// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableMapUpgradeable.sol";

import "../interfaces/IIbAlluo.sol";
import "../interfaces/IAdapter.sol";
import "../interfaces/IExchange.sol";
import "hardhat/console.sol";

contract LiquidityHandler is
    Initializable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable {

    using Address for address;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableMapUpgradeable for EnumerableMapUpgradeable.AddressToUintMap;
    
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    //flag for upgrades availability
    bool public upgradeStatus;

    // full info about adapter
    struct AdapterInfo {
        string name; // USD Curve-Aave
        uint256 percentage; //500 == 5.00%
        address adapterAddress; // 0x..
        bool status; // active
    }

    EnumerableMapUpgradeable.AddressToUintMap private ibAlluoToAdapterId;
    mapping(uint256 => AdapterInfo) public adapterIdsToAdapterInfo;

    struct Withdrawal {
        // address of user that did withdrawal
        address user;
        // address of token that user chose to receive
        address token;
        // amount to recieve
        uint256 amount;
        // withdrawal time
        uint256 time;
        // Output token (Say, for ibAlluoETH, want withdrawal in USDC, then token is wETH and outputtoken is USDC);
        address outputToken;
    }

    struct WithdrawalSystem {
        mapping(uint256 => Withdrawal) withdrawals;
        uint256 lastWithdrawalRequest;
        uint256 lastSatisfiedWithdrawal;
        uint256 totalWithdrawalAmount;
        bool resolverTrigger;
    }

    mapping(address => WithdrawalSystem) public ibAlluoToWithdrawalSystems;

    // Address of the exchange used to convert non-supportedToken deposits and withdrawals
    address public exchangeAddress;
    uint256 public exchangeSlippage;

    //info about what adapter or iballuo
    event EnoughToSatisfy(
        address ibAlluo,
        uint256 inPoolAfterDeposit, 
        uint256 totalAmountInWithdrawals
    );

    event WithdrawalSatisfied(
        address ibAlluo,
        address indexed user, 
        address token, 
        uint256 amount, 
        uint256 queueIndex,
        uint256 satisfiedTime
    );

    event AddedToQueue(
        address ibAlluo,
        address indexed user, 
        address token, 
        uint256 amount,
        uint256 queueIndex,
        uint256 requestTime
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function initialize(address _multiSigWallet, address _exchangeAddress, uint256 _exchangeSlippage) public initializer {
        __Pausable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        require(_multiSigWallet.isContract(), "Handler: Not contract");
        exchangeAddress = _exchangeAddress;
        exchangeSlippage = _exchangeSlippage;
        _grantRole(DEFAULT_ADMIN_ROLE, _multiSigWallet);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, _multiSigWallet);
    }

    /** @notice Called by ibAlluo, deposits tokens into the adapter.
     * @dev Deposits funds, checks whether adapter is filled or insufficient, and then acts accordingly.
     ** @param _token Address of token (USDC, DAI, USDT...)
     ** @param _amount Amount of tokens in correct deimals (10**18 for DAI, 10**6 for USDT)
     */
    function deposit(address _token, uint256 _amount) external whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 amount18 = _amount * 10 ** (18 - ERC20Upgradeable(_token).decimals());

        uint256 inAdapter = getAdapterAmount(msg.sender);
        uint256 expectedAdapterAmount = getExpectedAdapterAmount(msg.sender, amount18);

        uint256 adapterId = ibAlluoToAdapterId.get(msg.sender);
        address adapter = adapterIdsToAdapterInfo[adapterId].adapterAddress;

        IERC20Upgradeable(_token).safeTransfer(adapter, _amount);
        if (inAdapter < expectedAdapterAmount) {
            if (expectedAdapterAmount < inAdapter + amount18) {
                uint256 toWallet = inAdapter + amount18 - expectedAdapterAmount;
                uint256 leaveInPool = amount18 - toWallet;

                IAdapter(adapter).deposit(_token, amount18, leaveInPool);

            } else {
                IAdapter(adapter).deposit(_token, amount18, amount18);
            }

        } else {
            IAdapter(adapter).deposit(_token, amount18, 0);
        }

        WithdrawalSystem storage withdrawalSystem = ibAlluoToWithdrawalSystems[msg.sender];

        if(withdrawalSystem.totalWithdrawalAmount > 0 && !withdrawalSystem.resolverTrigger){
            uint256 inAdapterAfterDeposit = getAdapterAmount(msg.sender);
            uint256 firstInQueueAmount = withdrawalSystem.withdrawals[withdrawalSystem.lastSatisfiedWithdrawal + 1].amount;
            if(firstInQueueAmount <= inAdapterAfterDeposit){
                withdrawalSystem.resolverTrigger = true;
                emit EnoughToSatisfy(msg.sender, inAdapterAfterDeposit, withdrawalSystem.totalWithdrawalAmount);
            }
        }
    }

    /** @notice Called by ibAlluo, withdraws tokens from the adapter.
    * @dev Attempt to withdraw. If there are insufficient funds, you are added to the queue.
    ** @param _user Address of depositor 
    ** @param _token Address of token (USDC, DAI, USDT...)
    ** @param _amount Amount of tokens in 10**18
    */
    function withdraw(address _user, address _token, uint256 _amount) external whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE){
        uint256 inAdapter = getAdapterAmount(msg.sender);

        WithdrawalSystem storage withdrawalSystem = ibAlluoToWithdrawalSystems[msg.sender];
        if (inAdapter >= _amount && withdrawalSystem.totalWithdrawalAmount == 0) {
            uint256 adapterId = ibAlluoToAdapterId.get(msg.sender);
            address adapter = adapterIdsToAdapterInfo[adapterId].adapterAddress;
            IAdapter(adapter).withdraw(_user, _token, _amount);
            emit WithdrawalSatisfied(msg.sender, _user, _token, _amount, 0, block.timestamp);


        } 
        else {
            // Need to start with lastWithdrawalRequest+1 because ex.)
            // lastSatisfied = 0    lastRequest = 0
            // lastSatisfied = 0     lastRequest = 1
            // In satisfy function, it always starts with
            // lastSatisfied + 1 --> So there are errors!
            // Alternative: Can start at 0 here and change line 194 to + 0 instead.
            uint256 lastWithdrawalRequest = withdrawalSystem.lastWithdrawalRequest;
            withdrawalSystem.lastWithdrawalRequest++;
            withdrawalSystem.withdrawals[lastWithdrawalRequest+1] = Withdrawal({
                user: _user,
                token: _token,
                amount: _amount,
                time: block.timestamp,
                outputToken: _token
            });
            withdrawalSystem.totalWithdrawalAmount += _amount;
            emit AddedToQueue(msg.sender, _user, _token, _amount, lastWithdrawalRequest+1, block.timestamp);
        }
    
    }

    function _withdrawThroughExchange(address _mainToken, address _targetToken, uint256 _amount18, address _user  ) internal {
        uint256 amountinMainTokens = _amount18 * 10**ERC20Upgradeable(_mainToken).decimals() / 10**18;
        IERC20Upgradeable(_mainToken).approve(exchangeAddress, type(uint256).max);
        uint256 amountinTargetTokens = IExchange(exchangeAddress).exchange(_mainToken, _targetToken, amountinMainTokens,0);
        IERC20Upgradeable(_targetToken).transfer(_user, amountinTargetTokens);
    }
    // Same function as above but overload for case when you want to withdraw in a different token native to an ibAlluo.
    // For example: Withdraw USDC from ibAlluoEth.
    function withdraw(address _user, address _token, uint256 _amount, address _outputToken) external whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE){
        uint256 inAdapter = getAdapterAmount(msg.sender);

        WithdrawalSystem storage withdrawalSystem = ibAlluoToWithdrawalSystems[msg.sender];
        if (inAdapter >= _amount && withdrawalSystem.totalWithdrawalAmount == 0) {
            uint256 adapterId = ibAlluoToAdapterId.get(msg.sender);
            address adapter = adapterIdsToAdapterInfo[adapterId].adapterAddress;
            if (_token != _outputToken) {
                IAdapter(adapter).withdraw(address(this), _token, _amount);
                _withdrawThroughExchange(_token, _outputToken, _amount, _user);
            } else {
                IAdapter(adapter).withdraw(_user, _token, _amount);
            }
            emit WithdrawalSatisfied(msg.sender, _user, _token, _amount, 0, block.timestamp);


        } 
        else {
            // Need to start with lastWithdrawalRequest+1 because ex.)
            // lastSatisfied = 0    lastRequest = 0
            // lastSatisfied = 0     lastRequest = 1
            // In satisfy function, it always starts with
            // lastSatisfied + 1 --> So there are errors!
            // Alternative: Can start at 0 here and change line 194 to + 0 instead.
            uint256 lastWithdrawalRequest = withdrawalSystem.lastWithdrawalRequest;
            withdrawalSystem.lastWithdrawalRequest++;
            withdrawalSystem.withdrawals[lastWithdrawalRequest+1] = Withdrawal({
                user: _user,
                token: _token,
                amount: _amount,
                time: block.timestamp,
                outputToken: _outputToken
            });
            withdrawalSystem.totalWithdrawalAmount += _amount;
            emit AddedToQueue(msg.sender, _user, _token, _amount, lastWithdrawalRequest+1, block.timestamp);
        }
    
    }

    function satisfyAdapterWithdrawals(address _ibAlluo) public whenNotPaused{
        WithdrawalSystem storage withdrawalSystem = ibAlluoToWithdrawalSystems[_ibAlluo];
        uint256 lastWithdrawalRequest =  withdrawalSystem.lastWithdrawalRequest;
        uint256 lastSatisfiedWithdrawal = withdrawalSystem.lastSatisfiedWithdrawal;

        if (lastWithdrawalRequest != lastSatisfiedWithdrawal) {
            uint256 inAdapter = getAdapterAmount(_ibAlluo);
            while (lastSatisfiedWithdrawal != lastWithdrawalRequest) {
                Withdrawal memory withdrawal = withdrawalSystem.withdrawals[lastSatisfiedWithdrawal+1];
                uint adapterId = ibAlluoToAdapterId.get(_ibAlluo);
                address adapter = adapterIdsToAdapterInfo[adapterId].adapterAddress;
                if (withdrawal.amount <= inAdapter) {
                    if (withdrawal.outputToken != withdrawal.token) {
                        IAdapter(adapter).withdraw(address(this), withdrawal.token, withdrawal.amount);
                        _withdrawThroughExchange(withdrawal.token, withdrawal.outputToken, withdrawal.amount, withdrawal.user);
                    } else {
                        IAdapter(adapter).withdraw(withdrawal.user, withdrawal.token, withdrawal.amount);
                    }
                    inAdapter -= withdrawal.amount;
                    withdrawalSystem.totalWithdrawalAmount -= withdrawal.amount;
                    withdrawalSystem.lastSatisfiedWithdrawal++;
                    lastSatisfiedWithdrawal++;
                    withdrawalSystem.resolverTrigger = false;

                    emit WithdrawalSatisfied(
                        _ibAlluo,
                        withdrawal.user, 
                        withdrawal.token, 
                        withdrawal.amount, 
                        lastSatisfiedWithdrawal,
                        block.timestamp
                    );
                } else {
                    break;
                }
            }
        }
    }

    function satisfyAllWithdrawals() external whenNotPaused{
        for(uint i = 0; i < ibAlluoToAdapterId.length(); i++){
            (address ibAlluo,) = ibAlluoToAdapterId.at(i);
            satisfyAdapterWithdrawals(ibAlluo);
        }
    }

    function getAdapterAmount(address _ibAlluo) public view returns(uint256) {
        uint256 adapterId = ibAlluoToAdapterId.get(_ibAlluo);
        address adapter = adapterIdsToAdapterInfo[adapterId].adapterAddress;

        return IAdapter(adapter).getAdapterAmount();
    }

    function getExpectedAdapterAmount(address _ibAlluo, uint256 _newAmount) public view returns(uint256) {

        uint256 adapterId = ibAlluoToAdapterId.get(_ibAlluo);
        uint256 percentage = adapterIdsToAdapterInfo[adapterId].percentage;

        uint256 totalWithdrawalAmount = ibAlluoToWithdrawalSystems[_ibAlluo].totalWithdrawalAmount;
        
        return (_newAmount + IIbAlluo(_ibAlluo).totalAssetSupply()) * percentage / 10000 + totalWithdrawalAmount;
    }

    function getAdapterId(address _ibAlluo) external view returns(uint256){
        return ibAlluoToAdapterId.get(_ibAlluo);
    }

    function getListOfIbAlluos()external view returns(address[] memory){
        uint256 numberOfIbAlluos = ibAlluoToAdapterId.length();
        address[] memory ibAlluos = new address[](numberOfIbAlluos);
        for(uint i = 0; i < numberOfIbAlluos; i++){
            (ibAlluos[i],) = ibAlluoToAdapterId.at(i);
        }
        return ibAlluos;
    }

    function getLastAdapterIndex() public view returns(uint256){
        uint256 counter = 1;
        while(true){
            if(adapterIdsToAdapterInfo[counter].adapterAddress == address(0)){
                counter--;
                break;
            }
            else{
                counter++;
            }
        }
        return counter;
    }

    function getActiveAdapters() external view returns(AdapterInfo[] memory, address[] memory){
        uint256 numberOfIbAlluos = ibAlluoToAdapterId.length();
        address[] memory ibAlluos = new address[](numberOfIbAlluos);
        uint256[] memory adaptersId = new uint256[](numberOfIbAlluos);
        AdapterInfo[] memory adapters = new AdapterInfo[](numberOfIbAlluos);
        for(uint i = 0; i < numberOfIbAlluos; i++){
            (ibAlluos[i], adaptersId[i]) = ibAlluoToAdapterId.at(i);
            adapters[i] = adapterIdsToAdapterInfo[adaptersId[i]];
        }
        return (adapters, ibAlluos);
    }

    function getAllAdapters() external view returns(AdapterInfo[] memory){
        uint256 numberOfAllAdapters = getLastAdapterIndex();
        AdapterInfo[] memory adapters = new AdapterInfo[](numberOfAllAdapters);
        for(uint i = 0; i < numberOfAllAdapters; i++){
            adapters[i] = adapterIdsToAdapterInfo[i+1];
        }
        return adapters;
    }

    function ibAlluoLastWithdrawalCheck(address _ibAlluo) public view returns (uint256[3] memory) {
        WithdrawalSystem storage _ibAlluoWithdrawalSystem = ibAlluoToWithdrawalSystems[_ibAlluo];
        return [_ibAlluoWithdrawalSystem.lastWithdrawalRequest, _ibAlluoWithdrawalSystem.lastSatisfiedWithdrawal, _ibAlluoWithdrawalSystem.totalWithdrawalAmount];
    }

    ////////////

    function setIbAlluoToAdapterId(address _ibAlluo, uint256 _adapterId) external onlyRole(DEFAULT_ADMIN_ROLE){
        ibAlluoToAdapterId.set(_ibAlluo, _adapterId);
    }

    function grantIbAlluoPermissions(address _ibAlluo) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(DEFAULT_ADMIN_ROLE, _ibAlluo);
    }
    
    function setAdapter(
        uint256 _id, 
        string memory _name, 
        uint256 _percentage,
        address _adapterAddress,
        bool _status
    )external onlyRole(DEFAULT_ADMIN_ROLE){
        require(_id != 0, "Handler: !allowed 0 id");
        AdapterInfo storage adapter = adapterIdsToAdapterInfo[_id];

        adapter.name = _name;
        adapter.percentage = _percentage;
        adapter.adapterAddress = _adapterAddress;
        adapter.status = _status;
    }

    function changeAdapterStatus(
        uint256 _id, 
        bool _status
    )external onlyRole(DEFAULT_ADMIN_ROLE){
        adapterIdsToAdapterInfo[_id].status = _status;
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function grantRole(bytes32 role, address account)
    public
    override
    onlyRole(getRoleAdmin(role)) {
        if (role == DEFAULT_ADMIN_ROLE) {
            require(account.isContract(), "Handler: Not contract");
        }
        _grantRole(role, account);
    }

    /**
     * @dev admin function for removing funds from contract
     * @param _address address of the token being removed
     * @param _amount amount of the token being removed
     */
    function removeTokenByAddress(address _address, address _to, uint256 _amount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        IERC20Upgradeable(_address).safeTransfer(_to, _amount);
    }

    function changeUpgradeStatus(bool _status)
    external
    onlyRole(DEFAULT_ADMIN_ROLE) {
        upgradeStatus = _status;
    }

    function _authorizeUpgrade(address newImplementation)
    internal
    onlyRole(UPGRADER_ROLE)
    override {
        require(upgradeStatus, "Handler: Upgrade not allowed");
        upgradeStatus = false;
    }
}

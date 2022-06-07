// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "../../interfaces/curve/ICurvePoolUSD.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


contract LiquidityBufferVault is
    Initializable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable 
{
    using AddressUpgradeable for address;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // admin and reserves address
    address public wallet;

    // address of main contract with which users will interact  
    address public alluoLp;

    // AAVE curve pool
    ICurvePoolUSD public curvePool;

    //flag for upgrades availability
    bool public upgradeStatus;

    //flag for chainlink keepers that withdrawal can be satisfied 
    bool public keepersTrigger;

    // size of the acceptable slippage with 2 decimals
    // 125 = 1.25%
    uint32 public slippage;

    // percent of total alluoLp value which will go to curve pool
    // 525 = 5.25%
    uint32 public bufferPercentage;

    // amount which needed to satisfy all users in withdrawal list
    uint256 public totalWithdrawalAmount;

    // max waiting withdrawals time after which them should be satisfyed
    uint256 public maxWaitingTime;

    struct Withdrawal {
        // address of user that did withdrawal
        address user;
        // address of token that user chose to receive
        address token;
        // amount to recieve
        uint256 amount;
        // withdrawal time
        uint256 time;
    }

    // list of withrawals in queue
    mapping(uint256 => Withdrawal) public withdrawals;

    // index of last withdrawal in queue
    uint256 public lastWithdrawalRequest;
    // index of last satisfied withdrawal in queue
    uint256 public lastSatisfiedWithdrawal;

    // acceptable by alluoLp and curve tokens as deposit
    IERC20Upgradeable public DAI;
    IERC20Upgradeable public USDC;
    IERC20Upgradeable public USDT;

    event EnoughToSatisfy(
        uint256 inPoolAfterDeposit, 
        uint256 totalAmountInWithdrawals
    );

    event WithrawalSatisfied(
        address indexed user, 
        address token, 
        uint256 amount, 
        uint256 queueIndex,
        uint256 satisfiedTime
    );

    event AddedToQueue(
        address indexed user, 
        address token, 
        uint256 amount,
        uint256 queueIndex,
        uint256 requestTime
    );


    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function initialize(address _multiSigWallet, address _alluoLp, address _curvePool) public initializer {
        __Pausable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        require(_multiSigWallet.isContract(), "Buffer: Not contract");

        _grantRole(DEFAULT_ADMIN_ROLE, _multiSigWallet);
        _grantRole(DEFAULT_ADMIN_ROLE, _alluoLp);
        _grantRole(UPGRADER_ROLE, _multiSigWallet);

        wallet = _multiSigWallet;
        bufferPercentage = 500;
        slippage = 200;
        curvePool = ICurvePoolUSD(_curvePool);
        alluoLp = _alluoLp;

        maxWaitingTime = 3600 * 23;
    }

    // allow curve pool to pull DAI, USDT and USDC from the buffer.
    function approveAll() external whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE){
        DAI = IERC20Upgradeable(0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063);
        USDC = IERC20Upgradeable(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
        USDT = IERC20Upgradeable(0xc2132D05D31c914a87C6611C10748AEb04B58e8F);

        DAI.safeApprove(address(curvePool), type(uint256).max);
        USDC.safeApprove(address(curvePool), type(uint256).max);
        USDT.safeApprove(address(curvePool), type(uint256).max);
    }

    // function checks how much in buffer now and hom much should be
    // fills buffer and sends to wallet what left (conveting it to usdc)
    function deposit(address _token, uint256 _amount) external whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) {

        uint256 inPool = getBufferAmount();

        if (IERC20Upgradeable(_token) == DAI) {
            uint256 lpAmount = curvePool.add_liquidity([_amount, 0, 0], 0, true);
            uint256 shouldBeInPool = getExpectedBufferAmount(_amount);
            if (inPool < shouldBeInPool) {

                if (shouldBeInPool < inPool + _amount) {
                    uint256 toWallet = inPool + _amount - shouldBeInPool;
                    uint256 toWalletIn6 = toWallet / 10 ** 12;
                    
                    curvePool.remove_liquidity_imbalance(
                        [0, toWalletIn6, 0],
                        toWallet * (10000 + slippage) / 10000,
                        true
                    );
                    USDC.safeTransfer(wallet, toWalletIn6);
                }
            } else {
                uint minAmountOut = _amount * (10000 - slippage) / 10000;

                uint256 toWallet = curvePool.remove_liquidity_one_coin(
                    lpAmount,
                    1,
                    minAmountOut / 10 ** 12,
                    true
                );
                USDC.safeTransfer(wallet, toWallet);
            }
        } else if (IERC20Upgradeable(_token) == USDC) {
            uint256 amountIn18 = _amount * 10 ** 12;
            uint256 shouldBeInPool = getExpectedBufferAmount(amountIn18);
            if (inPool < shouldBeInPool) {

                if (shouldBeInPool < inPool + amountIn18) {
                    uint256 toPoolIn18 = shouldBeInPool - inPool;
                    curvePool.add_liquidity(
                        [0, toPoolIn18 / 10 ** 12, 0],
                        0,
                        true
                    );
                    USDC.safeTransfer(wallet, (amountIn18 - toPoolIn18) / 10 ** 12);
                } else {
                    curvePool.add_liquidity([0, _amount, 0], 0, true);
                }
            } else {
                USDC.safeTransfer(wallet, _amount);
            }
        } 
        else {      //      _token == USDT
            uint256 amountIn18 = _amount * 10 ** 12;
            uint256 lpAmount = curvePool.add_liquidity([0, 0, _amount], 0, true);
            uint256 shouldBeInPool = getExpectedBufferAmount(amountIn18);
            if (inPool < shouldBeInPool) {

                if (shouldBeInPool < inPool + amountIn18) {
                    uint256 toWallet = inPool + amountIn18 - shouldBeInPool;
                    uint256 toWalletIn6 = toWallet / 10 ** 12;
                    curvePool.remove_liquidity_imbalance(
                        [0, toWalletIn6, 0],
                        toWallet * (10000 + slippage) / 10000,
                        true
                    );
                    USDC.safeTransfer(wallet, toWalletIn6);
                }
            } else {
                uint256 toWallet = curvePool.remove_liquidity_one_coin(
                    lpAmount,
                    1,
                    _amount * (10000 - slippage) / 10000,
                    true
                );
                USDC.safeTransfer(wallet, toWallet);
            }
        }

        if(lastWithdrawalRequest != lastSatisfiedWithdrawal && !keepersTrigger){
            uint256 inPoolNow = getBufferAmount();
            if(withdrawals[lastSatisfiedWithdrawal + 1].amount <= inPoolNow){
                keepersTrigger = true;
                emit EnoughToSatisfy(inPoolNow, totalWithdrawalAmount);
            }
        }

    }


    // function checks is in buffer enoght tokens to satisfy withdraw
    // or is queue empty, if so sending chosen tokens
    // if not adding withdrawal in queue
    function withdraw(address _user, address _token, uint256 _amount) external whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE){

        uint256 inPool = getBufferAmount();
        if (inPool > _amount && lastWithdrawalRequest == lastSatisfiedWithdrawal) {
            uint256 toUser;

            if (IERC20Upgradeable(_token) == DAI) {
                curvePool.remove_liquidity_imbalance(
                    [_amount, 0, 0], 
                    _amount * (10000 + slippage) / 10000, 
                    true
                );
                toUser = _amount;
                DAI.safeTransfer(_user, toUser);
            } else if (IERC20Upgradeable(_token) == USDC) {
                // We want to be save agains arbitragers so at any withraw of USDT/USDC
                // contract checks how much will be burned curveLp by withrawing this amount in DAI
                // and passes this burned amount to get USDC/USDT
                uint256 toBurn = curvePool.calc_token_amount([_amount, 0, 0], false);
                uint256 amountIn6 = _amount / 10 ** 12;
                toUser = curvePool.remove_liquidity_one_coin(
                    toBurn, 
                    1, 
                    amountIn6 * (10000 - slippage) / 10000, 
                    true
                );
                USDC.safeTransfer(_user, toUser);
            } else {    //      _token == USDT
                
                uint256 toBurn = curvePool.calc_token_amount([_amount, 0, 0], false);
                uint256 amountIn6 = _amount / 10 ** 12;
                toUser = curvePool.remove_liquidity_one_coin(
                    toBurn, 
                    2, 
                    amountIn6 * (10000 - slippage) / 10000, 
                    true
                );
                USDT.safeTransfer(_user, toUser);
            }

            emit WithrawalSatisfied(_user, _token, toUser, 0, block.timestamp);
        } else {
            lastWithdrawalRequest++;
            uint256 timeNow = block.timestamp;
            withdrawals[lastWithdrawalRequest] = Withdrawal({
                user: _user,
                token: _token,
                amount: _amount,
                time: timeNow
            });
            totalWithdrawalAmount += _amount;
            emit AddedToQueue(_user, _token, _amount, lastWithdrawalRequest, timeNow);
        }
    }

    // function for satisfaction withdrawals in queue
    // triggered by BE or chainlink keepers  
    function satisfyWithdrawals() external whenNotPaused{
        if (lastWithdrawalRequest != lastSatisfiedWithdrawal) {

            uint256 inPool = getBufferAmount();
            while (lastSatisfiedWithdrawal != lastWithdrawalRequest) {
                Withdrawal memory withdrawal = withdrawals[lastSatisfiedWithdrawal + 1];
                uint256 amount = withdrawal.amount;
                if (amount <= inPool) {
                    
                    uint256 toUser;

                    if (IERC20Upgradeable(withdrawal.token) == DAI) {

                        curvePool.remove_liquidity_imbalance(
                            [amount, 0, 0], 
                            amount * (10000 + slippage) / 10000, 
                            true
                        );
                        toUser = amount;
                        DAI.safeTransfer(withdrawal.user, toUser);
                    } else if (IERC20Upgradeable(withdrawal.token) == USDC) {
                        uint256 toBurn = curvePool.calc_token_amount([amount, 0, 0], false);
                        uint256 amountIn6 = amount / 10 ** 12;
                        toUser = curvePool.remove_liquidity_one_coin(
                            toBurn, 
                            1, 
                            amountIn6 * (10000 - slippage) / 10000, 
                            true
                        );
                        USDC.safeTransfer(withdrawal.user, toUser);
                    } 
                    else {     //      _token == USDT
                        uint256 toBurn = curvePool.calc_token_amount([amount, 0, 0], false);
                        uint256 amountIn6 = amount / 10 ** 12;
                        toUser = curvePool.remove_liquidity_one_coin(
                            toBurn, 
                            2, 
                            amountIn6 * (10000 - slippage) / 10000, 
                            true
                        );
                        USDT.safeTransfer(withdrawal.user, toUser);
                    }
                    
                    inPool -= amount;
                    totalWithdrawalAmount -= amount;
                    lastSatisfiedWithdrawal++;
                    keepersTrigger = false;
                    
                    emit WithrawalSatisfied(
                        withdrawal.user, 
                        withdrawal.token, 
                        toUser, 
                        lastSatisfiedWithdrawal,
                        block.timestamp
                    );

                } else {
                    break;
                }
            }
        }
    }

    function setSlippage(uint32 _newSlippage) external onlyRole(DEFAULT_ADMIN_ROLE) {
        slippage = _newSlippage;
    }

    function setBufferPersentage(uint32 _newPercentage) external onlyRole(DEFAULT_ADMIN_ROLE) {
        bufferPercentage = _newPercentage;
    }

    function getExpectedBufferAmount(uint256 _newAmount) public view returns(uint256) {
        return (_newAmount + ERC20(alluoLp).totalSupply()) * bufferPercentage / 10000 + totalWithdrawalAmount;
    }

    function getBufferAmount() public view returns(uint256) {
        uint256 curveLp = IERC20(curvePool.lp_token()).balanceOf(address(this));

        if(curveLp != 0){
            return curvePool.calc_withdraw_one_coin(curveLp, 0);
        }
        return 0;
    }

    function setWallet(address newWallet)
    external
    onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newWallet.isContract(), "Buffer: Not contract");

        wallet = newWallet;
    }

    function setCurvePool(address newPool)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(newPool.isContract(), "Buffer: Not contract");

        curvePool = ICurvePoolUSD(newPool);

    }

    function setAlluoLp(address newAlluoLp)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(newAlluoLp.isContract(), "Buffer: Not contract");
        _grantRole(DEFAULT_ADMIN_ROLE, newAlluoLp);
        _revokeRole(DEFAULT_ADMIN_ROLE, alluoLp);
        alluoLp = newAlluoLp;
    }

    function setWaitingTime(address newAlluoLp)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(newAlluoLp.isContract(), "Buffer: Not contract");
        _grantRole(DEFAULT_ADMIN_ROLE, newAlluoLp);
        _revokeRole(DEFAULT_ADMIN_ROLE, alluoLp);
        alluoLp = newAlluoLp;
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
        onlyRole(getRoleAdmin(role))
    {
        if(role == DEFAULT_ADMIN_ROLE){
            require(account.isContract(), "Buffer: Not contract");
        }
        _grantRole(role, account);
    }


    function changeUpgradeStatus(bool _status)
    external
    onlyRole(DEFAULT_ADMIN_ROLE) {
        upgradeStatus = _status;
    }

    function getWithdrawalPosition(uint256 _index) external view returns(uint256){
        if(_index != 0 && _index <= lastWithdrawalRequest && _index > lastSatisfiedWithdrawal ){
            return _index - lastSatisfiedWithdrawal;
        }
        else{
            return 0;
        }
    }

    function isUserWaiting(address _user) external view returns(bool){
        if(lastWithdrawalRequest != lastSatisfiedWithdrawal){
            for(uint i = lastSatisfiedWithdrawal + 1; i <= lastWithdrawalRequest; i++){
                if(withdrawals[i].user == _user){
                    return true;
                }
            }
        }
        return false;
    }

    function getUserActiveWithdrawals(address _user) external view returns(uint256[] memory){
        if(lastWithdrawalRequest != lastSatisfiedWithdrawal){
            uint256 userRequestAmount;
            for(uint i = lastSatisfiedWithdrawal + 1; i <= lastWithdrawalRequest; i++){
                if(withdrawals[i].user == _user){
                    userRequestAmount++;
                }
            }
            uint256[] memory indexes = new uint256[](userRequestAmount);
            uint256 counter;
            for(uint i = lastSatisfiedWithdrawal + 1; i <= lastWithdrawalRequest; i++){
                if(withdrawals[i].user == _user){
                    indexes[counter] = i;
                    counter++;
                }
            }
            return indexes;
        }
        uint256[] memory empty;
        return empty;
    }

    function getCloseToLimitWithdrawals()external view returns(uint256[] memory, uint256 amount){
        if(lastWithdrawalRequest != lastSatisfiedWithdrawal){
            uint256 counter;
            for(uint i = lastSatisfiedWithdrawal + 1; i <= lastWithdrawalRequest; i++){
                if(withdrawals[i].time >= maxWaitingTime){
                    amount += withdrawals[i].amount;
                    counter++;
                }
            }
            uint256[] memory indexes = new uint256[](counter);
            if(counter !=0){
                uint256 newCounter;
                for(uint i = lastSatisfiedWithdrawal + 1; i <= lastSatisfiedWithdrawal + counter; i++){
                    indexes[newCounter] = i;
                    newCounter++;
                }
            }
            return (indexes, amount);
        }
        uint256[] memory empty;
        return (empty, 0);
    }

    function removeTokenByAddress(address _address, uint256 _amount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(_address != address(0), "Invalid token address");
        IERC20Upgradeable(_address).safeTransfer(msg.sender, _amount);
    }


    function _authorizeUpgrade(address newImplementation)
    internal
    onlyRole(UPGRADER_ROLE)
    override {
        require(upgradeStatus, "Buffer: Upgrade not allowed");
        upgradeStatus = false;
    }
}

import { parseEther, parseUnits } from "@ethersproject/units";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BigNumber, BigNumberish, BytesLike } from "ethers";
import { ethers, network, upgrades } from "hardhat";
import { before } from "mocha";
import { TestERC20, TestERC20__factory, LiquidityBufferUSDAdaptor, LiquidityBufferUSDAdaptor__factory, IERC20, PseudoMultisigWallet, PseudoMultisigWallet__factory , AlluoLpV3, AlluoLpV3__factory, LiquidityBufferVault, LiquidityBufferVault__factory, LiquidityBufferVaultForTests__factory, LiquidityBufferVaultForTests,  IbAlluo, IbAlluo__factory, IbAlluoV2, LiquidityBufferVaultV2, IbAlluoV2__factory, LiquidityBufferVaultV2__factory, IbAlluoUSD, LiquidityBufferVaultV3, USDAdaptor, IbAlluoUSD__factory, LiquidityBufferVaultV3__factory, USDAdaptor__factory, EURAdaptor, EURAdaptor__factory} from "../../typechain";

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

async function skipDays(d: number) {
    ethers.provider.send('evm_increaseTime', [d * 86400]);
    ethers.provider.send('evm_mine', []);
}

function getRandomArbitrary(min: number, max: number) {
    return Math.floor(Math.random() * (max - min) + min);
  }

async function  prepareCallData(type: string, parameters: any[]) : Promise<BytesLike>{
    if(type == "status"){
        let ABI = ["function changeUpgradeStatus(bool _status)"];
        let iface = new ethers.utils.Interface(ABI);
        let calldata = iface.encodeFunctionData("changeUpgradeStatus", [parameters[0]]);
        return calldata;
    }
    else if(type == "role"){
        let ABI = ["function grantRole(bytes32 role, address account)"];
        let iface = new ethers.utils.Interface(ABI);
        let calldata = iface.encodeFunctionData("grantRole", [parameters[0], parameters[1]]);
        return calldata;
    }
    else{
        return ethers.utils.randomBytes(0);
    }
}


describe("IbAlluo and Buffer", function () {
    let signers: SignerWithAddress[];
    let whale: SignerWithAddress;
    let curveLpHolder: SignerWithAddress;

    let alluoLpV3: AlluoLpV3;
    let ibAlluoUSD: IbAlluoUSD;
    let ibAlluoEUR: IbAlluoUSD;

    let multisig: PseudoMultisigWallet;
    let buffer: LiquidityBufferVaultV3;

    let dai: IERC20, usdc: IERC20, usdt: IERC20;
    let curveLpUSD: IERC20;

    let jeur: IERC20,  eurt: IERC20, eurs: IERC20;
    let curveLpEUR: IERC20;

    let jeurwhale: SignerWithAddress;
    let eurswhale : SignerWithAddress;
    let eurtwhale: SignerWithAddress;

    let adaptorEUR: EURAdaptor;


    let adaptorUSD: USDAdaptor;

    before(async function () {

        //We are forking Polygon mainnet, please set Alchemy key in .env
        await network.provider.request({
            method: "hardhat_reset",
            params: [{
                forking: {
                    enabled: true,
                    jsonRpcUrl: process.env.POLYGON_FORKING_URL as string,
                    //you can fork from last block by commenting next line
                    // blockNumber: 26313740, 
                },
            },],
        });

        signers = await ethers.getSigners();
        const whaleAddress = "0x075e72a5eDf65F0A5f44699c7654C1a76941Ddc8";
        const curveLpHolderAddress = "0xa0f2e2f7b3ab58e3e52b74f08d94ae52778d46df";

        const jeurWhale = "0x2c1cb163a00733cf773b828a77ea347cb0fc91b4"
        const eursWhale = "0x1bee4f735062cd00841d6997964f187f5f5f5ac9"
        const eurtWhale = "0x0e57f58cc5eb3674c4738074362a3d9d82ca7648"
        await ethers.provider.send(
            'hardhat_impersonateAccount',
            [whaleAddress]
        );

        await ethers.provider.send(
            'hardhat_impersonateAccount',
            [curveLpHolderAddress]
        );


        await ethers.provider.send(
            'hardhat_impersonateAccount',
            [jeurWhale]
        );

        await ethers.provider.send(
            'hardhat_impersonateAccount',
            [eursWhale]
        );
        await ethers.provider.send(
            'hardhat_impersonateAccount',
            [eurtWhale]
        );

        
        whale = await ethers.getSigner(whaleAddress);
        curveLpHolder = await ethers.getSigner(curveLpHolderAddress);
        dai = await ethers.getContractAt("IERC20", "0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063");
        usdc = await ethers.getContractAt("IERC20", "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174");
        usdt = await ethers.getContractAt("IERC20", "0xc2132D05D31c914a87C6611C10748AEb04B58e8F");
        curveLpUSD = await ethers.getContractAt("IERC20", "0xE7a24EF0C5e95Ffb0f6684b813A78F2a3AD7D171");

        jeurwhale = await ethers.getSigner(jeurWhale);
        eurswhale = await ethers.getSigner(eursWhale);
        eurtwhale = await ethers.getSigner(eurtWhale);
        jeur = await ethers.getContractAt("IERC20", "0x4e3Decbb3645551B8A19f0eA1678079FCB33fB4c");
        eurt = await ethers.getContractAt("IERC20", "0x7BDF330f423Ea880FF95fC41A280fD5eCFD3D09f");
        eurs = await ethers.getContractAt("IERC20", "0xE111178A87A3BFf0c8d18DECBa5798827539Ae99");

        console.log("We are forking Polygon mainnet\n");
        expect(await dai.balanceOf(whale.address)).to.be.gt(0, "Whale has no DAI, or you are not forking Polygon");

        expect(await jeur.balanceOf(jeurwhale.address)).to.be.gt(0, "Whale has no jeur, or you are not forking Polygon");
        expect(await eurs.balanceOf(eurswhale.address)).to.be.gt(0, "Whale has no eurs, or you are not forking Polygon");
        expect(await eurt.balanceOf(eurtwhale.address)).to.be.gt(0, "Whale has no eurt, or you are not forking Polygon");
        await signers[0].sendTransaction({
            to: eurswhale.address,
            value: parseEther("100.0")
        });
        await signers[0].sendTransaction({
            to: jeurwhale.address,
            value: parseEther("100.0")
        });
        await signers[0].sendTransaction({
            to: eurtwhale.address,
            value: parseEther("100.0")
        });

        await signers[0].sendTransaction({
            to: whale.address,
            value: parseEther("100.0")
        });
    });


    beforeEach(async function () {
        const IbAlluo = await ethers.getContractFactory("IbAlluoUSD") as IbAlluoUSD__factory;
        //We are using this contract to simulate Gnosis multisig wallet
        const Multisig = await ethers.getContractFactory("PseudoMultisigWallet") as PseudoMultisigWallet__factory;
        //For tests we are using version of contract with hardhat console.log, to see all Txn
        //you can switch two next lines and turn off logs
        // const Buffer = await ethers.getContractFactory("LiquidityBufferVaultForTests") as LiquidityBufferVaultForTests__factory;
        const Buffer = await ethers.getContractFactory("LiquidityBufferVaultV3") as LiquidityBufferVaultV3__factory;
        const AdaptorUSD = await ethers.getContractFactory("USDAdaptor") as USDAdaptor__factory;
        const AdaptorEUR = await ethers.getContractFactory("EURAdaptor") as EURAdaptor__factory;


        multisig = await Multisig.deploy(true);

        await upgrades.silenceWarnings();
        buffer = await upgrades.deployProxy(Buffer,
            [multisig.address, multisig.address,],
            {initializer: 'initialize', kind:'uups',unsafeAllow: ['delegatecall']},
        ) as LiquidityBufferVaultV3;

        ibAlluoUSD = await upgrades.deployProxy(IbAlluo,
            [multisig.address,
            buffer.address,
            [dai.address,
            usdc.address,
            usdt.address]],
            {initializer: 'initialize', kind:'uups'}
        ) as IbAlluoUSD;

        ibAlluoEUR = await upgrades.deployProxy(IbAlluo,
            [multisig.address,
            buffer.address,
            [jeur.address,
            eurt.address,
            eurs.address]],
            {initializer: 'initialize', kind:'uups'}
        ) as IbAlluoUSD;
        
        adaptorUSD = await AdaptorUSD.deploy(multisig.address, buffer.address);
        adaptorEUR = await AdaptorEUR.deploy(multisig.address, buffer.address);

        // Necessary info for adaptor:
        // multisig.address, curvePool, dai.address, usdc.address, usdt.address
        let ABI;
        let iface;
        let calldata;

        expect(await ibAlluoUSD.liquidityBuffer()).equal(buffer.address);
        await ibAlluoUSD.migrateStep2();


        expect(await ibAlluoEUR.liquidityBuffer()).equal(buffer.address);
        await ibAlluoEUR.migrateStep2();


        // 
        ABI = ["function registerAdapter(string calldata _name, address _AdapterAddress, uint256 _percentage, bool _status, address _ibAlluo, uint256 _AdapterId)"];
        iface = new ethers.utils.Interface(ABI);
        calldata = iface.encodeFunctionData("registerAdapter", ["CurvePool", adaptorUSD.address, 0, true, ibAlluoUSD.address, 1]);
        await multisig.executeCall(buffer.address, calldata);


        ABI = ["function setSlippage ( uint32 _newSlippage )"];
        iface = new ethers.utils.Interface(ABI);
        calldata = iface.encodeFunctionData("setSlippage", [300] );
        await multisig.executeCall(adaptorUSD.address, calldata);

        ABI = ["function registerAdapter(string calldata _name, address _AdapterAddress, uint256 _percentage, bool _status, address _ibAlluo, uint256 _AdapterId)"];
        iface = new ethers.utils.Interface(ABI);
        calldata = iface.encodeFunctionData("registerAdapter", ["CurvePool", adaptorEUR.address, 0, true, ibAlluoEUR.address, 2]);
        await multisig.executeCall(buffer.address, calldata);


        ABI = ["function setSlippage ( uint32 _newSlippage )"];
        iface = new ethers.utils.Interface(ABI);
        calldata = iface.encodeFunctionData("setSlippage", [300] );
        await multisig.executeCall(adaptorEUR.address, calldata);

        // 

        ABI = [" function setIbAlluoArray(address[] calldata _ibAlluoArray)"];
        iface = new ethers.utils.Interface(ABI);
        calldata = iface.encodeFunctionData("setIbAlluoArray", [[ibAlluoUSD.address, ibAlluoEUR.address]] );
        await multisig.executeCall(buffer.address, calldata);

        let tokenArrayUSD = [dai.address, usdc.address, usdt.address];
        let tokenArrayEUR = [jeur.address, eurt.address, eurs.address];

        ABI = ["function setIbAlluoMappings(address _ibAlluo, address[] calldata _inputTokens, uint256 _AdaptorId )"];
        iface = new ethers.utils.Interface(ABI);
        calldata = iface.encodeFunctionData("setIbAlluoMappings", [ibAlluoUSD.address, tokenArrayUSD, 1] );
        await multisig.executeCall(buffer.address, calldata);
        calldata = iface.encodeFunctionData("setIbAlluoMappings", [ibAlluoEUR.address, tokenArrayEUR, 2] );
        await multisig.executeCall(buffer.address, calldata);

        

        ABI = ["function grantIbAlluoPermissions(address _ibAlluo)"];
        iface = new ethers.utils.Interface(ABI);
        calldata = iface.encodeFunctionData("grantIbAlluoPermissions", [ibAlluoUSD.address] );
        await multisig.executeCall(buffer.address, calldata);
        calldata = iface.encodeFunctionData("grantIbAlluoPermissions", [ibAlluoEUR.address] );
        await multisig.executeCall(buffer.address, calldata);


        tokenArrayUSD.forEach( async token => {
            ABI = ["function setTokenToAdapter (address _token, uint256 _AdapterId)"];
            iface = new ethers.utils.Interface(ABI);
            calldata = iface.encodeFunctionData("setTokenToAdapter", [token, 1] );
            await multisig.executeCall(buffer.address, calldata);
        })

        await adaptorUSD.AdaptorApproveAll();

        tokenArrayEUR.forEach( async token => {
            ABI = ["function setTokenToAdapter (address _token, uint256 _AdapterId)"];
            iface = new ethers.utils.Interface(ABI);
            calldata = iface.encodeFunctionData("setTokenToAdapter", [token, 2] );
            await multisig.executeCall(buffer.address, calldata);
        })

        await adaptorEUR.AdaptorApproveAll();

    });

    
    describe('USD and EUR Adaptor with IbAlluoV2: Test cases', function () {
        it("Depositing 100 jeur and immediately attempting to withdraw 50 should put you in the waiting list", async function () {
            await deposit(signers[0], jeur, parseEther("100"));
            await ibAlluoEUR.connect(signers[0]).withdraw(jeur.address, parseEther("50"));
            let withdrawalArray = await buffer.ibAlluoLastWithdrawalCheck(ibAlluoEUR.address)
            expect(withdrawalArray[0]).not.equal(withdrawalArray[1]);
        })
        it("Depositing 100 jeur, attempt to withdraw 50 and then only get paid after there is a deposit", async function () {
            await deposit(signers[0], jeur, parseEther("100"));
            await ibAlluoEUR.connect(signers[0]).withdraw(jeur.address, parseEther("50"));
            let withdrawalArray = await buffer.ibAlluoLastWithdrawalCheck(ibAlluoEUR.address)
            expect(withdrawalArray[0]).not.equal(withdrawalArray[1]);
            
            await deposit(signers[1], jeur, parseEther("100"));
            await buffer.satisfyWithdrawals(ibAlluoEUR.address);
            // Loss from slippage makes tests awkward.

            expect(Number(await jeur.balanceOf(signers[0].address))).greaterThanOrEqual(Number(parseUnits("49", 18)))
        })

        it("Depositing 100 eurt and immediately attempting to withdraw 50 should put you in the waiting list", async function () {
            await deposit(signers[0], eurt, parseUnits("100", 6));
            await ibAlluoEUR.connect(signers[0]).withdraw(eurt.address, parseUnits("100", 18));
            let withdrawalArray = await buffer.ibAlluoLastWithdrawalCheck(ibAlluoEUR.address)
            expect(withdrawalArray[0]).not.equal(withdrawalArray[1]);
        })
        it("Depositing 100 eurt, attempt to withdraw 50 and then only get paid after there is a deposit", async function () {
            await deposit(signers[0], eurt, parseUnits("100", 6));
            await ibAlluoEUR.connect(signers[0]).withdraw(eurt.address, parseUnits("50", 18));
            let withdrawalArray = await buffer.ibAlluoLastWithdrawalCheck(ibAlluoEUR.address)
            expect(withdrawalArray[0]).not.equal(withdrawalArray[1]);
            
            await deposit(signers[1], eurt, parseUnits("100", 6));
            await buffer.satisfyWithdrawals(ibAlluoEUR.address);
            expect(Number(await eurt.balanceOf(signers[0].address))).greaterThanOrEqual(Number(parseUnits("49", 6)))
        })

        it("Depositing 100 eurs and immediately attempting to withdraw 50 should put you in the waiting list", async function () {
            await deposit(signers[0], eurs, parseUnits("100", 2));
            await ibAlluoEUR.connect(signers[0]).withdraw(eurs.address, parseUnits("50", 18));
            let withdrawalArray = await buffer.ibAlluoLastWithdrawalCheck(ibAlluoEUR.address)
            expect(withdrawalArray[0]).not.equal(withdrawalArray[1]);
        })
        it("Depositing 100 eurs, attempt to withdraw 50 and then only get paid after there is a deposit", async function () {
            await deposit(signers[0], eurs, parseUnits("100", 2));
            await ibAlluoEUR.connect(signers[0]).withdraw(eurs.address, parseUnits("50", 18));
            let withdrawalArray = await buffer.ibAlluoLastWithdrawalCheck(ibAlluoEUR.address)
            expect(withdrawalArray[0]).not.equal(withdrawalArray[1]);
            
            await deposit(signers[1], eurs, parseUnits("100", 2));
            await buffer.satisfyWithdrawals(ibAlluoEUR.address);
            expect(Number(await eurs.balanceOf(signers[0].address))).greaterThanOrEqual(Number(parseUnits("49", 2)))
        })

        it("The balance of the multisig wallet should increase with deposits.", async function () {
                let walletBalance = await eurt.balanceOf(multisig.address);

                await deposit(signers[0], jeur, parseEther("100"));
                expect(Number(await eurt.balanceOf(multisig.address))).greaterThan(Number(walletBalance))
                walletBalance = await eurt.balanceOf(multisig.address);


                await deposit(signers[0], eurt, parseUnits("100", 6));
                expect(Number(await eurt.balanceOf(multisig.address))).greaterThan(Number(walletBalance))
                walletBalance = await eurt.balanceOf(multisig.address);

                await deposit(signers[0], eurs, parseUnits("100", 2));
                expect(Number(await eurt.balanceOf(multisig.address))).greaterThan(Number(walletBalance))
                walletBalance = await eurt.balanceOf(multisig.address);

                await deposit(signers[0], jeur, parseEther("100"));
                expect(Number(await eurt.balanceOf(multisig.address))).greaterThan(Number(walletBalance))
                walletBalance = await eurt.balanceOf(multisig.address);


                await deposit(signers[0], eurt, parseUnits("100", 6));
                expect(Number(await eurt.balanceOf(multisig.address))).greaterThan(Number(walletBalance))
                walletBalance = await eurt.balanceOf(multisig.address);

                await deposit(signers[0], eurs, parseUnits("100", 2));
                expect(Number(await eurt.balanceOf(multisig.address))).greaterThan(Number(walletBalance))
                walletBalance = await eurt.balanceOf(multisig.address);

                await deposit(signers[0], jeur, parseEther("100"));
                expect(Number(await eurt.balanceOf(multisig.address))).greaterThan(Number(walletBalance))
                walletBalance = await eurt.balanceOf(multisig.address);


                await deposit(signers[0], eurt, parseUnits("100", 6));
                expect(Number(await eurt.balanceOf(multisig.address))).greaterThan(Number(walletBalance))
                walletBalance = await eurt.balanceOf(multisig.address);

                await deposit(signers[0], eurs, parseUnits("100", 2));
                expect(Number(await eurt.balanceOf(multisig.address))).greaterThan(Number(walletBalance))
                walletBalance = await eurt.balanceOf(multisig.address);

                console.log("Final multisig balance:", walletBalance);
    
            })
        it("Attemping to withdraw more than allowed causes revert.", async function () {
            let walletBalance = await eurt.balanceOf(multisig.address);
            await deposit(signers[1], eurt, parseUnits("100", 6));
            expect(Number(await eurt.balanceOf(multisig.address))).greaterThan(Number(walletBalance))
            await expect(ibAlluoEUR.connect(signers[1]).withdraw(eurt.address, parseUnits("500", 18))).to.be.revertedWith('ERC20: burn amount exceeds balance')
            })

            
    })
    describe('Mass deposits and withdrawal test cases', function () {
        it("Multiple deposits and withdrawals: Eventually, all withdrawers should be paid", async function () {
            let walletBalance = await eurt.balanceOf(multisig.address);

            await deposit(signers[0], jeur, parseEther("100"));
            expect(Number(await eurt.balanceOf(multisig.address))).greaterThan(Number(walletBalance))
            walletBalance = await eurt.balanceOf(multisig.address);


            await deposit(signers[1], eurt, parseUnits("100", 6));
            expect(Number(await eurt.balanceOf(multisig.address))).greaterThan(Number(walletBalance))
            walletBalance = await eurt.balanceOf(multisig.address);

            await deposit(signers[2], eurs, parseUnits("100", 2));
            expect(Number(await eurt.balanceOf(multisig.address))).greaterThan(Number(walletBalance))
            walletBalance = await eurt.balanceOf(multisig.address);

            await ibAlluoEUR.connect(signers[0]).withdraw(jeur.address, parseEther("50"));
            let withdrawalArray = await buffer.ibAlluoLastWithdrawalCheck(ibAlluoEUR.address)
            expect(withdrawalArray[0]).not.equal(withdrawalArray[1]);
            await ibAlluoEUR.connect(signers[1]).withdraw(eurt.address, parseUnits("50", 18));
            withdrawalArray = await buffer.ibAlluoLastWithdrawalCheck(ibAlluoEUR.address)
            expect(withdrawalArray[0]).not.equal(withdrawalArray[1]);
            await ibAlluoEUR.connect(signers[2]).withdraw(eurs.address,parseUnits("50", 18));
            withdrawalArray = await buffer.ibAlluoLastWithdrawalCheck(ibAlluoEUR.address)
            expect(withdrawalArray[0]).not.equal(withdrawalArray[1]);

            // When there are deposits, should pay everyone back.
            await deposit(signers[2], eurs, parseUnits("1000", 2));
            await buffer.satisfyWithdrawals(ibAlluoEUR.address);
            expect(Number(await eurt.balanceOf(multisig.address))).greaterThan(Number(walletBalance))

            expect(Number(await jeur.balanceOf(signers[0].address))).greaterThanOrEqual(Number(parseUnits("49", 18)))
            expect(Number(await eurt.balanceOf(signers[1].address))).greaterThanOrEqual(Number(parseUnits("49", 6)))
            expect(Number(await eurs.balanceOf(signers[2].address))).greaterThanOrEqual(Number(parseUnits("49", 2)))



            })


        it("Depositing 100 DAI and immediately attempting to withdraw 50 should put you in the waiting list", async function () {
            await deposit(signers[0], dai, parseEther("100"));
            await ibAlluoUSD.connect(signers[0]).withdraw(dai.address, parseEther("50"));
            let withdrawalArray = await buffer.ibAlluoLastWithdrawalCheck(ibAlluoUSD.address)
            expect(withdrawalArray[0]).not.equal(withdrawalArray[1]);
        })
        it("Depositing 100 DAI, attempt to withdraw 50 and then only get paid after there is a deposit", async function () {
            await deposit(signers[0], dai, parseEther("100"));
            await ibAlluoUSD.connect(signers[0]).withdraw(dai.address, parseEther("50"));
            let withdrawalArray = await buffer.ibAlluoLastWithdrawalCheck(ibAlluoUSD.address)
            expect(withdrawalArray[0]).not.equal(withdrawalArray[1]);

            await deposit(signers[1], dai, parseEther("100"));
            await buffer.satisfyWithdrawals(ibAlluoUSD.address);
            expect(await dai.balanceOf(signers[0].address)).equal(parseEther("50"))
        })

        it("Depositing 100 USDC and immediately attempting to withdraw 50 should put you in the waiting list", async function () {
            await deposit(signers[0], usdc, parseUnits("100", 6));
            await ibAlluoUSD.connect(signers[0]).withdraw(usdc.address, parseUnits("100", 18));
            let withdrawalArray = await buffer.ibAlluoLastWithdrawalCheck(ibAlluoUSD.address)
            expect(withdrawalArray[0]).not.equal(withdrawalArray[1]);
        })

        
        it("Depositing surplus USDC should not revert (Checking USD Adaptor Deposit function: Check toSend", async function () {
            await deposit(signers[0], usdc, parseUnits("100", 6));
            await deposit(signers[0], usdc, parseUnits("100", 6));
            await deposit(signers[0], usdc, parseUnits("100", 6));
            await deposit(signers[0], usdc, parseUnits("100", 6))
        })

        it("Depositing USDC when there is outstanding withdrawals (leaveInPool>0, toSend =0) should not revert (Checking USD Adaptor Deposit function: Check leaveInPool", async function () {
            await deposit(signers[0], usdc, parseUnits("10000", 6));
            await ibAlluoUSD.connect(signers[0]).withdraw(usdc.address, parseUnits("10000", 18));

            await deposit(signers[0], usdc, parseUnits("100", 6));

        })


        it("Depositing 100 USDC, attempt to withdraw 50 and then only get paid after there is a deposit", async function () {
            await deposit(signers[0], usdc, parseUnits("100", 6));
            await ibAlluoUSD.connect(signers[0]).withdraw(usdc.address, parseUnits("50", 18));
            let withdrawalArray = await buffer.ibAlluoLastWithdrawalCheck(ibAlluoUSD.address)
            expect(withdrawalArray[0]).not.equal(withdrawalArray[1]);
            
            await deposit(signers[1], usdc, parseUnits("100", 6));
            await buffer.satisfyWithdrawals(ibAlluoUSD.address);
            expect(Number(await usdc.balanceOf(signers[0].address))).greaterThanOrEqual(Number(parseUnits("49", 6)))
        })

        it("Depositing 100 USDT and immediately attempting to withdraw 50 should put you in the waiting list", async function () {
            await deposit(signers[0], usdt, parseUnits("100", 6));
            await ibAlluoUSD.connect(signers[0]).withdraw(usdt.address, parseUnits("50", 18));
            let withdrawalArray = await buffer.ibAlluoLastWithdrawalCheck(ibAlluoUSD.address)
            expect(withdrawalArray[0]).not.equal(withdrawalArray[1]);
        })
        it("Depositing 100 USDT, attempt to withdraw 50 and then only get paid after there is a deposit", async function () {
            await deposit(signers[0], usdt, parseUnits("100", 6));
            await ibAlluoUSD.connect(signers[0]).withdraw(usdt.address, parseUnits("50", 18));
            let withdrawalArray = await buffer.ibAlluoLastWithdrawalCheck(ibAlluoUSD.address)
            expect(withdrawalArray[0]).not.equal(withdrawalArray[1]);
            
            await deposit(signers[1], usdt, parseUnits("100", 6));
            await buffer.satisfyWithdrawals(ibAlluoUSD.address);

            expect(Number(await usdt.balanceOf(signers[0].address))).greaterThanOrEqual(Number(parseUnits("49", 6)))
        })

        it("The balance of the multisig wallet should increase with deposits.", async function () {
                let walletBalance = await usdc.balanceOf(multisig.address);

                await deposit(signers[0], dai, parseEther("100"));
                expect(Number(await usdc.balanceOf(multisig.address))).greaterThan(Number(walletBalance))
                walletBalance = await usdc.balanceOf(multisig.address);


                await deposit(signers[0], usdc, parseUnits("100", 6));
                expect(Number(await usdc.balanceOf(multisig.address))).greaterThan(Number(walletBalance))
                walletBalance = await usdc.balanceOf(multisig.address);

                await deposit(signers[0], usdt, parseUnits("100", 6));
                expect(Number(await usdc.balanceOf(multisig.address))).greaterThan(Number(walletBalance))
                walletBalance = await usdc.balanceOf(multisig.address);

                await deposit(signers[0], dai, parseEther("100"));
                expect(Number(await usdc.balanceOf(multisig.address))).greaterThan(Number(walletBalance))
                walletBalance = await usdc.balanceOf(multisig.address);


                await deposit(signers[0], usdc, parseUnits("100", 6));
                expect(Number(await usdc.balanceOf(multisig.address))).greaterThan(Number(walletBalance))
                walletBalance = await usdc.balanceOf(multisig.address);

                await deposit(signers[0], usdt, parseUnits("100", 6));
                expect(Number(await usdc.balanceOf(multisig.address))).greaterThan(Number(walletBalance))
                walletBalance = await usdc.balanceOf(multisig.address);

                await deposit(signers[0], dai, parseEther("100"));
                expect(Number(await usdc.balanceOf(multisig.address))).greaterThan(Number(walletBalance))
                walletBalance = await usdc.balanceOf(multisig.address);


                await deposit(signers[0], usdc, parseUnits("100", 6));
                expect(Number(await usdc.balanceOf(multisig.address))).greaterThan(Number(walletBalance))
                walletBalance = await usdc.balanceOf(multisig.address);

                await deposit(signers[0], usdt, parseUnits("100", 6));
                expect(Number(await usdc.balanceOf(multisig.address))).greaterThan(Number(walletBalance))
                walletBalance = await usdc.balanceOf(multisig.address);

                console.log("Final multisig balance:", walletBalance);
    
            })
        it("Attemping to withdraw more than allowed causes revert.", async function () {
            let walletBalance = await usdc.balanceOf(multisig.address);
            await deposit(signers[1], usdc, parseUnits("100", 6));
            expect(Number(await usdc.balanceOf(multisig.address))).greaterThan(Number(walletBalance))
            await expect(ibAlluoUSD.connect(signers[1]).withdraw(usdc.address, parseUnits("500", 18))).to.be.revertedWith('ERC20: burn amount exceeds balance')
            })

            
    })

    
    describe('Mass deposits and withdrawal test cases', function () {
        it("Multiple deposits and withdrawals: Eventually, all withdrawers should be paid", async function () {
            let walletBalance = await usdc.balanceOf(multisig.address);

            await deposit(signers[0], dai, parseEther("100"));
            expect(Number(await usdc.balanceOf(multisig.address))).greaterThan(Number(walletBalance))
            walletBalance = await usdc.balanceOf(multisig.address);


            await deposit(signers[1], usdc, parseUnits("100", 6));
            expect(Number(await usdc.balanceOf(multisig.address))).greaterThan(Number(walletBalance))
            walletBalance = await usdc.balanceOf(multisig.address);

            await deposit(signers[2], usdt, parseUnits("100", 6));
            expect(Number(await usdc.balanceOf(multisig.address))).greaterThan(Number(walletBalance))
            walletBalance = await usdc.balanceOf(multisig.address);

            await ibAlluoUSD.connect(signers[0]).withdraw(dai.address, parseEther("50"));
            let withdrawalArray = await buffer.ibAlluoLastWithdrawalCheck(ibAlluoUSD.address)
            expect(withdrawalArray[0]).not.equal(withdrawalArray[1]);

            await ibAlluoUSD.connect(signers[1]).withdraw(usdc.address, parseUnits("50", 18));
            withdrawalArray = await buffer.ibAlluoLastWithdrawalCheck(ibAlluoUSD.address)
            expect(withdrawalArray[0]).not.equal(withdrawalArray[1]);

            await ibAlluoUSD.connect(signers[2]).withdraw(usdt.address,parseUnits("50", 18));
            withdrawalArray = await buffer.ibAlluoLastWithdrawalCheck(ibAlluoUSD.address)
            expect(withdrawalArray[0]).not.equal(withdrawalArray[1]);    

            // When there are deposits, should pay everyone back.
            await deposit(signers[2], usdt, parseUnits("1000", 6));
            await buffer.satisfyWithdrawals(ibAlluoUSD.address);
            expect(Number(await usdc.balanceOf(multisig.address))).greaterThan(Number(walletBalance))

            expect(Number(await dai.balanceOf(signers[0].address))).greaterThanOrEqual(Number(parseUnits("49", 18)))
            expect(Number(await usdc.balanceOf(signers[1].address))).greaterThanOrEqual(Number(parseUnits("49", 6)))
            expect(Number(await usdt.balanceOf(signers[2].address))).greaterThanOrEqual(Number(parseUnits("49", 6)))



            })

            
    })

    async function deposit(recipient: SignerWithAddress, token: IERC20, amount: BigNumberish) {

        if (token == eurs) {
            await token.connect(eurswhale).transfer(recipient.address, amount);
            await token.connect(recipient).approve(ibAlluoEUR.address, amount);        
            await ibAlluoEUR.connect(recipient).deposit(token.address, amount);
        }
        else if (token == eurt) {
            await token.connect(eurtwhale).transfer(recipient.address, amount);
            await token.connect(recipient).approve(ibAlluoEUR.address, amount);        
            await ibAlluoEUR.connect(recipient).deposit(token.address, amount);
        }

        else if (token == jeur) {
            await token.connect(jeurwhale).transfer(recipient.address, amount);
            await token.connect(recipient).approve(ibAlluoEUR.address, amount);        
            await ibAlluoEUR.connect(recipient).deposit(token.address, amount);
        }
    
        else {
            await token.connect(whale).transfer(recipient.address, amount);
            await token.connect(recipient).approve(ibAlluoUSD.address, amount);        
            await ibAlluoUSD.connect(recipient).deposit(token.address, amount);
        }
    }

});
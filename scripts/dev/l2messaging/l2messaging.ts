import { BigNumber, Wallet } from "ethers";
import { ethers, upgrades } from "hardhat"
import * as dotenv from "dotenv";
import { GoerliSender } from "../../../typechain";

function newtonRaphson(APY: number) {
    const n = 3156000
    // const calcApprox = 1.000000024385628033745;
    const margin = 0.0000000000000000000001
    let error = 1
    let value = 1 
    let newValue =1 
    let numerator = 1 
    let denominator = 1 
    while (error > margin) {
        numerator =  (value**n - APY)
        denominator = (n*value**(n-1))
        newValue = value - numerator/ denominator
        error = Math.abs(newValue - value);
        value = newValue
        console.log(value)
    }
    return value;
}

async function main() {

    const interestPerSecond = BigNumber.from("10000002438562803");
    let mneumonic  = process.env.MNEMONIC
    

    const rinkebyContract = await ethers.getContractAt("RinkebySender","0xf2268ab2B9680036d158A1AF13B65CEF6f16c515");
    await rinkebyContract.setChild("0x4bD894CE0c9B907b3Ea1bd762221311bFAEE391D")

    if (typeof mneumonic === "string") {
        let wallet = Wallet.fromMnemonic(mneumonic)        
        let messageHash = ethers.utils.solidityKeccak256(['uint256'], [interestPerSecond]);
        var sig = await wallet.signMessage(ethers.utils.arrayify(messageHash));
        let entryData = ethers.utils.defaultAbiCoder.encode(["bytes32", "bytes", "uint256"], [messageHash, sig, interestPerSecond])
        await rinkebyContract.step1_initiateAnyCallSimple(entryData);
    }
   

}

async function checkHashing() {
    async function main() {
        // Deployed with custom ibAlluo contract
        // Change mumbaiChild address in contract before.
        const interestPerSecond = BigNumber.from("100000002438562803");
        let mneumonic  = process.env.MNEMONIC
        
        const testGoerliHashing = await ethers.getContractAt("TestGoerliHashing", "0x59DC254b68856A2578E496F668BF4E612f96a449")
    
        if (typeof mneumonic === "string") {
            let wallet = Wallet.fromMnemonic(mneumonic)        
            let messageHash = ethers.utils.solidityKeccak256(['uint256'], [interestPerSecond]);
            var sig = await wallet.signMessage(ethers.utils.arrayify(messageHash));
            console.log(wallet.address);
            let entryData = await testGoerliHashing.encodeParams(messageHash, sig, interestPerSecond)
            let dataBack = await testGoerliHashing.onStateReceive(entryData)
            console.log(dataBack);
        }
    }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

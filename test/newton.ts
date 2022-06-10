import { parseEther, parseUnits } from "@ethersproject/units";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BigNumber, BigNumberish, BytesLike } from "ethers";
import { ethers, network, upgrades } from "hardhat";
import { before } from "mocha";
// import { IERC20, PseudoMultisigWallet, PseudoMultisigWallet__factory, IbAlluo, IbAlluo__factory, LiquidityHandler, UsdCurveAdapter, LiquidityHandler__factory, UsdCurveAdapter__factory, EurCurveAdapter, EthNoPoolAdapter, EurCurveAdapter__factory, EthNoPoolAdapter__factory } from "../typechain";
const calcApprox = 1.000000024385628033745;


function getBaseLog(x: number, y: number) {
    return Math.log(y) / Math.log(x);
  }

      
describe("Test Newton-Raphson", function () {
    it("Test", async function() {
        const APY = 1.08 
        const n = 3156000
        const calcApprox = 1.000000024385628033745;
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
        console.log("final", value);
    })

    it("Another test", async function () {
        console.log(10**(getBaseLog(10,1.08)/31536000))

    })
})

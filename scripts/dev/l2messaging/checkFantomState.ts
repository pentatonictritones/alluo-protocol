import { BigNumber, Wallet } from "ethers";
import { ethers, upgrades } from "hardhat"
import * as dotenv from "dotenv";
import { GoerliSender } from "../../../typechain";


async function main() {

    const polygonChildAddress = "0x4bD894CE0c9B907b3Ea1bd762221311bFAEE391D"

    const polygonContract = await ethers.getContractAt("PolygonChild",polygonChildAddress);

 
    console.log("last caller", await polygonContract.lastCaller());
    console.log("message", await polygonContract.lastMessage())
    console.log("data", await polygonContract.lastData())
    console.log("id", await polygonContract.lastChainID())
    console.log("nonce", await polygonContract.lastNonce())


}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });


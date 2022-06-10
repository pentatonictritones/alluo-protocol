import { BigNumber } from "ethers";
import { ethers, upgrades } from "hardhat"
import * as dotenv from "dotenv";

async function main() {
    // Deployed with custom ibAlluo contract

    const PolygonChild = await ethers.getContractFactory("PolygonChild");
    let polygonChild = await PolygonChild.deploy()
    await polygonChild.deployed();
    console.log("Deployed on polygon at:", polygonChild.address)

}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });


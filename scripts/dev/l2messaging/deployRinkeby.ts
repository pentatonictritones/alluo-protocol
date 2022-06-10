import { BigNumber } from "ethers";
import { ethers, upgrades } from "hardhat"
import * as dotenv from "dotenv";


async function main() {
    const rinkebySender = await ethers.getContractFactory("RinkebySender");
    const RinkebySender = await rinkebySender.deploy();
    console.log("deployed RinkebySender", RinkebySender.address);
  
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });


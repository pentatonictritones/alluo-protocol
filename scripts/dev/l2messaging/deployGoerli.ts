import { BigNumber } from "ethers";
import { ethers, upgrades } from "hardhat"
import * as dotenv from "dotenv";


async function main() {
    // Deployed with custom ibAlluo contract
    // Change mumbaiChild address in contract before.
    const GoerliSender = await ethers.getContractFactory("GoerliSender");
    const goerliSender = await GoerliSender.deploy();
    console.log("deployed GoerliSender", goerliSender.address);
  
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

// npx hardhat node
//npx hardhat run scripts/dev/l2messaging/mumbaiContracts.ts --network mumbai

    // 100000000244041000
    
    // 100000002438562803
    // 100000000154712590
    // const interestPerSecond = newtonRaphson(1.08);
    // const interestPerSecond = BigNumber.from(100000002438562803);
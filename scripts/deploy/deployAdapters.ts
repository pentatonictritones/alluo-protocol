import { ethers, upgrades } from "hardhat"

async function main() {

  const UsdAdapter = await ethers.getContractFactory("UsdCurveAdapter");
  const EurAdapter = await ethers.getContractFactory("EurCurveAdapter");

  const gnosis = "0x2580f9954529853Ca5aC5543cE39E9B5B1145135";
  const handler = "0x31a3439Ac7E6Ea7e0C0E4b846F45700c6354f8c1";
  const slippage = 200;

  const usdAdapter = await UsdAdapter.deploy(gnosis, handler, slippage)
  console.log("UsdAdapter deployed to:", usdAdapter.address);

  const eurAdapter = await EurAdapter.deploy(gnosis, handler, slippage)
  console.log("EurAdapter deployed to:", eurAdapter.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

//npx hardhat run scripts/deploy/deployAdapters.ts --network polygon
//npx hardhat verify 0x4E01cA43b441fD76c5647e490532e47df7345B1b "0x2580f9954529853Ca5aC5543cE39E9B5B1145135" "0x31a3439Ac7E6Ea7e0C0E4b846F45700c6354f8c1" 200 --network polygon
//npx hardhat verify 0x2972a2D537f1d004707C14509a87a39068F21665 "0x2580f9954529853Ca5aC5543cE39E9B5B1145135" "0x31a3439Ac7E6Ea7e0C0E4b846F45700c6354f8c1" 200 --network polygon
//npx hardhat verify 0x57Ea02C5147b3A79b5Cc27Fd30C0D9501505bE0B "0x2580f9954529853Ca5aC5543cE39E9B5B1145135" "0x31a3439Ac7E6Ea7e0C0E4b846F45700c6354f8c1" --network polygon
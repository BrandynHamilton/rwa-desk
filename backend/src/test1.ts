// import { ethers } from "ethers";
// import fs from "fs";
// import path from "path";
// import dotenv from "dotenv";
// import { EncryptedERC__factory } from "../typechain-types"; // <-- import the factory

// dotenv.config({
//   path: path.resolve(__dirname, "../../.env"),
// });

// const main = async () => {
//   // Deployment addresses
//   const encryptedERC = "0x17E140974d66466401D362247A66d25AcedD0e01";

//   // Fuji USDC
//   const usdc = "0x5425890298aed601595a70AB815c96711D31Bc65";

//   // Load private key
//   const privateKey = process.env.PRIVATE_KEY;
//   if (!privateKey) throw new Error("PRIVATE_KEY not set in .env");

//   // Connect wallet
//   const provider = new ethers.JsonRpcProvider(
//     process.env.RPC_URL || "https://api.avax-test.network/ext/bc/C/rpc"
//   );
//   const wallet = new ethers.Wallet(privateKey, provider);
//   console.log("Using wallet:", wallet.address);

//   // ERC20 contract (still minimal ABI since we only call approve + balanceOf)
//   const erc20Contract = new ethers.Contract(
//     usdc,
//     [
//       "function approve(address spender, uint256 amount) public returns (bool)",
//       "function balanceOf(address account) public view returns (uint256)",
//     ],
//     wallet
//   );

//   // Use TypeChain factory for EncryptedERC
//   const converter = EncryptedERC__factory.connect(encryptedERC, wallet);

//   console.log("Converter contract address:", converter.target);

//   // Approve
//   const amount = ethers.parseUnits("1", 6); // USDC has 6 decimals
//   console.log(`Approving ${amount} USDC to converter...`);
//   const approveTx = await erc20Contract.approve(converter.target, amount); // use .target if using v6 factory
//   await approveTx.wait();
//   console.log("Approved.");

//   // Mint
//   console.log(`Converting 1 USDC to eUSDC...`);
//   const mintTx = await converter.privateMint(amount);
//   await mintTx.wait();
//   console.log("Conversion complete!");

//   // Balances
//   const erc20Balance = await erc20Contract.balanceOf(wallet.address);
//   const eerc20Balance = await converter.balanceOf(wallet.address);

//   console.log(`Wallet USDC balance: ${ethers.formatUnits(erc20Balance, 6)}`);
//   console.log(`Wallet eUSDC balance: ${ethers.formatUnits(eerc20Balance, 18)}`);
// };

// main().catch((error) => {
//   console.error(error);
//   process.exitCode = 1;
// });

"use strict";
var __awaiter = (this && this.__awaiter) || function (thisArg, _arguments, P, generator) {
    function adopt(value) { return value instanceof P ? value : new P(function (resolve) { resolve(value); }); }
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
        function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
        function step(result) { result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected); }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
};
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const ethers_1 = require("ethers");
const path_1 = __importDefault(require("path"));
const dotenv_1 = __importDefault(require("dotenv"));
const typechain_types_1 = require("../typechain-types"); // <-- import the factory
dotenv_1.default.config({
    path: path_1.default.resolve(__dirname, "../../.env"),
});
const main = () => __awaiter(void 0, void 0, void 0, function* () {
    // Deployment addresses
    const encryptedERC = "0x17E140974d66466401D362247A66d25AcedD0e01";
    // Fuji USDC
    const usdc = "0x5425890298aed601595a70AB815c96711D31Bc65";
    // Load private key
    const privateKey = process.env.PRIVATE_KEY;
    if (!privateKey)
        throw new Error("PRIVATE_KEY not set in .env");
    // Connect wallet
    const provider = new ethers_1.ethers.JsonRpcProvider(process.env.RPC_URL || "https://api.avax-test.network/ext/bc/C/rpc");
    const wallet = new ethers_1.ethers.Wallet(privateKey, provider);
    console.log("Using wallet:", wallet.address);
    // ERC20 contract (still minimal ABI since we only call approve + balanceOf)
    const erc20Contract = new ethers_1.ethers.Contract(usdc, [
        "function approve(address spender, uint256 amount) public returns (bool)",
        "function balanceOf(address account) public view returns (uint256)",
    ], wallet);
    // Use TypeChain factory for EncryptedERC
    const converter = typechain_types_1.EncryptedERC__factory.connect(encryptedERC, wallet);
    console.log("Converter contract address:", converter.target);
    // Approve
    const amount = ethers_1.ethers.parseUnits("1", 6); // USDC has 6 decimals
    console.log(`Approving ${amount} USDC to converter...`);
    const approveTx = yield erc20Contract.approve(converter.target, amount); // use .target if using v6 factory
    yield approveTx.wait();
    console.log("Approved.");
    // Mint
    console.log(`Converting 1 USDC to eUSDC...`);
    const mintTx = yield converter.privateMint(amount);
    yield mintTx.wait();
    console.log("Conversion complete!");
    // Balances
    const erc20Balance = yield erc20Contract.balanceOf(wallet.address);
    const eerc20Balance = yield converter.balanceOf(wallet.address);
    console.log(`Wallet USDC balance: ${ethers_1.ethers.formatUnits(erc20Balance, 6)}`);
    console.log(`Wallet eUSDC balance: ${ethers_1.ethers.formatUnits(eerc20Balance, 18)}`);
});
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});

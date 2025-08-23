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
// src/register-wallet.ts
const ethers_1 = require("ethers");
const path_1 = __importDefault(require("path"));
const dotenv_1 = __importDefault(require("dotenv"));
const typechain_types_1 = require("../typechain-types");
const src_1 = require("../../EncryptedERC/src"); // adjust path
dotenv_1.default.config({ path: path_1.default.resolve(__dirname, "../../.env") });
function main() {
    return __awaiter(this, void 0, void 0, function* () {
        const registrarAddr = "0xe7Bfc67C48912E9db35d6443458fe63d72F091F7"; // TODO: Registrar address on Fuji
        const privateKey = process.env.PRIVATE_KEY;
        if (!privateKey)
            throw new Error("PRIVATE_KEY not set");
        const provider = new ethers_1.ethers.JsonRpcProvider(process.env.RPC_URL || "https://api.avax-test.network/ext/bc/C/rpc");
        const wallet = new ethers_1.ethers.Wallet(privateKey, provider);
        console.log("Using wallet:", wallet.address);
        // Attach Registrar contract
        const registrar = typechain_types_1.Registrar__factory.connect(registrarAddr, wallet);
        //   Generate proof (project helper)
        const proof = yield (0, src_1.generateRegistrationProof)(wallet.privateKey);
        console.log("Proof:", proof);
        //   Submit proof
        const tx = yield registrar.register(proof);
        yield tx.wait();
        console.log("Wallet registered!");
    });
}
main().catch((err) => {
    console.error(err);
    process.exit(1);
});

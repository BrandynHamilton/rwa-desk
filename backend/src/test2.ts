import { ethers, zkit } from "hardhat";
import * as fs from "fs";
import * as path from "path";
import dotenv from "dotenv";
import { poseidon3 } from "poseidon-lite";
import { deriveKeysFromUser } from "../../eerc-backend-converter/src/utils";
import type { RegistrationCircuit } from "../../generated-types/zkit";

dotenv.config({ path: path.resolve(__dirname, "../../.env") });

const main = async () => {
    // Load private key from .env
    const privateKey = process.env.PRIVATE_KEY;
    if (!privateKey) throw new Error("❌ PRIVATE_KEY missing in .env");

    const provider = new ethers.JsonRpcProvider(
        process.env.RPC_URL || "https://api.avax-test.network/ext/bc/C/rpc"
    );
    const wallet = new ethers.Wallet(privateKey, provider);
    const userAddress = await wallet.getAddress();

    // Load deployment addresses (registrar + encryptedERC + usdc, etc.)
    const deploymentPath = path.join(
        __dirname,
        "../../EncryptedERC/deployments/converter/latest-converter.json"
    );
    const deploymentData = JSON.parse(fs.readFileSync(deploymentPath, "utf8"));

    const registrarAddress = deploymentData.contracts.registrar;
    console.log("🔧 Registering user in EncryptedERC using zkit...");
    console.log("Registrar:", registrarAddress);
    console.log("User to register:", userAddress);

    // Connect to Registrar
    const registrar = await ethers.getContractAt("Registrar", registrarAddress, wallet);

    // 1. Check if already registered
    const isRegistered = await registrar.isUserRegistered(userAddress);
    if (isRegistered) {
        console.log("✅ User is already registered");
        return;
    }

    // 2. Derive zk-friendly keys from ETH key
    const { privateKey: babyJubPriv, formattedPrivateKey, publicKey } =
        await deriveKeysFromUser(userAddress, wallet);

    // 3. Generate registration hash
    const chainId = await provider.getNetwork().then(net => net.chainId);
    const registrationHash = poseidon3([
        BigInt(chainId),
        formattedPrivateKey,
        BigInt(userAddress),
    ]);

    console.log("Chain ID:", chainId.toString());
    console.log("Registration Hash:", registrationHash.toString());

    // 4. Generate proof using zkit
    console.log("🔐 Generating registration proof using zkit...");
    const circuit = await zkit.getCircuit("RegistrationCircuit");
    const registrationCircuit = circuit as unknown as RegistrationCircuit;

    const input = {
        SenderPrivateKey: formattedPrivateKey,
        SenderPublicKey: [publicKey[0], publicKey[1]],
        SenderAddress: BigInt(userAddress),
        ChainID: BigInt(chainId),
        RegistrationHash: registrationHash,
    };

    console.log("📋 Circuit inputs:", input);

    const proof = await registrationCircuit.generateProof(input);
    const calldata = await registrationCircuit.generateCalldata(proof);

    // 5. Call the contract
    console.log("📝 Registering in the contract...");
    const registerTx = await registrar.register(calldata);
    await registerTx.wait();
    console.log("✅ User registered successfully!");

    // 6. Verify registration
    const isNowRegistered = await registrar.isUserRegistered(userAddress);
    const userPublicKey = await registrar.getUserPublicKey(userAddress);
    console.log("Verification:");
    console.log("- Registered:", isNowRegistered);
    console.log("- Public key X:", userPublicKey[0].toString());
    console.log("- Public key Y:", userPublicKey[1].toString());

    // 7. Save BabyJub keys for later (needed for mint/transfer proofs)
    const userKeys = {
        address: userAddress,
        privateKey: {
            raw: babyJubPriv.toString(),
            formatted: formattedPrivateKey.toString(),
        },
        publicKey: {
            x: publicKey[0].toString(),
            y: publicKey[1].toString(),
        },
        registrationHash: registrationHash.toString(),
    };

    const keysPath = path.join(__dirname, "../../deployments/converter/user-keys.json");
    fs.writeFileSync(keysPath, JSON.stringify(userKeys, null, 2));
    console.log("🔑 User keys saved to:", keysPath);
};

main().catch((error) => {
    console.error("❌ Script failed:", error);
    process.exitCode = 1;
});

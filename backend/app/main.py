from fastapi import FastAPI, Request, HTTPException, BackgroundTasks
from fastapi.responses import FileResponse
from flask import request
from pydantic import BaseModel
from web3 import Web3
import os
from dotenv import load_dotenv
import threading
import asyncio
import json
import time

load_dotenv()

WEB3_PROVIDER = os.getenv("GATEWAY")  # or local/testnet
USDC_ADDRESS = os.getenv("USDC_ADDRESS")  # USDC on Avalanche Fuji

current_dir = os.path.dirname(os.path.abspath(__file__))

print(F'current_dir: {current_dir}')

# ABI Paths 
erc20_abi_path = os.path.join(current_dir, "..", "..", "backend", "abi", "erc20_abi.json")
erc20_abi_path = os.path.abspath(erc20_abi_path)

print("Looking for ERC20 ABI at:", erc20_abi_path)
# RWADesk ABI
rwa_desk_abi_path = os.path.join(current_dir, "..", "..", "contracts", "out", "RWADesk.sol", "RWADesk.json")

# RWAToken (MockERC721) ABI
erc721_abi_path = os.path.join(current_dir, "..", "..", "contracts", "out", "MockERC721.sol", "RWAToken.json")

# Environment Variables
RWA_DESK_ADDRESS = os.getenv("RWA_DESK_ADDRESS")
RWA_TOKEN_ADDRESS = os.getenv("RWA_TOKEN_ADDRESS")
DESK_PRIVATE_KEY = os.getenv("DESK_PRIVATE_KEY")
ISSUER_PRIVATE_KEY = os.getenv("ISSUER_PRIVATE_KEY")

with open(erc20_abi_path, "r") as abi_file:
    ERC20_ABI = abi_file.read()

with open(rwa_desk_abi_path) as f:
    rwa_artifact = json.load(f)
RWA_DESK_ABI = rwa_artifact["abi"]

with open(erc721_abi_path, "r") as f:
    erc721_artifact = json.load(f)
ERC721_ABI = erc721_artifact["abi"]

# Initialize Web3
w3 = Web3(Web3.HTTPProvider(WEB3_PROVIDER))
evm_account = w3.eth.account.from_key(DESK_PRIVATE_KEY)

# Contracts
usdc_contract = w3.eth.contract(address=USDC_ADDRESS, abi=ERC20_ABI)
rwa_desk_contract = w3.eth.contract(address=RWA_DESK_ADDRESS, abi=RWA_DESK_ABI)
erc721_contract = w3.eth.contract(address=RWA_TOKEN_ADDRESS, abi=ERC721_ABI)

# Set default account
EVM_ADDRESS = evm_account.address
w3.eth.default_account = EVM_ADDRESS

app = FastAPI()

def load_last_block(key, default, cache):
    """
    Load last block from cache (e.g., Redis, disk cache).
    Returns `default` if not found or invalid.
    """
    try:
        val = cache.get(key)
        if val is not None:
            return int(val)
    except Exception:
        pass
    return default

def reset_last_block(key, new_value, cache):
    cache.set(key, str(new_value))

def save_last_block(key, block_number, cache):
    """
    Save last block to cache.
    """
    try:
        cache.set(key, str(block_number))
    except Exception as e:
        print(f"[ERROR] Failed to save last block {key}: {e}")

def start_network_validator_listener(network, private_key, config, ALCHEMY_API_KEY, offchain_db, last_blocks_cache, ev_func):
    print(f"[{network.upper()}] Connecting...")
    w3, account = network_func(network=network, ALCHEMY_API_KEY=ALCHEMY_API_KEY, PRIVATE_KEY=private_key)

    registry_contracts = config[network]["registry_addresses"]
    abi_map = config[network]["abis"]

    print(f"[{network.upper()}] Connected to {w3.provider.endpoint_uri} as {account.address}")

    threading.Thread(
        target=network_validator_listener,
        args=(network, w3, registry_contracts, abi_map, offchain_db, last_blocks_cache, ev_func),
        daemon=True
    ).start()

def network_validator_listener(network, w3, registry_contracts, abi_map, offchain_db, cache, ev_func):
    seen_logs = set()
    last_block_key = f"{network}_all_contracts"
    last_block = load_last_block(last_block_key, w3.eth.block_number - 1, cache)

    # Prepare contract instances for all registries except ValidatorRegistry
    contracts = []
    for registry_name, registry_address in registry_contracts.items():
        if registry_name == "ValidatorRegistry":
            continue
        abi = abi_map[registry_name]
        contract = w3.eth.contract(address=registry_address, abi=abi)
        contracts.append((registry_name, contract))

    print(f"[{network.upper()}] Listening to {len(contracts)} contracts from block {last_block + 1}")

    while True:
        try:
            current_block = w3.eth.block_number
            if current_block > last_block:
                for registry_name, contract in contracts:
                    for event_name, handler in [
                        ("PostProof", ev_func),
                        # add other events & handlers if needed here
                    ]:
                        try:
                            logs = getattr(contract.events, event_name).get_logs(
                                from_block=last_block + 1,
                                to_block=current_block
                            )
                        except ValueError as e:
                            err = e.args[0]
                            if isinstance(err, dict) and err.get("code") == -32000:
                                print(f"[{network.upper()}] ⚠️ Pruned block; skipping to {current_block}")
                                last_block = current_block
                                continue
                            raise

                        for ev in logs:
                            tx_hash = ev['transactionHash'].hex()
                            idx = ev['logIndex']
                            dedupe_key = (network, tx_hash, idx)
                            if dedupe_key in seen_logs:
                                continue
                            seen_logs.add(dedupe_key)
                            handler(ev, offchain_db)

                last_block = current_block
                save_last_block(last_block_key, last_block, cache)

            time.sleep(3)
        except Exception as e:
            print(f"[{network.upper()}] ⚠️ Listener error: {e}")
            time.sleep(5)

@app.get("/")
async def root():
    return {"message": "Welcome to the RWA Desk API"}



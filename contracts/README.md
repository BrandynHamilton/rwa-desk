# RWA Desk - Real-World Asset OTC Desk

## Overview

**RWA Desk** is a suite of smart contracts built in Solidity for managing over-the-counter (OTC) transactions of real-world assets (RWA) in a secure and transparent manner. The project leverages OpenZeppelin libraries for safe asset handling, access control, and reentrancy protection.

This system allows sellers to escrow ERC20 or ERC721 assets, accept bids in USDC, manage refunds for losing bidders, and release the asset to the winning bidder.

---

## Contracts

### 1. RWADesk

- **File:** `src/RWADesk.sol`
- **Description:** Main OTC desk contract that handles escrow of ERC20/721 assets, bidding, and closing of escrows.
- **Key Features:**
  - Initialize escrow with ERC20 or ERC721 assets.
  - Post minimum valuations for assets.
  - Accept and track bids in USDC.
  - Close escrow, transfer winning funds to seller, refund losing bidders, and release assets to winners.
  - Cancel escrow under specified conditions.
  - Uses OpenZeppelin `Ownable` and `ReentrancyGuard` for security.
- **Events:**
  - `EscrowInitialized`
  - `ValuationPosted`
  - `BidPlaced`
  - `EscrowClosed`
  - `EscrowCanceled`
  - `AssetReleased`
- **Enums & Structs:**
  - `AssetType` – differentiates ERC20 vs ERC721.
  - `Escrow` – stores escrow metadata, bids, and asset information.

---

### 2. WhitelistRegistry

- **File:** `src/WhitelistRegistry.sol`
- **Description:** Simple whitelist management for addresses allowed to participate in the OTC desk.
- **Features:**
  - Add/remove addresses from whitelist.
  - Check if an address is whitelisted.
  - Only owner can manage the whitelist.

---

### 3. RWAToken

- **File:** `src/MockERC721.sol`
- **Description:** Mock ERC721 token representing real-world assets.
- **Features:**
  - ERC721 token with burnable functionality.
  - `safeMint` function to mint new tokens.
  - `Ownable` access control for minting.

---

## Getting Started

### Prerequisites

- Foundry (https://book.getfoundry.sh/)
- Solidity 0.8.27+
- Node.js (optional, for scripts)

### Installation

1. Clone the repository:

```bash
git clone <repo-url>
cd rwa-desk-contracts
```

2. Install dependencies:

```bash
forge install OpenZeppelin/openzeppelin-contracts
```

---

### Build

Compile all contracts:

```bash
forge build
```

---

### Deploy

Deploy `RWADesk`:

```bash
forge create \
  --rpc-url <RPC_URL> \
  --private-key <PRIVATE_KEY> \
  --constructor-args <USDC_TOKEN_ADDRESS> \
  src/RWADesk.sol:RWADesk \
  --broadcast
```

Deploy `WhitelistRegistry`:

```bash
forge create \
  --rpc-url <RPC_URL> \
  --private-key <PRIVATE_KEY> \
  src/WhitelistRegistry.sol:WhitelistRegistry \
  --broadcast
```

Deploy `RWAToken` (Mock ERC721):

```bash
forge create \
  --rpc-url <RPC_URL> \
  --private-key <PRIVATE_KEY> \
  --constructor-args <OWNER_ADDRESS> \
  src/MockERC721.sol:RWAToken \
  --broadcast
```

---

### Testing

Run all tests:

```bash
forge test
```

---

## Project Structure

```
rwa-desk-contracts/
├─ src/                  # Solidity source files
│  ├─ RWADesk.sol
│  ├─ WhitelistRegistry.sol
│  └─ MockERC721.sol
├─ lib/                  # Installed dependencies (OpenZeppelin, forge-std)
├─ out/                  # Compiled artifacts (ignore in git)
├─ foundry.toml          # Foundry project configuration
└─ README.md
```

---

## Notes

- The `lib/` folder should be added to `.gitignore` as it contains dependencies that can be re-installed.
- All funds are managed in USDC; ensure the USDC token address corresponds to the correct network.
- Access control is enforced via `Ownable`. Only the desk owner can post valuations, cancel escrows, or manage the whitelist.

---

## Author

**Brandyn Hamilton (RWA Desk Team)**

---

## License

MIT License

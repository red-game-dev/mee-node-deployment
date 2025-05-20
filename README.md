## 📘 Biconomy Light SDK – Local Test Setup & Execution Guide

This guide walks through setting up a local mainnet fork, verifying contract availability, and running a transaction via the Biconomy SDK.

---

## 🧱 Prerequisites

Make sure the following tools are installed:

* [Node.js](https://nodejs.org/) (v16 or higher)
* [Foundry (cast, anvil)](https://book.getfoundry.sh/)
* [Docker & Docker Compose](https://docs.docker.com/compose/)
* [jq](https://stedolan.github.io/jq/) (optional, for JSON parsing)

---

## 📁 Project Structure Assumptions

```
.
├── docker-compose.yml
├── scripts/
│   ├── fork-anvil.sh
│   ├── verify-fork.sh
├── src/
│   └── index.ts - SDK integration and transaction code, based if sdk will intalize or not, else will use traditonal ethers.
├── package.json
```

---

## 🧪 Step-by-Step Instructions

---

### 1. ✅ Fork Mainnet Locally via Anvil

This script forks Ethereum mainnet using your Alchemy/Infura RPC and runs Anvil locally on port `8545`.

```bash
npm run fork:mainnet
```

☑️ **What it does**:

* Loads `.env` to read `MAINNET_RPC_URL`
* Starts anvil with:

  * chain ID = 1
  * block number = `22243923` (important to ensure factory contract exists)
  * impersonation and large balances enabled

📌 **Output should include:**

```
Anvil is running! The local RPC URL is: http://localhost:8545
```

---

### 2. ✅ Verify the Forked Node Matches Expectations

Run the verification script to ensure fork is pointing to correct block and chain ID:

```bash
npm run verify:fork
```

☑️ This may include checks like:

* Block number ≥ `22243923`
* Chain ID = `1`
* Returns contract code for system contracts

---

### 3. ✅ Ensure Biconomy Smart Account Factory Contract Is Deployed

This confirms the smart account factory is available at its expected address (`0x000000001D1D5004a02bAfAb9de2D6CE5b7B13de`):

```bash
npm run verify:contract:available
```

☑️ **Expected output:**

* Contract bytecode (starts with `0x6080...`)
* **Not** `0x` (which means no contract deployed)

---

### 4. ✅ Start Local MEE Node (Bundler)

This runs the Biconomy MEE Bundler locally using Docker:

```bash
npm run docker:start
```

☑️ What it does:

* Builds the bundler container with `docker-compose`
* Exposes JSON-RPC API on `http://localhost:3000`

📌 Ensure that your forked Anvil and Docker container are both running before proceeding.

---

### 5. ✅ Make a Biconomy Smart Account Transaction

Run your task runner script inside `./src` to:

* Initialize a Smart Account
* Transfer USDC from whale to admin EOA
* Send USDC from Smart Account to AAVE
* Receive aUSDC in Smart Account
* Send aUSDC back to EOA

```bash
npm run make:transaction
```

☑️ This will:

* Check balance and fund the EOA
* Deploy smart account (if needed)
* Perform approvals and interaction with AAVE
* Validate everything via logs

📌 **Watch the logs for:**

```bash
✅ Smart Account aUSDC balance after: ...
✅ Successfully transferred aUSDC back to EOA
=== MEE INTEGRATION COMPLETED SUCCESSFULLY ===
```

---

## 🔄 Troubleshooting

| Issue                               | Solution                                                     |
| ----------------------------------- | ------------------------------------------------------------ |
| `Cannot POST /v3`                   | Use `MEE_NODE_URL=http://localhost:3000` (no `/v3`)          |
| `computeAccountAddress returned 0x` | Ensure block number is ≥ `22243923` and chain ID is `1`      |
| Docker fails                        | Try `docker-compose down` first and ensure port 3000 is free |
| EOA has no ETH                      | Add ETH via `anvil` config or impersonate an ETH whale       |

---

## 📦 package.json (for reference)

```json
{
  "name": "Biconomy-light-sdk",
  "version": "1.0.0",
  "description": "Biconomy MEE task demonstration",
  "main": "index.js",
  "scripts": {
    "docker:start": "docker-compose down && docker-compose build --no-cache && docker-compose up -d",
    "fork:mainnet": "bash ./scripts/fork-anvil.sh",
    "verify:fork": "bash ./scripts/verify-fork.sh",
    "verify:contract:available": "cast code 0x000000001D1D5004a02bAfAb9de2D6CE5b7B13de --rpc-url http://localhost:8545",
    "make:transaction": "cd ./src && npm install && npm run start"
  }
}
```

#!/bin/bash

# Load environment variables
source .env

# Colors for better readability
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Starting Anvil fork of Ethereum mainnet...${NC}"

MAINNET_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/HZaHTH7_tVMJ1iPuxrvPjooIN-ixbzvf


# Check if the RPC URL is set
if [ -z "$MAINNET_RPC_URL" ]; then
    echo -e "${RED}Error: MAINNET_RPC_URL is not set in .env file${NC}"
    exit 1
fi

# Start Anvil with fork
echo -e "${BLUE}Forking from: $MAINNET_RPC_URL${NC}"

# Start Anvil with more parameters for better debugging and stability
anvil \
    --fork-url $MAINNET_RPC_URL \
    --port 8545 \
    --fork-block-number 22243923 \
    --block-time 1 \
    --chain-id 1 \
    --accounts 10 \
    --balance 10000 \
    --auto-impersonate

echo -e "${GREEN}Anvil is running! The local RPC URL is: http://localhost:8545${NC}"
echo -e "${YELLOW}Press Ctrl+C to stop the node${NC}"
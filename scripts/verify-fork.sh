#!/bin/bash

# Load environment variables
source .env

# Colors for better readability
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Verifying contracts on the forked chain...${NC}"

USDC_ADDRESS=${USDC_ADDRESS:-"0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"}
USDC_WHALE=${USDC_WHALE:-"0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503"}
AAVE_POOL_ADDRESS=${AAVE_POOL_ADDRESS:-"0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2"}

# Check USDC contract
echo -e "${BLUE}Checking USDC contract...${NC}"
USDC_NAME=$(cast call $USDC_ADDRESS "name()(string)" --rpc-url http://localhost:8545)
USDC_SYMBOL=$(cast call $USDC_ADDRESS "symbol()(string)" --rpc-url http://localhost:8545)
USDC_DECIMALS=$(cast call $USDC_ADDRESS "decimals()(uint8)" --rpc-url http://localhost:8545)

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ USDC Contract verified: $USDC_NAME ($USDC_SYMBOL) with $USDC_DECIMALS decimals${NC}"
else
    echo -e "${RED}✗ Failed to verify USDC contract${NC}"
fi

# Check AAVE Pool contract
echo -e "${BLUE}Checking AAVE Pool contract...${NC}"
AAVE_POOL_PROVIDER=$(cast call $AAVE_POOL_ADDRESS "ADDRESSES_PROVIDER()(address)" --rpc-url http://localhost:8545)

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ AAVE Pool verified with provider: $AAVE_POOL_PROVIDER${NC}"
else
    echo -e "${RED}✗ Failed to verify AAVE Pool contract${NC}"
fi

# Check USDC Whale balance
echo -e "${BLUE}Checking USDC Whale balance...${NC}"
USDC_WHALE_BALANCE=$(cast call $USDC_ADDRESS "balanceOf(address)(uint256)" $USDC_WHALE --rpc-url http://localhost:8545)

if [ $? -eq 0 ]; then
    # Convert to readable format (USDC has 6 decimals)
    if command -v bc >/dev/null 2>&1; then
        USDC_WHALE_BALANCE_READABLE=$(echo "scale=2; $USDC_WHALE_BALANCE / 1000000" | bc)
    else
        # Strip everything except digits (remove scientific notation suffixes if any)
        USDC_WHALE_BALANCE_CLEAN=$(echo $USDC_WHALE_BALANCE | grep -oE '[0-9]+')

        # Convert to readable format
        USDC_WHALE_BALANCE_READABLE=$(awk "BEGIN { printf \"%.2f\", $USDC_WHALE_BALANCE_CLEAN / 1000000 }")
    fi
    echo -e "${GREEN}✓ USDC Whale has $USDC_WHALE_BALANCE_READABLE USDC${NC}"
else
    echo -e "${RED}✗ Failed to check USDC Whale balance${NC}"
fi

echo -e "${YELLOW}Fork verification complete!${NC}"
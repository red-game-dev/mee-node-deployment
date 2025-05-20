#!/bin/bash

# Colors for better readability
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Load environment variables
source .env

# Check if address argument is provided
if [ -z "$1" ]; then
    echo -e "${RED}Error: No wallet address provided${NC}"
    echo -e "${BLUE}Usage: ./scripts/direct-whale-transfer.sh <WALLET_ADDRESS> [USDC_AMOUNT]${NC}"
    exit 1
fi

# Set the amount (default to 1000 USDC if not provided)
AMOUNT=${2:-1000}
WALLET_ADDRESS=$1
USDC_ADDRESS=${USDC_ADDRESS:-"0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"}
USDC_WHALE=${USDC_WHALE:-"0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503"}

echo -e "${YELLOW}Funding wallet with USDC using direct method...${NC}"
echo -e "${BLUE}Wallet: $WALLET_ADDRESS${NC}"
echo -e "${BLUE}Amount: $AMOUNT USDC${NC}"
echo -e "${BLUE}USDC Whale: $USDC_WHALE${NC}"

# Check initial balance
INITIAL_BALANCE=$(cast call $USDC_ADDRESS "balanceOf(address)(uint256)" $WALLET_ADDRESS --rpc-url http://localhost:8545 2>/dev/null)
echo -e "${BLUE}Initial balance: $INITIAL_BALANCE USDC (raw)${NC}"

# Check whale's balance
WHALE_BALANCE=$(cast call $USDC_ADDRESS "balanceOf(address)(uint256)" $USDC_WHALE --rpc-url http://localhost:8545 2>/dev/null)
echo -e "${BLUE}Whale's USDC balance: $WHALE_BALANCE USDC (raw)${NC}"

if [ "$WHALE_BALANCE" = "0" ] || [ -z "$WHALE_BALANCE" ]; then
    echo -e "${RED}Whale has no USDC balance.${NC}"
    exit 1
fi

# Calculate the amount in wei (USDC has 6 decimals)
AMOUNT_WEI=$(echo "$AMOUNT * 1000000" | bc 2>/dev/null || echo $(( AMOUNT * 1000000 )))

# The direct approach is to use `setBalance` for ETH
echo -e "${BLUE}Using direct approach to set your account balance...${NC}"

# Let's try to directly manipulate the USDC balance by setting storage
echo -e "${BLUE}Looking for the correct storage slot for USDC balances...${NC}"

# Map of known storage layouts for popular tokens
# For USDC, typically the balances are at slot 0, 1, 2, or 9
USDC_SLOTS=(9 0 1 2 3 4 5 6 7 8)

for slot in "${USDC_SLOTS[@]}"; do
    echo -e "${BLUE}Trying storage slot $slot...${NC}"
    
    # Calculate storage key
    PADDED_ADDRESS=$(echo $WALLET_ADDRESS | sed 's/^0x/000000000000000000000000/')
    PADDED_SLOT=$(printf "%064x" $slot)
    COMPUTED_KEY=$(cast keccak "${PADDED_ADDRESS}${PADDED_SLOT}" 2>/dev/null | tr -d '\n')
    
    if [ -z "$COMPUTED_KEY" ]; then
        echo -e "${RED}Failed to compute key for slot $slot${NC}"
        continue
    fi
    
    # Set storage directly
    echo -e "${BLUE}Setting storage at key $COMPUTED_KEY...${NC}"
    AMOUNT_HEX=$(printf "%064x" $AMOUNT_WEI)
    curl -s -X POST -H "Content-Type: application/json" --data "{\"jsonrpc\":\"2.0\",\"method\":\"anvil_setStorageAt\",\"params\":[\"$USDC_ADDRESS\", \"0x$COMPUTED_KEY\", \"0x$AMOUNT_HEX\"],\"id\":1}" http://localhost:8545 > /dev/null
    
    # Check if it worked
    NEW_BALANCE=$(cast call $USDC_ADDRESS "balanceOf(address)(uint256)" $WALLET_ADDRESS --rpc-url http://localhost:8545 2>/dev/null)
    
    if [ "$NEW_BALANCE" != "0" ] && [ -n "$NEW_BALANCE" ]; then
        echo -e "${GREEN}✓ Balance updated successfully at slot $slot!${NC}"
        echo -e "${GREEN}New balance: $NEW_BALANCE USDC (raw)${NC}"
        exit 0
    fi
done

# If we're here, direct storage manipulation didn't work
echo -e "${RED}✗ Direct storage manipulation failed${NC}"
echo -e "${YELLOW}Trying to use an alternative method: setUsdcBalance...${NC}"

# Create a simple proxy contract to mint USDC
echo -e "${BLUE}Creating a simple USDC balance setter script...${NC}"

# Use the simplest approach: just create a new ERC20 token
# First, get the current nonce
NONCE_RESULT=$(curl -s -X POST -H "Content-Type: application/json" --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getTransactionCount\",\"params\":[\"$WALLET_ADDRESS\", \"latest\"],\"id\":1}" http://localhost:8545)
NONCE=$(echo $NONCE_RESULT | grep -o '"result":"0x[^"]*' | sed 's/"result":"//g')

echo -e "${BLUE}Current nonce: $NONCE${NC}"

# Let's create a USDC balance using a different method
# We'll deploy a simple contract that can mint USDC
TRANSFER_FUNCTION_SELECTOR="a9059cbb"
PADDED_ADDRESS=$(echo $WALLET_ADDRESS | sed 's/^0x/000000000000000000000000/')
PADDED_AMOUNT=$(printf "%064x" $AMOUNT_WEI)
TRANSFER_DATA="${TRANSFER_FUNCTION_SELECTOR}${PADDED_ADDRESS}${PADDED_AMOUNT}"

echo -e "${BLUE}Impersonating USDC whale to transfer USDC...${NC}"
IMPERSONATE_RESULT=$(curl -s -X POST -H "Content-Type: application/json" --data "{\"jsonrpc\":\"2.0\",\"method\":\"anvil_impersonateAccount\",\"params\":[\"$USDC_WHALE\"],\"id\":1}" http://localhost:8545)

# Set the balance of the whale for gas
SET_BALANCE_RESULT=$(curl -s -X POST -H "Content-Type: application/json" --data "{\"jsonrpc\":\"2.0\",\"method\":\"anvil_setBalance\",\"params\":[\"$USDC_WHALE\", \"0x3635C9ADC5DEA00000\"],\"id\":1}" http://localhost:8545)

# Send transaction as the whale
echo -e "${BLUE}Sending transaction as the whale...${NC}"
TX_RESULT=$(curl -s -X POST -H "Content-Type: application/json" --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_sendTransaction\",\"params\":[{\"from\":\"$USDC_WHALE\",\"to\":\"$USDC_ADDRESS\",\"data\":\"0x$TRANSFER_DATA\",\"gas\":\"0x100000\",\"gasPrice\":\"0x3b9aca00\"}],\"id\":1}" http://localhost:8545)
TX_HASH=$(echo $TX_RESULT | grep -o '"result":"0x[^"]*' | sed 's/"result":"//g')

echo -e "${BLUE}Transaction hash: $TX_HASH${NC}"

# Stop impersonating
STOP_IMPERSONATE_RESULT=$(curl -s -X POST -H "Content-Type: application/json" --data "{\"jsonrpc\":\"2.0\",\"method\":\"anvil_stopImpersonatingAccount\",\"params\":[\"$USDC_WHALE\"],\"id\":1}" http://localhost:8545)

# Check the final balance
FINAL_BALANCE=$(cast call $USDC_ADDRESS "balanceOf(address)(uint256)" $WALLET_ADDRESS --rpc-url http://localhost:8545 2>/dev/null)

if [ "$FINAL_BALANCE" != "0" ] && [ -n "$FINAL_BALANCE" ]; then
    echo -e "${GREEN}✓ Transfer successful!${NC}"
    echo -e "${GREEN}Final balance: $FINAL_BALANCE USDC (raw)${NC}"
    exit 0
else
    echo -e "${RED}✗ All methods failed${NC}"
    echo -e "${YELLOW}Let's try a very simple method: create a mock USDC token${NC}"
    
    # As a last resort, let's create a mock USDC token with the same interface
    # This won't work with the real AAVE protocol, but for demo purposes it might be sufficient
    echo -e "${BLUE}Creating a mock USDC token...${NC}"
    echo -e "${RED}WARNING: This is for demonstration purposes only and won't work with the real AAVE protocol${NC}"
    echo -e "${YELLOW}Consider using a different block number or approach for a real solution.${NC}"
    exit 1
fi

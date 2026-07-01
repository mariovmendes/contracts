#!/usr/bin/env bash
# Main deployment orchestrator for Compose Contracts

set -euo pipefail

NETWORK_NAME=$1

echo "========================================="
echo "Deploying Compose Contracts to $NETWORK_NAME"
echo "========================================="
echo ""

# Parse network configuration
source scripts/parse-network.sh "$NETWORK_NAME"

echo "Network:     $NETWORK_NAME"
echo "Chain ID:    $NETWORK_CHAIN_ID"
echo "RPC URL:     $NETWORK_RPC_URL"
echo ""

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed. Please install jq."
    exit 1
fi

# Create temporary file for deployment output
TMP_OUTPUT=$(mktemp)

# =============================================================================
# Step 0/3: (mock mode only) Deploy MockVerifier and use it in place of
# NETWORK_VERIFIER_ADDRESS. NEVER set MOCK_MODE=true against a network that
# carries any real value — MockVerifier accepts any proof unconditionally.
# =============================================================================
if [ "${MOCK_MODE:-false}" = "true" ]; then
    echo "========================================="
    echo "Step 0/3: MOCK_MODE — deploying MockVerifier"
    echo "========================================="
    echo ""

    forge script script/DeployMockVerifier.s.sol:DeployMockVerifier \
        --rpc-url "$NETWORK_RPC_URL" \
        --private-key "$DEPLOYER_PRIVATE_KEY" \
        --broadcast \
        2>&1 | tee "$TMP_OUTPUT"

    MOCK_BROADCAST_DIR="broadcast/DeployMockVerifier.s.sol/$NETWORK_CHAIN_ID"
    MOCK_BROADCAST_FILE=$(ls -t "$MOCK_BROADCAST_DIR"/run-*.json 2>/dev/null | head -1)

    if [ -z "$MOCK_BROADCAST_FILE" ]; then
        echo "Error: Could not find broadcast output for MockVerifier"
        exit 1
    fi

    MOCK_VERIFIER_ADDRESS=$(jq -r '.transactions[] | select(.contractName == "MockVerifier") | .contractAddress' "$MOCK_BROADCAST_FILE" | head -1)

    if [ -z "$MOCK_VERIFIER_ADDRESS" ] || [ "$MOCK_VERIFIER_ADDRESS" = "null" ]; then
        echo "Error: Could not extract MockVerifier address"
        exit 1
    fi

    echo ""
    echo "✓ MockVerifier deployed at: $MOCK_VERIFIER_ADDRESS"
    echo "  Overriding NETWORK_VERIFIER_ADDRESS ($NETWORK_VERIFIER_ADDRESS -> $MOCK_VERIFIER_ADDRESS)"
    echo ""

    NETWORK_VERIFIER_ADDRESS="$MOCK_VERIFIER_ADDRESS"
fi

# =============================================================================
# Step 1: Deploy ComposeL2OutputOracle (Proxy + Implementation)
# =============================================================================
echo "========================================="
echo "Step 1/3: Deploying ComposeL2OutputOracle"
echo "========================================="
echo ""

# Deploy with verification
if [ -n "${ETHERSCAN_API_KEY:-}" ]; then
    forge script script/DeployComposeL2OutputOracle.s.sol:DeployComposeL2OutputOracle \
        --rpc-url "$NETWORK_RPC_URL" \
        --sig "run(address,address,address,bytes32,uint256)" \
        "$NETWORK_VERIFIER_ADDRESS" \
        "$NETWORK_OWNER_ADDRESS" \
        "$NETWORK_PROPOSER_ADDRESS" \
        "$NETWORK_AGGREGATION_VKEY" \
        "$NETWORK_STARTING_SUPERBLOCK_NUMBER" \
        --private-key "$DEPLOYER_PRIVATE_KEY" \
        --broadcast \
        --verify \
        --etherscan-api-key "$ETHERSCAN_API_KEY" \
        2>&1 | tee "$TMP_OUTPUT"
else
    echo "Warning: Skipping verification (no ETHERSCAN_API_KEY)"
    forge script script/DeployComposeL2OutputOracle.s.sol:DeployComposeL2OutputOracle \
        --rpc-url "$NETWORK_RPC_URL" \
        --sig "run(address,address,address,bytes32,uint256)" \
        "$NETWORK_VERIFIER_ADDRESS" \
        "$NETWORK_OWNER_ADDRESS" \
        "$NETWORK_PROPOSER_ADDRESS" \
        "$NETWORK_AGGREGATION_VKEY" \
        "$NETWORK_STARTING_SUPERBLOCK_NUMBER" \
        --private-key "$DEPLOYER_PRIVATE_KEY" \
        --broadcast \
        2>&1 | tee "$TMP_OUTPUT"
fi

# Parse ComposeL2OutputOracle addresses from broadcast output
BROADCAST_DIR="broadcast/DeployComposeL2OutputOracle.s.sol/$NETWORK_CHAIN_ID"
BROADCAST_FILE=$(ls -t "$BROADCAST_DIR"/run-*.json 2>/dev/null | head -1)

if [ -z "$BROADCAST_FILE" ]; then
    echo "Error: Could not find broadcast output for ComposeL2OutputOracle"
    exit 1
fi

# Extract addresses from broadcast JSON
ORACLE_IMPL=$(jq -r '.transactions[] | select(.contractName == "ComposeL2OutputOracle") | .contractAddress' "$BROADCAST_FILE" | head -1)
ORACLE_PROXY=$(jq -r '.transactions[] | select(.contractName == "ERC1967Proxy") | .contractAddress' "$BROADCAST_FILE" | head -1)

if [ -z "$ORACLE_PROXY" ] || [ "$ORACLE_PROXY" = "null" ]; then
    echo "Error: Could not extract ComposeL2OutputOracle proxy address"
    exit 1
fi

echo ""
echo "✓ ComposeL2OutputOracle deployed:"
echo "  Implementation: $ORACLE_IMPL"
echo "  Proxy:          $ORACLE_PROXY"
echo ""

# =============================================================================
# Step 2: Deploy ComposeDisputeGame (Implementation)
# =============================================================================
echo "========================================="
echo "Step 2/3: Deploying ComposeDisputeGame"
echo "========================================="
echo ""

# Deploy with verification
if [ -n "${ETHERSCAN_API_KEY:-}" ]; then
    forge script script/DeployComposeDisputeGame.s.sol:DeployComposeDisputeGame \
        --rpc-url "$NETWORK_RPC_URL" \
        --sig "run(address)" "$ORACLE_PROXY" \
        --private-key "$DEPLOYER_PRIVATE_KEY" \
        --broadcast \
        --verify \
        --etherscan-api-key "$ETHERSCAN_API_KEY" \
        2>&1 | tee "$TMP_OUTPUT"
else
    echo "Warning: Skipping verification (no ETHERSCAN_API_KEY)"
    forge script script/DeployComposeDisputeGame.s.sol:DeployComposeDisputeGame \
        --rpc-url "$NETWORK_RPC_URL" \
        --sig "run(address)" "$ORACLE_PROXY" \
        --private-key "$DEPLOYER_PRIVATE_KEY" \
        --broadcast \
        2>&1 | tee "$TMP_OUTPUT"
fi

# Parse ComposeDisputeGame address from broadcast output
BROADCAST_DIR="broadcast/DeployComposeDisputeGame.s.sol/$NETWORK_CHAIN_ID"
BROADCAST_FILE=$(ls -t "$BROADCAST_DIR"/run-*.json 2>/dev/null | head -1)

if [ -z "$BROADCAST_FILE" ]; then
    echo "Error: Could not find broadcast output for ComposeDisputeGame"
    exit 1
fi

GAME_IMPL=$(jq -r '.transactions[] | select(.contractName == "ComposeDisputeGame") | .contractAddress' "$BROADCAST_FILE" | head -1)

if [ -z "$GAME_IMPL" ] || [ "$GAME_IMPL" = "null" ]; then
    echo "Error: Could not extract ComposeDisputeGame address"
    exit 1
fi

echo ""
echo "✓ ComposeDisputeGame deployed:"
echo "  Implementation: $GAME_IMPL"
echo ""

# =============================================================================
# Step 3: Deploy DisputeGameFactory (ProxyAdmin + Implementation + Proxy)
# =============================================================================
echo "========================================="
echo "Step 3/3: Deploying DisputeGameFactory"
echo "========================================="
echo ""

# Deploy with verification
if [ -n "${ETHERSCAN_API_KEY:-}" ]; then
    forge script script/DeployDisputeGameFactory.s.sol:DeployDisputeGameFactory \
        --rpc-url "$NETWORK_RPC_URL" \
        --sig "run(address)" "$NETWORK_ADMIN_ADDRESS" \
        --private-key "$DEPLOYER_PRIVATE_KEY" \
        --broadcast \
        --verify \
        --etherscan-api-key "$ETHERSCAN_API_KEY" \
        2>&1 | tee "$TMP_OUTPUT"
else
    echo "Warning: Skipping verification (no ETHERSCAN_API_KEY)"
    forge script script/DeployDisputeGameFactory.s.sol:DeployDisputeGameFactory \
        --rpc-url "$NETWORK_RPC_URL" \
        --sig "run(address)" "$NETWORK_ADMIN_ADDRESS" \
        --private-key "$DEPLOYER_PRIVATE_KEY" \
        --broadcast \
        2>&1 | tee "$TMP_OUTPUT"
fi

# Parse DisputeGameFactory addresses from broadcast output
BROADCAST_DIR="broadcast/DeployDisputeGameFactory.s.sol/$NETWORK_CHAIN_ID"
BROADCAST_FILE=$(ls -t "$BROADCAST_DIR"/run-*.json 2>/dev/null | head -1)

if [ -z "$BROADCAST_FILE" ]; then
    echo "Error: Could not find broadcast output for DisputeGameFactory"
    exit 1
fi

# Extract addresses (order: ProxyAdmin, DisputeGameFactory impl, Proxy)
PROXY_ADMIN=$(jq -r '.transactions[] | select(.contractName == "ProxyAdmin") | .contractAddress' "$BROADCAST_FILE" | head -1)
FACTORY_IMPL=$(jq -r '.transactions[] | select(.contractName == "DisputeGameFactory") | .contractAddress' "$BROADCAST_FILE" | head -1)
FACTORY_PROXY=$(jq -r '.transactions[] | select(.contractName == "Proxy") | .contractAddress' "$BROADCAST_FILE" | head -1)

if [ -z "$FACTORY_PROXY" ] || [ "$FACTORY_PROXY" = "null" ]; then
    echo "Error: Could not extract DisputeGameFactory proxy address"
    exit 1
fi

echo ""
echo "✓ DisputeGameFactory deployed:"
echo "  Implementation: $FACTORY_IMPL"
echo "  Proxy:          $FACTORY_PROXY"
echo "  ProxyAdmin:     $PROXY_ADMIN"
echo ""

# =============================================================================
# Save deployment addresses
# =============================================================================
./scripts/save-deployment.sh \
    "$NETWORK_NAME" \
    "$NETWORK_CHAIN_ID" \
    "$ORACLE_PROXY" \
    "$ORACLE_IMPL" \
    "$GAME_IMPL" \
    "$FACTORY_PROXY" \
    "$FACTORY_IMPL" \
    "$PROXY_ADMIN"

echo ""
echo "========================================="
echo "✓ Deployment to $NETWORK_NAME complete!"
echo "========================================="

# Cleanup
rm -f "$TMP_OUTPUT"

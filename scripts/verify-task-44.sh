#!/usr/bin/env bash
set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting verification for Task 44: Multi-Node Integration Testing${NC}"

# Check if relevant files exist
echo "Checking for required files..."
REQUIRED_FILES=(
    "lib/cluster-tester.nix"
    "tests/multi-node.nix"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo -e "${RED}Error: Required file $file not found!${NC}"
        exit 1
    fi
done
echo "All required files present."

# Run the test
echo "Running NixOS test for Multi-Node Integration..."
if nix build .#checks.x86_64-linux.task-44-multi-node-integration --no-link; then
    echo -e "${GREEN}Task 44 verification SUCCESS: Multi-node orchestration functioning.${NC}"
else
    echo -e "${RED}Task 44 verification FAILED: Test execution failed.${NC}"
    exit 1
fi

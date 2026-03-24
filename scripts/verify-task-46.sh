#!/usr/bin/env bash
set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting verification for Task 46: Hardware Testing Framework${NC}"

# Check if relevant files exist
echo "Checking for required files..."
REQUIRED_FILES=(
    "lib/hardware-validator.nix"
    "modules/hardware-testing.nix"
    "tests/hardware-test.nix"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo -e "${RED}Error: Required file $file not found!${NC}"
        exit 1
    fi
done
echo "All required files present."

# Run the test
echo "Running NixOS Hardware Test Suite..."
if nix build .#checks.x86_64-linux.task-46-hardware-testing --no-link; then
    echo -e "${GREEN}Task 46 verification SUCCESS: Hardware validation logic confirmed.${NC}"
else
    echo -e "${RED}Task 46 verification FAILED: Test execution failed.${NC}"
    exit 1
fi

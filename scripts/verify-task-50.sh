#!/usr/bin/env bash
set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "Verifying Task 50: Container Network Policies..."

# 1. Check if files exist
echo -n "Checking for module files... "
if [ -f "modules/container-network-policies.nix" ] && [ -f "lib/network-policy-tester.nix" ] && [ -f "tests/container-network-policy-test.nix" ]; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAILED${NC}"
    echo "Missing required files"
    exit 1
fi

# 2. Run the test
echo "Running container network policy test..."
if nix build .#checks.x86_64-linux.task-50-container-policies --print-build-logs; then
    echo -e "${GREEN}Test Passed!${NC}"
else
    echo -e "${RED}Test Failed!${NC}"
    exit 1
fi

echo -e "${GREEN}Verification Complete!${NC}"

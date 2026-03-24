#!/usr/bin/env bash
set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "Verifying Task 49: Service Mesh Compatibility..."

# 1. Check if files exist
echo -n "Checking for module files... "
if [ -f "modules/service-mesh-compatibility.nix" ] && [ -f "lib/mesh-tester.nix" ] && [ -f "tests/service-mesh-compatibility-test.nix" ]; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAILED${NC}"
    echo "Missing required files"
    exit 1
fi

# 2. Run the test
echo "Running service mesh compatibility test..."
if nix build .#checks.x86_64-linux.task-49-service-mesh --print-build-logs; then
    echo -e "${GREEN}Test Passed!${NC}"
else
    echo -e "${RED}Test Failed!${NC}"
    exit 1
fi

echo -e "${GREEN}Verification Complete!${NC}"

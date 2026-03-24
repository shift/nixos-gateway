#!/usr/bin/env bash
set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting verification for Task 43: Security Penetration Testing${NC}"

# Check if relevant files exist
echo "Checking for required files..."
REQUIRED_FILES=(
    "lib/pentest-engine.nix"
    "modules/security-pentest.nix"
    "tests/security-pentest.nix"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo -e "${RED}Error: Required file $file not found!${NC}"
        exit 1
    fi
done
echo "All required files present."

# Run the test
echo "Running NixOS test for Security Penetration..."
if nix build .#checks.x86_64-linux.task-43-security-pentest --no-link; then
    echo -e "${GREEN}Task 43 verification SUCCESS: Pentest logic and reporting are functioning correctly.${NC}"
else
    echo -e "${RED}Task 43 verification FAILED: Test execution failed.${NC}"
    exit 1
fi

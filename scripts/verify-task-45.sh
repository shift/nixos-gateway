#!/usr/bin/env bash
set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting verification for Task 45: CI/CD Integration${NC}"

# Check if relevant files exist
echo "Checking for required files..."
REQUIRED_FILES=(
    "lib/pipeline-manager.nix"
    "ci/ci-pipeline.nix"
    "tests/ci-cd.nix"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo -e "${RED}Error: Required file $file not found!${NC}"
        exit 1
    fi
done
echo "All required files present."

# Run the test
echo "Running CI/CD Pipeline Generation Test..."
if nix build .#checks.x86_64-linux.task-45-ci-cd --no-link; then
    echo -e "${GREEN}Task 45 verification SUCCESS: CI/CD pipeline logic verified.${NC}"
else
    echo -e "${RED}Task 45 verification FAILED: Test execution failed.${NC}"
    exit 1
fi

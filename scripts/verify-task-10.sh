#!/usr/bin/env bash
set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "🔐 Verifying Task 10: Policy-Based Routing..."

# Check if we are in a nix shell
if [ -z "$IN_NIX_SHELL" ]; then
    echo -e "${YELLOW}⚠️  Warning: Not in a nix shell. Some commands might fail.${NC}"
    echo -e "${YELLOW}   Suggestion: Run 'nix develop' first.${NC}"
fi

# 1. Check if policy routing library exists
echo -e "🔍 Checking policy routing library implementation..."
if [ -f "lib/policy-routing.nix" ]; then
    echo -e "  ${GREEN}✓${NC} Policy routing library file exists"
    
    # Simple syntax check for library
    if nix-instantiate --parse lib/policy-routing.nix >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} Policy routing library syntax validation"
    else
        echo -e "  ${RED}✗${NC} Policy routing library syntax validation"
        echo -e "    ${RED}Details: Nix syntax error in lib/policy-routing.nix${NC}"
        exit 1
    fi
else
    echo -e "  ${RED}✗${NC} Policy routing library file missing"
    exit 1
fi

# 2. Check if policy routing module exists
echo -e "🔍 Checking policy routing module..."
if [ -f "modules/policy-routing.nix" ]; then
    echo -e "  ${GREEN}✓${NC} Policy routing module file exists"
    
    # Simple syntax check for module
    if nix-instantiate --parse modules/policy-routing.nix >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} Policy routing module syntax validation"
    else
        echo -e "  ${RED}✗${NC} Policy routing module syntax validation"
        echo -e "    ${RED}Details: Nix syntax error in modules/policy-routing.nix${NC}"
        exit 1
    fi
else
    echo -e "  ${RED}✗${NC} Policy routing module file missing"
    exit 1
fi

# 3. Check if policy routing test exists
echo -e "🔍 Checking policy routing test..."
if [ -f "tests/policy-routing-test.nix" ]; then
    echo -e "  ${GREEN}✓${NC} Policy routing test file exists"
    
    # Simple syntax check for test
    if nix-instantiate --parse tests/policy-routing-test.nix >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} Policy routing test syntax validation"
    else
        echo -e "  ${RED}✗${NC} Policy routing test syntax validation"
        echo -e "    ${RED}Details: Nix syntax error in tests/policy-routing-test.nix${NC}"
        exit 1
    fi
else
    echo -e "  ${RED}✗${NC} Policy routing test file missing"
    exit 1
fi

# 4. Run the verification test
echo -e "\n🧪 Running verification test (VM-based)..."
echo -e "${YELLOW}Note: This may take a few minutes as it builds a VM...${NC}"

if nix build .#checks.x86_64-linux.task-10-policy-routing --show-trace -L; then
    echo -e "  ${GREEN}✓${NC} Policy routing verification test passed"
else
    echo -e "  ${RED}✗${NC} Policy routing verification test failed"
    echo -e "    ${RED}Check the build log for details${NC}"
    exit 1
fi

echo -e "\n📊 Summary:"
echo -e "  ${GREEN}Passed: All checks${NC}"
echo -e "  ${RED}Failed: 0${NC}"

echo -e "\n${GREEN}🎉 All tests passed! Task 10: Policy-Based Routing is complete.${NC}"

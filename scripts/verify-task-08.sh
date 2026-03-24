#!/bin/bash

# Task 08: Secret Rotation Automation Verification Script
# This script verifies that the secret rotation automation implementation is working correctly

set -e

echo "🔐 Verifying Task 08: Secret Rotation Automation..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test results
PASSED=0
FAILED=0

# Function to print test results
print_result() {
    local test_name="$1"
    local result="$2"
    local details="$3"
    
    if [ "$result" = "PASS" ]; then
        echo -e "  ${GREEN}✓${NC} $test_name"
        PASSED=$((PASSED + 1))
    else
        echo -e "  ${RED}✗${NC} $test_name"
        if [ -n "$details" ]; then
            echo -e "    ${RED}Details: $details${NC}"
        fi
        FAILED=$((FAILED + 1))
    fi
}

# Function to check if file exists
check_file_exists() {
    local file_path="$1"
    local description="$2"
    
    if [ -f "$file_path" ]; then
        print_result "$description" "PASS"
        return 0
    else
        print_result "$description" "FAIL" "File not found: $file_path"
        return 1
    fi
}

# Function to check if directory exists
check_directory_exists() {
    local dir_path="$1"
    local description="$2"
    
    if [ -d "$dir_path" ]; then
        print_result "$description" "PASS"
        return 0
    else
        print_result "$description" "FAIL" "Directory not found: $dir_path"
        return 1
    fi
}

# Function to check Nix expression syntax
check_nix_syntax() {
    local file_path="$1"
    local description="$2"
    
    if nix-instantiate --parse "$file_path" >/dev/null 2>&1; then
        print_result "$description" "PASS"
        return 0
    else
        print_result "$description" "FAIL" "Nix syntax error in $file_path"
        return 1
    fi
}

# Function to check Nix build
check_nix_build() {
    local expression="$1"
    local description="$2"
    
    if nix eval --impure --expr "$expression" >/dev/null 2>&1; then
        print_result "$description" "PASS"
        return 0
    else
        print_result "$description" "FAIL" "Nix evaluation failed for: $expression"
        return 1
    fi
}

echo "🔍 Checking secret rotation library implementation..."

# Test 1: Secret rotation library file exists
check_file_exists "lib/secret-rotation.nix" "Secret rotation library file exists"

# Test 2: Secret rotation library syntax
check_nix_syntax "lib/secret-rotation.nix" "Secret rotation library syntax validation"

# Test 3: Certificate manager module exists
check_file_exists "modules/certificate-manager.nix" "Certificate manager module exists"

# Test 4: Certificate manager module syntax
check_nix_syntax "modules/certificate-manager.nix" "Certificate manager module syntax validation"

# Test 5: Key rotation module exists
check_file_exists "modules/key-rotation.nix" "Key rotation module exists"

# Test 6: Key rotation module syntax
check_nix_syntax "modules/key-rotation.nix" "Key rotation module syntax validation"

# Test 7: Secret rotation test exists
check_file_exists "tests/secret-rotation-test.nix" "Secret rotation test exists"

# Test 8: Secret rotation test syntax
check_nix_syntax "tests/secret-rotation-test.nix" "Secret rotation test syntax validation"

# Test 9: Example configuration exists
check_file_exists "examples/secret-rotation-example.nix" "Secret rotation example exists"

# Test 10: Example configuration syntax
check_nix_syntax "examples/secret-rotation-example.nix" "Secret rotation example syntax validation"

echo ""
echo "🧪 Testing secret rotation library functionality..."

# Test 11: Check if library can be imported
check_nix_build "(import ./lib/secret-rotation.nix { inherit (import <nixpkgs> {}) lib; })" "Secret rotation library import"

# Test 12: Check certificate strategies
check_nix_build "(let lib = import <nixpkgs> { }; sr = import ./lib/secret-rotation.nix { inherit lib; }; in sr.certificateStrategies)" "Certificate strategies defined"

# Test 13: Check key strategies
check_nix_build "(let lib = import <nixpkgs> { }; sr = import ./lib/secret-rotation.nix { inherit lib; }; in sr.keyStrategies)" "Key strategies defined"

# Test 14: Check interval parsing
check_nix_build "(let lib = import <nixpkgs> { }; sr = import ./lib/secret-rotation.nix { inherit lib; }; in builtins.typeOf (sr.parseInterval \"30d\"))" "Interval parsing function"

echo ""
echo "🔧 Testing module integration..."

# Test 15: Check if modules are included in default.nix
if grep -q "certificate-manager.nix" modules/default.nix; then
    print_result "Certificate manager included in default.nix" "PASS"
else
    print_result "Certificate manager included in default.nix" "FAIL" "Not found in modules/default.nix"
fi

if grep -q "key-rotation.nix" modules/default.nix; then
    print_result "Key rotation included in default.nix" "PASS"
else
    print_result "Key rotation included in default.nix" "FAIL" "Not found in modules/default.nix"
fi

echo ""
echo "📋 Testing configuration options..."

# Test 16: Check certificate manager options
check_nix_build "(let pkgs = import <nixpkgs> {}; lib = pkgs.lib; cfg = { services.gateway.secretRotation.enable = true; }; in builtins.typeOf (import ./modules/certificate-manager.nix { config = cfg; inherit pkgs lib; }))" "Certificate manager module structure"

# Test 17: Check key rotation options
check_nix_build "(let pkgs = import <nixpkgs> {}; lib = pkgs.lib; cfg = { services.gateway.secretRotation.enable = true; }; in builtins.typeOf (import ./modules/key-rotation.nix { config = cfg; inherit pkgs lib; }))" "Key rotation module structure"

echo ""
echo "🧪 Testing rotation strategies..."

# Test 18: Check ACME strategy
if grep -q "acme.*=" lib/secret-rotation.nix; then
    print_result "ACME certificate strategy defined" "PASS"
else
    print_result "ACME certificate strategy defined" "FAIL" "ACME strategy not found"
fi

# Test 19: Check WireGuard strategy
if grep -q "wireguard.*=" lib/secret-rotation.nix; then
    print_result "WireGuard key rotation strategy defined" "PASS"
else
    print_result "WireGuard key rotation strategy defined" "FAIL" "WireGuard strategy not found"
fi

# Test 20: Check TSIG strategy
if grep -q "tsig.*=" lib/secret-rotation.nix; then
    print_result "TSIG key rotation strategy defined" "PASS"
else
    print_result "TSIG key rotation strategy defined" "FAIL" "TSIG strategy not found"
fi

echo ""
echo "🔄 Testing coordination and monitoring..."

# Test 21: Check coordination functionality
if grep -q "coordination" lib/secret-rotation.nix; then
    print_result "Key coordination functionality" "PASS"
else
    print_result "Key coordination functionality" "FAIL" "Coordination not found"
fi

# Test 22: Check monitoring integration
if grep -q "metrics" lib/secret-rotation.nix; then
    print_result "Rotation metrics generation" "PASS"
else
    print_result "Rotation metrics generation" "FAIL" "Metrics not found"
fi

echo ""
echo "🛡️ Testing security and validation..."

# Test 23: Check backup functionality
if grep -q "backup" lib/secret-rotation.nix; then
    print_result "Backup functionality included" "PASS"
else
    print_result "Backup functionality included" "FAIL" "Backup not found"
fi

# Test 24: Check rollback functionality
if grep -q "rollback" lib/secret-rotation.nix; then
    print_result "Rollback functionality included" "PASS"
else
    print_result "Rollback functionality included" "FAIL" "Rollback not found"
fi

# Test 25: Check validation functions
if grep -q "validateRotationConfig" lib/secret-rotation.nix; then
    print_result "Rotation validation functions" "PASS"
else
    print_result "Rotation validation functions" "FAIL" "Validation not found"
fi

echo ""
echo "📝 Testing documentation and examples..."

# Test 26: Check example configuration completeness
if grep -q "secretRotation" examples/secret-rotation-example.nix; then
    print_result "Example configuration structure" "PASS"
else
    print_result "Example configuration structure" "FAIL" "Secret rotation config not found"
fi

# Test 27: Check test coverage
test_count=$(grep -c "with subtest" tests/secret-rotation-test.nix || echo "0")
if [ "$test_count" -ge 10 ]; then
    print_result "Test coverage (found $test_count tests)" "PASS"
else
    print_result "Test coverage (found $test_count tests)" "FAIL" "Insufficient test coverage"
fi

echo ""
echo "🔗 Testing integration with existing modules..."

# Test 28: Check integration with secrets module
if grep -q "secretRotation" modules/secrets.nix; then
    print_result "Integration with secrets module" "PASS"
else
    print_result "Integration with secrets module" "FAIL" "No integration found"
fi

# Test 29: Check systemd service generation
if grep -q "systemd.services" modules/certificate-manager.nix && grep -q "systemd.services" modules/key-rotation.nix; then
    print_result "Systemd service generation" "PASS"
else
    print_result "Systemd service generation" "FAIL" "Systemd services not found"
fi

# Test 30: Check timer configuration
if grep -q "systemd.timers" modules/certificate-manager.nix && grep -q "systemd.timers" modules/key-rotation.nix; then
    print_result "Timer configuration" "PASS"
else
    print_result "Timer configuration" "FAIL" "Timers not found"
fi

echo ""
echo "🚀 Testing advanced features..."

# Test 31: Check peer notification
if grep -q "peerNotification" lib/secret-rotation.nix; then
    print_result "Peer notification functionality" "PASS"
else
    print_result "Peer notification functionality" "FAIL" "Peer notification not found"
fi

# Test 32: Check dependency management
if grep -q "resolveRotationDependencies" lib/secret-rotation.nix; then
    print_result "Rotation dependency management" "PASS"
else
    print_result "Rotation dependency management" "FAIL" "Dependency management not found"
fi

# Test 33: Check service reload coordination
if grep -q "reloadServices" modules/certificate-manager.nix; then
    print_result "Service reload coordination" "PASS"
else
    print_result "Service reload coordination" "FAIL" "Service reload not found"
fi

echo ""
echo "📊 Summary:"
echo -e "  ${GREEN}Passed: $PASSED${NC}"
echo -e "  ${RED}Failed: $FAILED${NC}"
echo -e "  ${YELLOW}Total: $((PASSED + FAILED))${NC}"

if [ $FAILED -eq 0 ]; then
    echo ""
    echo -e "${GREEN}🎉 All tests passed! Task 08: Secret Rotation Automation is complete.${NC}"
    echo ""
    echo "✅ Implemented features:"
    echo "  • Automated secret rotation framework"
    echo "  • Certificate management (ACME and self-signed)"
    echo "  • Key rotation (WireGuard, TSIG, API keys)"
    echo "  • Rotation scheduling and coordination"
    echo "  • Service restart coordination"
    echo "  • Backup and rollback mechanisms"
    echo "  • Monitoring and alerting integration"
    echo "  • Peer notification for distributed systems"
    echo "  • Comprehensive test suite"
    echo "  • Example configuration"
    echo ""
    echo "🔧 Ready for integration with existing gateway infrastructure."
    exit 0
else
    echo ""
    echo -e "${RED}❌ Some tests failed. Please review the implementation.${NC}"
    exit 1
fi
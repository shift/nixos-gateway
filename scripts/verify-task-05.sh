#!/usr/bin/env bash

# Verification script for Task 05: Configuration Templates
# This script tests the complete template system implementation

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++))
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Test functions
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    ((TESTS_TOTAL++))
    log_info "Running test: $test_name"
    
    if eval "$test_command" >/dev/null 2>&1; then
        log_success "$test_name"
        return 0
    else
        log_error "$test_name"
        return 1
    fi
}

# Check if we're in a Nix dev shell
check_nix_shell() {
    if [[ -z "${IN_NIX_SHELL:-}" ]]; then
        log_warning "Not in Nix dev shell, running commands with nix develop -c"
        NIX_DEVELOP_PREFIX="nix develop -c --"
    else
        NIX_DEVELOP_PREFIX=""
    fi
}

# Test 1: Template engine file exists
test_template_engine_exists() {
    [[ -f "lib/template-engine.nix" ]]
}

# Test 2: Templates directory exists and contains templates
test_templates_directory() {
    [[ -d "templates" ]] && [[ $(find templates -name "*.nix" | wc -l) -ge 7 ]]
}

# Test 3: Template engine syntax validation
test_template_engine_syntax() {
    $NIX_DEVELOP_PREFIX nix-instantiate --eval --expr "
        let
          lib = import <nixpkgs/lib>;
          templateEngine = import ./lib/template-engine.nix { inherit lib; };
        in
        templateEngine
    " >/dev/null
}

# Test 4: Template loading functionality
test_template_loading() {
    $NIX_DEVELOP_PREFIX nix-instantiate --eval --expr "
        let
          lib = import <nixpkgs/lib>;
          templateEngine = import ./lib/template-engine.nix { inherit lib; };
          templates = templateEngine.loadTemplates ./templates;
        in
        builtins.length (lib.attrNames templates) >= 7
    " >/dev/null
}

# Test 5: Template validation
test_template_validation() {
    $NIX_DEVELOP_PREFIX nix-instantiate --eval --expr "
        let
          lib = import <nixpkgs/lib>;
          templateEngine = import ./lib/template-engine.nix { inherit lib; };
          templates = templateEngine.loadTemplates ./templates;
          sohoTemplate = templates.soho-gateway;
        in
        templateEngine.validateTemplate sohoTemplate
    " >/dev/null
}

# Test 6: Template instantiation
test_template_instantiation() {
    $NIX_DEVELOP_PREFIX nix-instantiate --eval --expr "
        let
          lib = import <nixpkgs/lib>;
          templateEngine = import ./lib/template-engine.nix { inherit lib; };
          templates = templateEngine.loadTemplates ./templates;
          config = templateEngine.instantiateTemplateByName templates 'soho-gateway' {
            lanInterface = 'eth0';
            wanInterface = 'eth1';
          };
        in
        config ? services.gateway && config.services.gateway.enable
    " >/dev/null
}

# Test 7: Template inheritance
test_template_inheritance() {
    $NIX_DEVELOP_PREFIX nix-instantiate --eval --expr "
        let
          lib = import <nixpkgs/lib>;
          templateEngine = import ./lib/template-engine.nix { inherit lib; };
          templates = templateEngine.loadTemplates ./templates;
          resolved = templateEngine.resolveTemplateInheritance templates 'simple-gateway' [];
        in
        resolved.inherits == 'base-gateway'
    " >/dev/null
}

# Test 8: Template composition
test_template_composition() {
    $NIX_DEVELOP_PREFIX nix-instantiate --eval --expr "
        let
          lib = import <nixpkgs/lib>;
          templateEngine = import ./lib/template-engine.nix { inherit lib; };
          templates = templateEngine.loadTemplates ./templates;
          config = templateEngine.instantiateComposedTemplate templates [
            'base-gateway'
            'soho-gateway'
          ] {
            lanInterface = 'eth0';
            wanInterface = 'eth1';
          };
        in
        config ? services.gateway
    " >/dev/null
}

# Test 9: Template documentation generation
test_template_documentation() {
    $NIX_DEVELOP_PREFIX nix-instantiate --eval --expr "
        let
          lib = import <nixpkgs/lib>;
          templateEngine = import ./lib/template-engine.nix { inherit lib; };
          templates = templateEngine.loadTemplates ./templates;
          docs = templateEngine.generateTemplateDocs templates.soho-gateway;
        in
        builtins.isString docs && builtins.stringLength docs > 0
    " >/dev/null
}

# Test 10: Template listing functionality
test_template_listing() {
    $NIX_DEVELOP_PREFIX nix-instantiate --eval --expr "
        let
          lib = import <nixpkgs/lib>;
          templateEngine = import ./lib/template-engine.nix { inherit lib; };
          templates = templateEngine.loadTemplates ./templates;
          templateList = templateEngine.listTemplates templates;
        in
        builtins.length (lib.attrNames templateList) >= 7
    " >/dev/null
}

# Test 11: Parameter validation
test_parameter_validation() {
    # Test that missing required parameters are caught
    ! $NIX_DEVELOP_PREFIX nix-instantiate --eval --expr "
        let
          lib = import <nixpkgs/lib>;
          templateEngine = import ./lib/template-engine.nix { inherit lib; };
          templates = templateEngine.loadTemplates ./templates;
        in
        templateEngine.instantiateTemplateByName templates 'soho-gateway' {}
    " >/dev/null 2>&1
}

# Test 12: Template examples exist and are valid
test_template_examples() {
    [[ -f "examples/templates/template-examples.nix" ]] && \
    $NIX_DEVELOP_PREFIX nix-instantiate --eval --expr "
        let
          lib = import <nixpkgs/lib>;
          examples = import ./examples/templates/template-examples.nix { inherit lib; };
        in
        builtins.length (lib.attrNames examples) >= 7
    " >/dev/null
}

# Test 13: Test suite exists and is valid
test_test_suite() {
    [[ -f "tests/template-test.nix" ]] && \
    $NIX_DEVELOP_PREFIX nix-instantiate --eval --expr "
        let
          lib = import <nixpkgs/lib>;
          testSuite = import ./tests/template-test.nix { inherit lib; pkgs = import <nixpkgs> {}; };
        in
        builtins.length (lib.attrNames testSuite) >= 10
    " >/dev/null
}

# Test 14: Integration with existing modules
test_module_integration() {
    $NIX_DEVELOP_PREFIX nix-instantiate --eval --expr "
        let
          lib = import <nixpkgs/lib>;
          templateEngine = import ./lib/template-engine.nix { inherit lib; };
          templates = templateEngine.loadTemplates ./templates;
          config = templateEngine.instantiateTemplateByName templates 'soho-gateway' {
            lanInterface = 'eth0';
            wanInterface = 'eth1';
          };
        in
        config ? networking.firewall && config ? boot.kernel.sysctl
    " >/dev/null
}

# Test 15: Template dependency analysis
test_dependency_analysis() {
    $NIX_DEVELOP_PREFIX nix-instantiate --eval --expr "
        let
          lib = import <nixpkgs/lib>;
          templateEngine = import ./lib/template-engine.nix { inherit lib; };
          templates = templateEngine.loadTemplates ./templates;
          dependencies = templateEngine.analyzeDependencies templates;
        in
        dependencies ? simple-gateway && dependencies.simple-gateway.direct == 'base-gateway'
    " >/dev/null
}

# Main execution
main() {
    log_info "Starting Task 05: Configuration Templates verification"
    log_info "Checking Nix development environment..."
    check_nix_shell
    
    echo
    log_info "Running template system tests..."
    
    # Core functionality tests
    run_test "Template engine file exists" test_template_engine_exists
    run_test "Templates directory structure" test_templates_directory
    run_test "Template engine syntax validation" test_template_engine_syntax
    run_test "Template loading functionality" test_template_loading
    run_test "Template validation" test_template_validation
    run_test "Template instantiation" test_template_instantiation
    
    # Advanced features tests
    run_test "Template inheritance" test_template_inheritance
    run_test "Template composition" test_template_composition
    run_test "Template documentation generation" test_template_documentation
    run_test "Template listing functionality" test_template_listing
    run_test "Parameter validation" test_parameter_validation
    run_test "Template examples" test_template_examples
    run_test "Test suite validity" test_test_suite
    run_test "Module integration" test_module_integration
    run_test "Dependency analysis" test_dependency_analysis
    
    # Summary
    echo
    log_info "Test Summary:"
    echo "  Total tests: $TESTS_TOTAL"
    echo -e "  Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "  Failed: ${RED}$TESTS_FAILED${NC}"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo
        log_success "All tests passed! Task 05: Configuration Templates is complete."
        echo
        log_info "Implemented features:"
        echo "  ✓ Template engine with parameter validation"
        echo "  ✓ 7 common deployment pattern templates"
        echo "  ✓ Template inheritance and composition"
        echo "  ✓ Template documentation generation"
        echo "  ✓ Comprehensive test suite"
        echo "  ✓ Integration with existing modules"
        echo "  ✓ Example usage and documentation"
        exit 0
    else
        echo
        log_error "Some tests failed. Please review the implementation."
        exit 1
    fi
}

# Run main function
main "$@"
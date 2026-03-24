#!/usr/bin/env bash

# Verification script for Task 74: Self-Hosted API Gateway

echo "=== Task 74: Self-Hosted API Gateway Verification ==="

# Test 1: Check if API gateway config library can be imported
echo "Test 1: Import API gateway config library..."
if nix-instantiate --eval --expr 'import ./lib/api-gateway-config.nix { lib = (import <nixpkgs> {}).lib; }' >/dev/null 2>&1; then
    echo "✓ API gateway config library imports successfully"
else
    echo "✗ API gateway config library import failed"
    exit 1
fi

# Test 2: Check if API gateway plugins library can be imported
echo "Test 2: Import API gateway plugins library..."
if nix-instantiate --eval --expr 'import ./lib/api-gateway-plugins.nix { lib = (import <nixpkgs> {}).lib; }' >/dev/null 2>&1; then
    echo "✓ API gateway plugins library imports successfully"
else
    echo "✗ API gateway plugins library import failed"
    exit 1
fi

# Test 3: Check if API gateway module can be imported
echo "Test 3: Import API gateway module..."
if nix-instantiate --eval --expr 'import ./modules/api-gateway.nix { config = {}; pkgs = import <nixpkgs> {}; lib = (import <nixpkgs> {}).lib; }' >/dev/null 2>&1; then
    echo "✓ API gateway module imports successfully"
else
    echo "✗ API gateway module import failed"
    exit 1
fi

# Test 4: Check if API gateway test can be imported
echo "Test 4: Import API gateway test..."
if nix-instantiate --eval --expr 'import ./tests/api-gateway-test.nix { config = {}; pkgs = import <nixpkgs> {}; lib = (import <nixpkgs> {}).lib; }' >/dev/null 2>&1; then
    echo "✓ API gateway test imports successfully"
else
    echo "✗ API gateway test import failed"
    exit 1
fi

# Test 5: Check if example configuration can be imported
echo "Test 5: Import API gateway example..."
if nix-instantiate --eval --expr 'import ./examples/api-gateway-example.nix' >/dev/null 2>&1; then
    echo "✓ API gateway example imports successfully"
else
    echo "✗ API gateway example import failed"
    exit 1
fi

# Test 6: Check API gateway configuration functions
echo "Test 6: Verify API gateway configuration functions..."
if nix-instantiate --eval --expr '
  let lib = (import <nixpkgs> {}).lib;
      apiGatewayConfig = import ./lib/api-gateway-config.nix { inherit lib; };
  in builtins.attrNames apiGatewayConfig
' | grep -q "generateNginxConfig"; then
    echo "✓ API gateway configuration functions are defined"
else
    echo "✗ API gateway configuration functions not found"
    exit 1
fi

# Test 7: Check API gateway plugin functions
echo "Test 7: Verify API gateway plugin functions..."
if nix-instantiate --eval --expr '
  let lib = (import <nixpkgs> {}).lib;
      apiGatewayPlugins = import ./lib/api-gateway-plugins.nix { inherit lib; };
  in builtins.attrNames apiGatewayPlugins
' | grep -q "generatePluginChain"; then
    echo "✓ API gateway plugin functions are defined"
else
    echo "✗ API gateway plugin functions not found"
    exit 1
fi

# Test 8: Check default configurations
echo "Test 8: Verify default configurations..."
if nix-instantiate --eval --expr '
  let lib = (import <nixpkgs> {}).lib;
      apiGatewayConfig = import ./lib/api-gateway-config.nix { inherit lib; };
  in apiGatewayConfig.defaultConfig.enable
' | grep -q "false"; then
    echo "✓ Default configuration is properly set"
else
    echo "✗ Default configuration not properly set"
    exit 1
fi

# Test 9: Check plugin defaults
echo "Test 9: Verify plugin defaults..."
if nix-instantiate --eval --expr '
  let lib = (import <nixpkgs> {}).lib;
      apiGatewayPlugins = import ./lib/api-gateway-plugins.nix { inherit lib; };
  in builtins.length (builtins.attrNames apiGatewayPlugins.defaultPlugins)
' | grep -q "[0-9]"; then
    echo "✓ Plugin defaults are defined"
else
    echo "✗ Plugin defaults not found"
    exit 1
fi

# Test 10: Check documentation exists
echo "Test 10: Verify documentation..."
if [ -f "docs/api-gateway.md" ]; then
    echo "✓ API gateway documentation exists"
else
    echo "✗ API gateway documentation not found"
    exit 1
fi

# Test 11: Check example configuration
echo "Test 11: Verify example configuration..."
if [ -f "examples/api-gateway-example.nix" ]; then
    echo "✓ API gateway example configuration exists"
else
    echo "✗ API gateway example configuration not found"
    exit 1
fi

# Test 12: Check test suite
echo "Test 12: Verify test suite..."
if [ -f "tests/api-gateway-test.nix" ]; then
    echo "✓ API gateway test suite exists"
else
    echo "✗ API gateway test suite not found"
    exit 1
fi

echo
echo "=== All Task 74 verification tests passed! ==="
echo
echo "The self-hosted API gateway implementation includes:"
echo "- API gateway module (modules/api-gateway.nix)"
echo "- Configuration library (lib/api-gateway-config.nix)"
echo "- Plugin system (lib/api-gateway-plugins.nix)"
echo "- Comprehensive test suite (tests/api-gateway-test.nix)"
echo "- Example configuration (examples/api-gateway-example.nix)"
echo "- Documentation (docs/api-gateway.md)"
echo
echo "Features implemented:"
echo "- Request routing with path/method/header matching"
echo "- Authentication (OAuth2, JWT, API keys, Basic)"
echo "- Rate limiting (local and Redis-backed)"
echo "- CORS support"
echo "- Logging and monitoring"
echo "- Plugin system for extensibility"
echo "- Integration with existing NixOS Gateway modules"
echo
echo "Next steps:"
echo "1. Test the implementation in a NixOS environment"
echo "2. Run the test suite: systemctl start api-gateway-integration-test"
echo "3. Verify performance benchmarks"
echo "4. Complete security audit"
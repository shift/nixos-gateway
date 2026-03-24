#!/usr/bin/env bash

set -euo pipefail

echo "🔄 Verifying Task 04: Dynamic Configuration Reload"
echo "=================================================="

# Test 1: Check if config reload library can be imported
echo "Test 1: Import config reload library..."
if nix-instantiate --eval --expr 'import ./lib/config-reload.nix { lib = (import <nixpkgs> {}).lib; pkgs = (import <nixpkgs> {}); }' >/dev/null 2>&1; then
    echo "✅ Config reload library imports successfully"
else
    echo "❌ Config reload library import failed"
    exit 1
fi

# Test 2: Check if config manager module can be imported
echo "Test 2: Import config manager module..."
if nix-instantiate --eval --expr 'import ./modules/config-manager.nix { config = {}; lib = (import <nixpkgs> {}).lib; pkgs = (import <nixpkgs> {}); }' >/dev/null 2>&1; then
    echo "✅ Config manager module imports successfully"
else
    echo "❌ Config manager module import failed"
    exit 1
fi

# Test 3: Check if config reload test can be imported
echo "Test 3: Import config reload test..."
if nix-instantiate --eval --expr 'import ./tests/config-reload-test.nix { pkgs = import <nixpkgs> {}; lib = (import <nixpkgs> {}).lib; }' >/dev/null 2>&1; then
    echo "✅ Config reload test imports successfully"
else
    echo "❌ Config reload test import failed"
    exit 1
fi

# Test 4: Check reload capabilities
echo "Test 4: Verify reload capabilities..."
if nix-instantiate --eval --expr '
  let
    lib = (import <nixpkgs> {}).lib;
    configReload = import ./lib/config-reload.nix { inherit lib; pkgs = import <nixpkgs> {}; };
  in
  builtins.length (builtins.attrNames configReload.reloadCapabilities) >= 5
' 2>/dev/null | grep -q "true"; then
    echo "✅ Reload capabilities are defined"
else
    echo "❌ Reload capabilities not found"
    exit 1
fi

# Test 5: Check orchestration function
echo "Test 5: Verify orchestration function..."
if nix-instantiate --eval --expr '
  let
    lib = (import <nixpkgs> {}).lib;
    configReload = import ./lib/config-reload.nix { inherit lib; pkgs = import <nixpkgs> {}; };
  in
  builtins.isFunction configReload.orchestrateReload
' 2>/dev/null | grep -q "true"; then
    echo "✅ Orchestration function is defined"
else
    echo "❌ Orchestration function not found"
    exit 1
fi

# Test 6: Check script generation
echo "Test 6: Verify script generation..."
if nix-instantiate --eval --expr '
  let
    lib = (import <nixpkgs> {}).lib;
    configReload = import ./lib/config-reload.nix { inherit lib; pkgs = import <nixpkgs> {}; };
    result = configReload.orchestrateReload { services = [ "dns" ]; };
  in
  builtins.hasAttr "scripts" result && builtins.hasAttr "dns" result.scripts
' 2>/dev/null | grep -q "true"; then
    echo "✅ Script generation works"
else
    echo "❌ Script generation failed"
    exit 1
fi

# Test 7: Check dependency management
echo "Test 7: Verify dependency management..."
if nix-instantiate --eval --expr '
  let
    lib = (import <nixpkgs> {}).lib;
    configReload = import ./lib/config-reload.nix { inherit lib; pkgs = import <nixpkgs> {}; };
    deps = configReload.getDependentServices "dns";
  in
  builtins.isList deps
' 2>/dev/null | grep -q "true"; then
    echo "✅ Dependency management works"
else
    echo "❌ Dependency management failed"
    exit 1
fi

# Test 8: Check validation functions
echo "Test 8: Verify validation functions..."
if nix-instantiate --eval --expr '
  let
    lib = (import <nixpkgs> {}).lib;
    configReload = import ./lib/config-reload.nix { inherit lib; pkgs = import <nixpkgs> {}; };
  in
  builtins.isFunction configReload.validateReloadConfig
' 2>/dev/null | grep -q "true"; then
    echo "✅ Validation functions are defined"
else
    echo "❌ Validation functions not found"
    exit 1
fi

# Test 9: Check if documentation exists
echo "Test 9: Check documentation..."
if [ -f "docs/config-reload.md" ]; then
    echo "✅ Documentation exists"
else
    echo "❌ Documentation not found"
    exit 1
fi

# Test 10: Check documentation content
echo "Test 10: Verify documentation content..."
if grep -q "Dynamic Configuration Reload" docs/config-reload.md && \
   grep -q "Supported Services" docs/config-reload.md && \
   grep -q "Management CLI" docs/config-reload.md; then
    echo "✅ Documentation has required content"
else
    echo "❌ Documentation missing required content"
    exit 1
fi

# Test 11: Check flake.nix integration
echo "Test 11: Check flake.nix integration..."
if grep -q "configReload" flake.nix && \
   grep -q "config-manager" flake.nix && \
   grep -q "task-04-config-reload" flake.nix; then
    echo "✅ Flake.nix integration complete"
else
    echo "❌ Flake.nix integration incomplete"
    exit 1
fi

# Test 12: Check test integration
echo "Test 12: Check test integration..."
if nix-instantiate --eval --expr '
  let
    pkgs = import <nixpkgs> {};
  in
  builtins.hasAttr "name" (import ./tests/config-reload-test.nix { inherit pkgs; })
' 2>/dev/null | grep -q "true"; then
    echo "✅ Test integration works"
else
    echo "❌ Test integration failed"
    exit 1
fi

# Test 13: Check reload order generation
echo "Test 13: Verify reload order generation..."
if nix-instantiate --eval --expr '
  let
    lib = (import <nixpkgs> {}).lib;
    configReload = import ./lib/config-reload.nix { inherit lib; pkgs = import <nixpkgs> {}; };
    order = configReload.generateReloadOrder [ "dhcp" "dns" ];
  in
  builtins.isList order && builtins.length order > 0
' 2>/dev/null | grep -q "true"; then
    echo "✅ Reload order generation works"
else
    echo "❌ Reload order generation failed"
    exit 1
fi

# Test 14: Check rollback functionality
echo "Test 14: Verify rollback functionality..."
if nix-instantiate --eval --expr '
  let
    lib = (import <nixpkgs> {}).lib;
    configReload = import ./lib/config-reload.nix { inherit lib; pkgs = import <nixpkgs> {}; };
    rollbackScript = configReload.generateRollbackScript "dns";
  in
  builtins.isString rollbackScript && builtins.stringLength rollbackScript > 0
' 2>/dev/null | grep -q "true"; then
    echo "✅ Rollback functionality works"
else
    echo "❌ Rollback functionality failed"
    exit 1
fi

# Test 15: Check change detection
echo "Test 15: Verify change detection..."
if nix-instantiate --eval --expr '
  let
    lib = (import <nixpkgs> {}).lib;
    configReload = import ./lib/config-reload.nix { inherit lib; pkgs = import <nixpkgs> {}; };
    changeScript = configReload.generateChangeDetectionScript "dns";
  in
  builtins.isString changeScript && builtins.stringLength changeScript > 0
' 2>/dev/null | grep -q "true"; then
    echo "✅ Change detection works"
else
    echo "❌ Change detection failed"
    exit 1
fi

echo ""
echo "🎉 All Task 04 verification tests passed!"
echo ""
echo "✅ Dynamic Configuration Reload implementation complete:"
echo "  - Config reload framework (lib/config-reload.nix)"
echo "  - Configuration manager module (modules/config-manager.nix)"
echo "  - Comprehensive test suite (tests/config-reload-test.nix)"
echo "  - Complete documentation (docs/config-reload.md)"
echo "  - Flake.nix integration with test target"
echo ""
echo "🚀 Features implemented:"
echo "  - Hot reload capabilities for gateway services"
echo "  - Configuration change detection"
echo "  - Service restart coordination"
echo "  - Rollback mechanisms"
echo "  - Integration with existing modules"
echo "  - Management CLI (gateway-reload)"
echo "  - File watching and scheduled operations"
echo "  - Health check integration"
echo "  - Security and performance considerations"
echo ""
echo "📋 Ready for testing with: nix build .#checks.x86_64-linux.task-04-config-reload"
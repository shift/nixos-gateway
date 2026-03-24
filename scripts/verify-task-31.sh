#!/usr/bin/env bash

# Task 31: High Availability Clustering - Verification Script
# This script verifies the HA clustering implementation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

echo "=== Task 31: High Availability Clustering Verification ==="
echo

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print status
print_status() {
    local status=$1
    local message=$2
    if [ "$status" -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $message"
    else
        echo -e "${RED}✗${NC} $message"
    fi
}

# Function to check file existence
check_file() {
    local file=$1
    local description=$2
    if [ -f "$file" ]; then
        print_status 0 "$description found: $file"
        return 0
    else
        print_status 1 "$description missing: $file"
        return 1
    fi
}

# Function to check directory existence
check_dir() {
    local dir=$1
    local description=$2
    if [ -d "$dir" ]; then
        print_status 0 "$description found: $dir"
        return 0
    else
        print_status 1 "$description missing: $dir"
        return 1
    fi
}

# Function to check Nix module syntax
check_nix_syntax() {
    local file=$1
    local description=$2
    if nix-instantiate --parse "$file" >/dev/null 2>&1; then
        print_status 0 "$description syntax valid: $file"
        return 0
    else
        print_status 1 "$description syntax invalid: $file"
        return 1
    fi
}

# Function to check Python syntax
check_python_syntax() {
    local file=$1
    local description=$2
    if python3 -m py_compile "$file" 2>/dev/null; then
        print_status 0 "$description syntax valid: $file"
        return 0
    else
        print_status 1 "$description syntax invalid: $file"
        return 1
    fi
}

# Function to check if module exports expected attributes
check_module_exports() {
    local file=$1
    local attr=$2
    local description=$3
    if nix-instantiate -E "(import $file { lib = import <nixpkgs/lib>; }).$attr" >/dev/null 2>&1; then
        print_status 0 "$description exports $attr: $file"
        return 0
    else
        print_status 1 "$description missing $attr: $file"
        return 1
    fi
}

echo "1. Checking file structure..."
echo

# Check core files
check_file "$PROJECT_ROOT/lib/cluster-manager.nix" "Cluster manager library"
check_file "$PROJECT_ROOT/modules/ha-cluster.nix" "HA cluster module"

echo
echo "2. Checking Nix module syntax..."
echo

# Check syntax
check_nix_syntax "$PROJECT_ROOT/lib/cluster-manager.nix" "Cluster manager library"
check_nix_syntax "$PROJECT_ROOT/modules/ha-cluster.nix" "HA cluster module"

echo
echo "3. Checking module exports..."
echo

# Check exports
check_module_exports "$PROJECT_ROOT/lib/cluster-manager.nix" "defaultHAClusterConfig" "Cluster manager library"
check_module_exports "$PROJECT_ROOT/lib/cluster-manager.nix" "clusterManagerUtils" "Cluster manager library"
check_module_exports "$PROJECT_ROOT/lib/cluster-manager.nix" "utils" "Cluster manager library"

echo
echo "4. Checking Python code..."
echo

# Extract and check Python code
PYTHON_CODE=$(nix-instantiate --eval "$PROJECT_ROOT/lib/cluster-manager.nix" -A clusterManagerUtils.clusterManagerUtils --json | jq -r .)
if [ $? -eq 0 ] && [ -n "$PYTHON_CODE" ]; then
    print_status 0 "Python code extracted from Nix"
    # Write to temp file and check syntax
    TEMP_PYTHON=$(mktemp)
    echo "$PYTHON_CODE" > "$TEMP_PYTHON"
    check_python_syntax "$TEMP_PYTHON" "Embedded Python code"
    rm "$TEMP_PYTHON"
else
    print_status 1 "Failed to extract Python code from Nix"
fi

echo
echo "5. Checking configuration structure..."
echo

# Check default configuration structure
DEFAULT_CONFIG=$(nix-instantiate --eval "$PROJECT_ROOT/lib/cluster-manager.nix" -A defaultHAClusterConfig --json 2>/dev/null)
if [ $? -eq 0 ]; then
    print_status 0 "Default HA cluster configuration loads"

    # Check required sections
    if echo "$DEFAULT_CONFIG" | jq -e '.cluster' >/dev/null 2>&1; then
        print_status 0 "Cluster configuration section present"
    else
        print_status 1 "Cluster configuration section missing"
    fi

    if echo "$DEFAULT_CONFIG" | jq -e '.services' >/dev/null 2>&1; then
        print_status 0 "Services configuration section present"
    else
        print_status 1 "Services configuration section missing"
    fi

    if echo "$DEFAULT_CONFIG" | jq -e '.failover' >/dev/null 2>&1; then
        print_status 0 "Failover configuration section present"
    else
        print_status 1 "Failover configuration section missing"
    fi

    if echo "$DEFAULT_CONFIG" | jq -e '.loadBalancing' >/dev/null 2>&1; then
        print_status 0 "Load balancing configuration section present"
    else
        print_status 1 "Load balancing configuration section missing"
    fi

    if echo "$DEFAULT_CONFIG" | jq -e '.synchronization' >/dev/null 2>&1; then
        print_status 0 "Synchronization configuration section present"
    else
        print_status 1 "Synchronization configuration section missing"
    fi

    if echo "$DEFAULT_CONFIG" | jq -e '.monitoring' >/dev/null 2>&1; then
        print_status 0 "Monitoring configuration section present"
    else
        print_status 1 "Monitoring configuration section missing"
    fi
else
    print_status 1 "Failed to load default HA cluster configuration"
fi

echo
echo "6. Checking module options..."
echo

# Check if module can be imported and has expected options
MODULE_CHECK=$(nix-instantiate --eval -E "
  let
    haCluster = import $PROJECT_ROOT/modules/ha-cluster.nix;
    config = { };
    lib = { mkOption = x: x; types = { str = \"string\"; int = 1; bool = true; listOf = x: x; attrs = {}; enum = x: x; }; mkEnableOption = x: true; mkIf = x: y: y; };
    pkgs = {};
  in
  haCluster { inherit config lib pkgs; }
" 2>/dev/null)

if [ $? -eq 0 ]; then
    print_status 0 "HA cluster module imports successfully"
else
    print_status 1 "HA cluster module import failed"
fi

echo
echo "7. Checking utility functions..."
echo

# Check utility functions
UTILS_CHECK=$(nix-instantiate --eval "$PROJECT_ROOT/lib/cluster-manager.nix" -A utils.validateConfig --json 2>/dev/null)
if [ $? -eq 0 ]; then
    print_status 0 "Configuration validation utility available"
else
    print_status 1 "Configuration validation utility missing"
fi

echo
echo "8. Checking example configurations..."
echo

# Check if we can generate example configs
EXAMPLE_CHECK=$(nix-instantiate --eval -E "
  let
    lib = import <nixpkgs/lib>;
    clusterLib = import $PROJECT_ROOT/lib/cluster-manager.nix { inherit lib; };
    exampleConfig = clusterLib.utils.mergeConfig {
      cluster = {
        name = \"test-cluster\";
        nodes = [
          { name = \"node1\"; address = \"192.168.1.10\"; role = \"active\"; }
          { name = \"node2\"; address = \"192.168.1.11\"; role = \"standby\"; }
        ];
      };
      services.dns.enable = true;
      loadBalancing.enable = true;
    };
  in
  exampleConfig.cluster.name
" 2>/dev/null)

if [ $? -eq 0 ] && [ "$EXAMPLE_CHECK" = "\"test-cluster\"" ]; then
    print_status 0 "Configuration merging works correctly"
else
    print_status 1 "Configuration merging failed"
fi

echo
echo "9. Checking systemd service definitions..."
echo

# Check if systemd services are properly defined
SYSTEMD_CHECK=$(nix-instantiate --eval -E "
  let
    haCluster = import $PROJECT_ROOT/modules/ha-cluster.nix;
    config = {
      services.gateway.haCluster = {
        enable = true;
        cluster = {
          name = \"test-cluster\";
          nodes = [
            { name = \"node1\"; address = \"192.168.1.10\"; role = \"active\"; priority = 100; }
          ];
        };
      };
    };
    lib = { mkOption = x: x; types = { str = \"string\"; int = 1; bool = true; listOf = x: x; attrs = {}; enum = x: x; }; mkEnableOption = x: true; mkIf = x: y: y; };
    pkgs = { writeScriptBin = x: y: { bin = { cluster-manager = \"test\"; }; }; };
  in
  (haCluster { inherit config lib pkgs; }).config.systemd.services.\"ha-cluster-manager\".description
" 2>/dev/null)

if [ $? -eq 0 ]; then
    print_status 0 "Systemd services properly defined"
else
    print_status 1 "Systemd services definition failed"
fi

echo
echo "=== Verification Complete ==="
echo
echo "If all checks passed, Task 31 (High Availability Clustering) is successfully implemented."
echo "The implementation includes:"
echo "- Cluster management and node orchestration"
echo "- State synchronization for configuration and databases"
echo "- Load distribution and traffic balancing"
echo "- Automatic failover procedures"
echo "- Comprehensive monitoring and alerting"
echo "- Integration with systemd services and timers"
echo
echo "Next steps:"
echo "1. Test the implementation in a real NixOS environment"
echo "2. Configure multiple nodes for actual clustering"
echo "3. Monitor cluster health and failover scenarios"
echo "4. Consider implementing additional features from the roadmap"
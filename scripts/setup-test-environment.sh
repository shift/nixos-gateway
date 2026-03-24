#!/usr/bin/env bash
# scripts/setup-test-environment.sh

set -euo pipefail

COMBINATION="${1:-}"
SCENARIO="${2:-comprehensive}"
CONFIG_FILE="${3:-test-configs/${COMBINATION}.nix}"

echo "Setting up test environment for $COMBINATION ($SCENARIO)"

# Create test configuration if it doesn't exist
if [[ ! -f "$CONFIG_FILE" ]]; then
    mkdir -p "$(dirname "$CONFIG_FILE")"

    # Generate basic test configuration
    cat > "$CONFIG_FILE" << EOF
{ config, lib, ... }:

{
  imports = [
    ../modules
  ];

  services.gateway = {
    enable = true;

    interfaces = {
      wan = "eth0";
      lan = "eth1";
    };

    domain = "test.local";

    data = {
      network = {
        subnets = {
          lan = {
            ipv4 = {
              subnet = "192.168.1.0/24";
              gateway = "192.168.1.1";
            };
          };
        };
      };

      hosts = {
        staticDHCPv4Assignments = [
          {
            name = "test-client";
            macAddress = "aa:bb:cc:dd:ee:01";
            ipAddress = "192.168.1.10";
          }
        ];
      };
    };
  };

  # Test environment settings
  virtualisation.memorySize = 2048;
  virtualisation.cores = 2;
  services.getty.autologinUser = "root";
}
EOF

    echo "Created test configuration: $CONFIG_FILE"
fi

# Validate the configuration
echo "Validating test configuration..."
if ! nix-instantiate "$CONFIG_FILE" --eval >/dev/null 2>&1; then
    echo "ERROR: Invalid test configuration"
    exit 1
fi

# Setup test directories
TEST_BASE_DIR="${TEST_BASE_DIR:-test-environment}"
mkdir -p "$TEST_BASE_DIR"
mkdir -p "$TEST_BASE_DIR/logs"
mkdir -p "$TEST_BASE_DIR/results"
mkdir -p "$TEST_BASE_DIR/evidence"

# Create environment metadata
cat > "$TEST_BASE_DIR/environment.json" << EOF
{
  "combination": "$COMBINATION",
  "scenario": "$SCENARIO",
  "config_file": "$CONFIG_FILE",
  "created": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "nix_version": "$(nix --version)",
  "system": "$(uname -a)"
}
EOF

echo "Test environment setup completed"
echo "Environment info: $TEST_BASE_DIR/environment.json"
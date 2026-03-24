#!/usr/bin/env bash
set -e

echo "Verifying Task 20: Network Topology Discovery..."

# 1. Check for new files
if [ ! -f "lib/network-mapper.nix" ]; then
    echo "❌ lib/network-mapper.nix missing"
    exit 1
fi
if [ ! -f "modules/topology-discovery.nix" ]; then
    echo "❌ modules/topology-discovery.nix missing"
    exit 1
fi
if [ ! -f "tests/topology-discovery-test.nix" ]; then
    echo "❌ tests/topology-discovery-test.nix missing"
    exit 1
fi

echo "✅ All required files present."

# 2. Run the test
echo "Running NixOS test..."
if nix build .#checks.x86_64-linux.task-20-network-topology-discovery -L; then
    echo "✅ Test passed successfully."
else
    echo "❌ Test failed."
    exit 1
fi

echo "Task 20 verification complete!"

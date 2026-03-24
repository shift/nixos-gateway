#!/usr/bin/env bash
set -e

echo "Verifying Task 14: Application-Aware Traffic Shaping..."

# 1. Run the NixOS test
echo "Running NixOS integration test..."
if nix build .#checks.x86_64-linux.task-14-app-aware-qos; then
    echo "✅ Test passed!"
    cat result
else
    echo "❌ Test failed!"
    exit 1
fi

echo "Task 14 verification complete."

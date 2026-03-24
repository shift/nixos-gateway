#!/usr/bin/env bash
set -e

echo "Verifying Task 15: Bandwidth Allocation per Device..."

# 1. Run the NixOS test
echo "Running NixOS integration test..."
if nix build .#checks.x86_64-linux.task-15-bandwidth-allocation; then
    echo "✅ Test passed!"
    cat result
else
    echo "❌ Test failed!"
    exit 1
fi

echo "Task 15 verification complete."

#!/usr/bin/env bash
set -e

echo "Verifying Task 21: Performance Baselining..."

# 1. Check for new files
if [ ! -f "lib/baseline-analyzer.nix" ]; then
    echo "❌ lib/baseline-analyzer.nix missing"
    exit 1
fi
if [ ! -f "modules/performance-baselining.nix" ]; then
    echo "❌ modules/performance-baselining.nix missing"
    exit 1
fi
if [ ! -f "tests/performance-baselining-test.nix" ]; then
    echo "❌ tests/performance-baselining-test.nix missing"
    exit 1
fi

echo "✅ All required files present."

# 2. Run the test
echo "Running NixOS test..."
if nix build .#checks.x86_64-linux.task-21-performance-baselining -L; then
    echo "✅ Test passed successfully."
else
    echo "❌ Test failed."
    exit 1
fi

echo "Task 21 verification complete!"

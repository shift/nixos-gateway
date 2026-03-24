#!/usr/bin/env bash
set -e

echo "Verifying Task 22: Zero Trust Microsegmentation..."

# 1. Check for new files
if [ ! -f "lib/trust-engine.nix" ]; then
    echo "❌ lib/trust-engine.nix missing"
    exit 1
fi
if [ ! -f "modules/zero-trust.nix" ]; then
    echo "❌ modules/zero-trust.nix missing"
    exit 1
fi
if [ ! -f "tests/zero-trust-test.nix" ]; then
    echo "❌ tests/zero-trust-test.nix missing"
    exit 1
fi

echo "✅ All required files present."

# 2. Run the test
echo "Running NixOS test..."
if nix build .#checks.x86_64-linux.zero-trust-test -L; then
    echo "✅ Test passed successfully."
else
    echo "❌ Test failed."
    exit 1
fi

echo "Task 22 verification complete!"

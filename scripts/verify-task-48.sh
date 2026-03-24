#!/usr/bin/env bash
set -euo pipefail

echo "Running verification for Task 48 (Failure Recovery)..."

# Build and run the test
if nix build .#checks.x86_64-linux.task-48-failure-recovery -L; then
  echo "✅ Task 48 Verification Passed: Failure scenario tests succeeded."
  exit 0
else
  echo "❌ Task 48 Verification Failed."
  exit 1
fi

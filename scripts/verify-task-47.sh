#!/usr/bin/env bash
set -euo pipefail

echo "Running verification for Task 47 (Performance Benchmarking)..."

# Build and run the test
if nix build .#checks.x86_64-linux.task-47-performance-benchmarking -L; then
  echo "✅ Task 47 Verification Passed: Benchmark test succeeded."
  exit 0
else
  echo "❌ Task 47 Verification Failed."
  exit 1
fi

#!/usr/bin/env bash
set -e

echo "Verifying Task 18: Log Aggregation..."

# Run the new log aggregation test
echo "Running log aggregation test..."
nix build .#checks.x86_64-linux.task-18-log-aggregation --show-trace

echo "✅ Task 18 verification successful!"

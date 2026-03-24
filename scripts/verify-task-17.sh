#!/usr/bin/env bash
set -e

echo "Verifying Task 17: Distributed Tracing..."

# Run the new distributed tracing test
echo "Running distributed tracing test..."
nix build .#checks.x86_64-linux.task-17-distributed-tracing --show-trace

echo "✅ Task 17 verification successful!"

#!/usr/bin/env bash
set -e

echo "Verifying Task 16: Service Level Objectives..."

# Run the SLO test
echo "Running SLO integration test..."
nix build .#checks.x86_64-linux.task-16-slo -L

echo "Task 16 verification passed!"

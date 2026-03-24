#!/usr/bin/env bash
# scripts/cleanup-test-environment.sh

set -euo pipefail

COMBINATION="${1:-}"
SCENARIO="${2:-comprehensive}"

echo "Cleaning up test environment for $COMBINATION ($SCENARIO)"

TEST_BASE_DIR="${TEST_BASE_DIR:-test-environment}"

# Archive logs and results
if [[ -d "$TEST_BASE_DIR" ]]; then
    ARCHIVE_NAME="test-archive-$(date +%Y%m%d-%H%M%S).tar.gz"

    echo "Archiving test environment to $ARCHIVE_NAME"
    tar -czf "$ARCHIVE_NAME" -C "$(dirname "$TEST_BASE_DIR")" "$(basename "$TEST_BASE_DIR")"

    # Clean up test directories
    rm -rf "$TEST_BASE_DIR"

    echo "Test environment archived and cleaned up"
else
    echo "No test environment found to clean up"
fi

# Clean up any temporary files
find . -name "*.tmp" -type f -delete 2>/dev/null || true
find . -name "*~" -type f -delete 2>/dev/null || true

# Clean up old archives (keep last 5)
ls -t test-archive-*.tar.gz 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null || true

echo "Cleanup completed"
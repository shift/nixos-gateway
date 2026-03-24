#!/usr/bin/env bash

# Test Status Checker - Quick overview of test results
# Usage: ./test-status.sh [run_id]

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$PROJECT_ROOT/test-results"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Get run ID from argument or use latest
RUN_ID="${1:-}"
if [[ -z "$RUN_ID" ]]; then
    RUN_ID=$(ls -t "$LOG_DIR" 2>/dev/null | head -1 || echo "")
fi

if [[ -z "$RUN_ID" ]]; then
    echo -e "${RED}No test runs found${NC}"
    exit 1
fi

SUMMARY_FILE="$LOG_DIR/$RUN_ID/test_summary.json"

if [[ ! -f "$SUMMARY_FILE" ]]; then
    echo -e "${RED}Test summary not found for run: $RUN_ID${NC}"
    exit 1
fi

# Extract data from summary
TOTAL_TESTS=$(jq -r '.total_tests' "$SUMMARY_FILE")
PASSED_TESTS=$(jq -r '.passed_tests' "$SUMMARY_FILE")
FAILED_TESTS=$(jq -r '.failed_tests' "$SUMMARY_FILE")
SKIPPED_TESTS=$(jq -r '.skipped_tests' "$SUMMARY_FILE")
SUCCESS_RATE=$(jq -r '.success_rate' "$SUMMARY_FILE")

# Display summary
echo -e "${PURPLE}=== Test Status for $RUN_ID ===${NC}"
echo
echo -e "${BLUE}Total Tests:${NC} $TOTAL_TESTS"
echo -e "${GREEN}Passed:${NC} $PASSED_TESTS"
echo -e "${RED}Failed:${NC} $FAILED_TESTS"
echo -e "${YELLOW}Skipped:${NC} $SKIPPED_TESTS"
echo -e "${BLUE}Success Rate:${NC} ${SUCCESS_RATE}%"
echo

# Show recent failures if any
if [[ "$FAILED_TESTS" -gt 0 ]]; then
    echo -e "${RED}=== Recent Failures ===${NC}"
    
    # Get failed tests
    jq -r '.test_results | to_entries[] | select(.value != "passed") | "\(.key) - \(.value)"' "$SUMMARY_FILE" | head -10 | while read line; do
        echo -e "${RED}✗ $line${NC}"
    done
    echo
fi

# Show feature status
FEATURE_COUNT=$(jq -r '.feature_results | length' "$SUMMARY_FILE")
if [[ "$FEATURE_COUNT" -gt 0 ]]; then
    echo -e "${BLUE}=== Feature Status ===${NC}"
    
    jq -r '.feature_results | to_entries[] | "\(.key) - \(.value)"' "$SUMMARY_FILE" | while read line; do
        if [[ "$line" =~ passed$ ]]; then
            echo -e "${GREEN}✓ $line${NC}"
        else
            echo -e "${RED}✗ $line${NC}"
        fi
    done
    echo
fi

# Show task status
TASK_COUNT=$(jq -r '.task_results | length' "$SUMMARY_FILE")
if [[ "$TASK_COUNT" -gt 0 ]]; then
    echo -e "${BLUE}=== Task Status ===${NC}"
    
    jq -r '.task_results | to_entries[] | "\(.key) - \(.value)"' "$SUMMARY_FILE" | while read line; do
        if [[ "$line" =~ passed$ ]]; then
            echo -e "${GREEN}✓ $line${NC}"
        else
            echo -e "${RED}✗ $line${NC}"
        fi
    done
    echo
fi

# Show available runs
echo -e "${BLUE}=== Available Test Runs ===${NC}"
ls -t "$LOG_DIR" 2>/dev/null | head -10 | while read run; do
    if [[ "$run" == "$RUN_ID" ]]; then
        echo -e "${GREEN}> $run (current)${NC}"
    else
        echo "  $run"
    fi
done

echo
echo -e "${BLUE}Full report:${NC} $LOG_DIR/$RUN_ID/test_summary.md"
echo -e "${BLUE}Logs directory:${NC} $LOG_DIR/$RUN_ID/logs/"
#!/usr/bin/env bash
# batch-analyze-evidence.sh - Analyze collected test evidence

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

EVIDENCE_DIR="$1"
ANALYSIS_DIR="$2"

if [[ -z "$EVIDENCE_DIR" || -z "$ANALYSIS_DIR" ]]; then
    echo "Usage: $0 <evidence_dir> <analysis_dir>"
    exit 1
fi

mkdir -p "$ANALYSIS_DIR"

echo "Analyzing evidence from: $EVIDENCE_DIR"
echo "Output analysis to: $ANALYSIS_DIR"

# Initialize analysis results
cat > "$ANALYSIS_DIR/summary.json" << EOF
{
  "evidence_analysis": {
    "timestamp": "$(date -Iseconds)",
    "evidence_directory": "$EVIDENCE_DIR",
    "total_tests": 0,
    "evidence_types_found": [],
    "completeness_score": 0,
    "issues": []
  }
}
EOF

# Count test directories
if [[ -d "$EVIDENCE_DIR" ]]; then
    TEST_COUNT=$(find "$EVIDENCE_DIR" -maxdepth 1 -type d | wc -l)
    TEST_COUNT=$((TEST_COUNT - 1))  # Subtract the evidence dir itself

    echo "Found $TEST_COUNT test evidence directories"

    # Analyze each test's evidence
    for test_dir in "$EVIDENCE_DIR"/*/; do
        if [[ -d "$test_dir" ]]; then
            test_name=$(basename "$test_dir")
            echo "Analyzing test: $test_name"

            # Check for evidence types
            evidence_types=()
            [[ -f "$test_dir/logs/system.log" ]] && evidence_types+=("system_logs")
            [[ -f "$test_dir/metrics/performance.json" ]] && evidence_types+=("performance_metrics")
            [[ -f "$test_dir/outputs/commands.txt" ]] && evidence_types+=("command_outputs")
            [[ -d "$test_dir/configs" ]] && evidence_types+=("configurations")

            # Create test analysis
            cat > "$ANALYSIS_DIR/${test_name}-analysis.json" << EOF
{
  "test_name": "$test_name",
  "evidence_types": [$(printf '"%s",' "${evidence_types[@]}" | sed 's/,$//')],
  "evidence_count": ${#evidence_types[@]},
  "analysis_timestamp": "$(date -Iseconds)",
  "completeness": $((${#evidence_types[@]} * 25))
}
EOF
        fi
    done
else
    echo "Evidence directory not found: $EVIDENCE_DIR"
fi

echo "Evidence analysis complete"
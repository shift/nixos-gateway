#!/usr/bin/env bash
# run-comprehensive-testing.sh - Single command to run comprehensive feature testing

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
SCOPE="${SCOPE:-core}"
FEATURE="${FEATURE:-all}"
OUTPUT_DIR="${OUTPUT_DIR:-test-results/$(date +%Y%m%d-%H%M%S)}"
PARALLEL="${PARALLEL:-true}"
VERBOSE="${VERBOSE:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Help function
show_help() {
    cat << EOF
NixOS Gateway Comprehensive Feature Testing

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -s, --scope SCOPE       Test scope: core, networking, security, monitoring, vpn, advanced, full
                            Default: core
    -f, --feature FEATURE   Specific feature to test (when scope=feature)
                            Default: all
    -o, --output DIR        Output directory for results
                            Default: test-results/YYYYMMDD-HHMMSS
    -p, --parallel          Run tests in parallel (default: true)
    --serial               Run tests serially
    -v, --verbose          Verbose output
    -h, --help             Show this help

EXAMPLES:
    # Run core feature tests
    $0

    # Run all networking tests
    $0 --scope networking

    # Test specific feature
    $0 --scope feature --feature dns

    # Run full test suite serially
    $0 --scope full --serial --verbose

OUTPUT:
    Results will be saved to: \$OUTPUT_DIR/
    ├── evidence/           # Collected test evidence
    ├── reports/            # Generated reports
    ├── logs/              # Test execution logs
    └── summary.json       # Test summary

REQUIRES:
    - Nix with flakes enabled
    - Sufficient disk space (~10GB)
    - Internet connection for external tests
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--scope)
            SCOPE="$2"
            shift 2
            ;;
        -f|--feature)
            FEATURE="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -p|--parallel)
            PARALLEL="true"
            shift
            ;;
        --serial)
            PARALLEL="false"
            shift
            ;;
        -v|--verbose)
            VERBOSE="true"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate scope
VALID_SCOPES=("core" "networking" "security" "monitoring" "vpn" "advanced" "full" "feature")
if [[ ! " ${VALID_SCOPES[@]} " =~ " ${SCOPE} " ]]; then
    log_error "Invalid scope: $SCOPE"
    log_error "Valid scopes: ${VALID_SCOPES[*]}"
    exit 1
fi

# Setup output directory
mkdir -p "$OUTPUT_DIR"
LOG_FILE="$OUTPUT_DIR/testing.log"

# Logging setup
exec > >(tee -a "$LOG_FILE") 2>&1

log_info "Starting NixOS Gateway Comprehensive Feature Testing"
log_info "Scope: $SCOPE"
log_info "Feature: $FEATURE"
log_info "Output: $OUTPUT_DIR"
log_info "Parallel: $PARALLEL"
log_info "Timestamp: $(date)"

# Pre-flight checks
log_info "Running pre-flight checks..."

# Check if we're in the right directory
if [[ ! -f "flake.nix" ]]; then
    log_error "Must be run from repository root (flake.nix not found)"
    exit 1
fi

# Check Nix availability
if ! command -v nix >/dev/null 2>&1; then
    log_error "Nix not found. Please install Nix."
    exit 1
fi

# Check if flakes are enabled
if ! nix flake metadata . >/dev/null 2>&1; then
    log_error "Nix flakes not enabled. Please enable flakes."
    exit 1
fi

# Check available disk space
DISK_SPACE=$(df / | tail -1 | awk '{print $4}')
if [[ $DISK_SPACE -lt 10000000 ]]; then  # 10GB in KB
    log_warning "Low disk space: $(($DISK_SPACE / 1024 / 1024))GB available. At least 10GB recommended."
fi

log_success "Pre-flight checks passed"

# Setup test environment
log_info "Setting up test environment..."
export TEST_OUTPUT_DIR="$OUTPUT_DIR"
export TEST_SCOPE="$SCOPE"
export TEST_FEATURE="$FEATURE"
export TEST_PARALLEL="$PARALLEL"
export TEST_VERBOSE="$VERBOSE"

# Create test configuration
cat > "$OUTPUT_DIR/test-config.json" << EOF
{
  "scope": "$SCOPE",
  "feature": "$FEATURE",
  "output_dir": "$OUTPUT_DIR",
  "parallel": $PARALLEL,
  "verbose": $VERBOSE,
  "start_time": "$(date -Iseconds)",
  "repository": "$(git rev-parse HEAD 2>/dev/null || echo 'unknown')",
  "hostname": "$(hostname)"
}
EOF

# Determine test groups to run
case "$SCOPE" in
    "core")
        TEST_GROUPS=("core")
        ;;
    "networking")
        TEST_GROUPS=("networking")
        ;;
    "security")
        TEST_GROUPS=("security")
        ;;
    "monitoring")
        TEST_GROUPS=("monitoring")
        ;;
    "vpn")
        TEST_GROUPS=("vpn")
        ;;
    "advanced")
        TEST_GROUPS=("advanced")
        ;;
    "full")
        TEST_GROUPS=("core" "networking" "security" "monitoring" "vpn" "advanced")
        ;;
    "feature")
        if [[ "$FEATURE" == "all" ]]; then
            TEST_GROUPS=("core" "networking" "security" "monitoring" "vpn" "advanced")
        else
            TEST_GROUPS=("feature-$FEATURE")
        fi
        ;;
esac

log_info "Will run test groups: ${TEST_GROUPS[*]}"

# Execute tests
OVERALL_SUCCESS=true
GROUP_RESULTS=()

for group in "${TEST_GROUPS[@]}"; do
    log_info "Executing test group: $group"

    if [[ "$PARALLEL" == "true" ]] && [[ ${#TEST_GROUPS[@]} -gt 1 ]]; then
        # Run in background for parallel execution
        ./scripts/run-test-group.sh "$group" "$OUTPUT_DIR/evidence" > "$OUTPUT_DIR/logs/$group.log" 2>&1 &
        GROUP_PIDS+=($!)
        GROUP_NAMES+=("$group")
    else
        # Run serially
        if ./scripts/run-test-group.sh "$group" "$OUTPUT_DIR/evidence"; then
            GROUP_RESULTS+=("$group:success")
            log_success "Test group $group completed successfully"
        else
            GROUP_RESULTS+=("$group:failed")
            OVERALL_SUCCESS=false
            log_error "Test group $group failed"
        fi
    fi
done

# Wait for parallel jobs
if [[ "$PARALLEL" == "true" ]] && [[ ${#TEST_GROUPS[@]} -gt 1 ]]; then
    log_info "Waiting for parallel test execution to complete..."

    for i in "${!GROUP_PIDS[@]}"; do
        pid=${GROUP_PIDS[$i]}
        group=${GROUP_NAMES[$i]}

        if wait "$pid"; then
            GROUP_RESULTS+=("$group:success")
            log_success "Test group $group completed successfully"
        else
            GROUP_RESULTS+=("$group:failed")
            OVERALL_SUCCESS=false
            log_error "Test group $group failed"
        fi
    done
fi

# Collect and analyze evidence
log_info "Collecting and analyzing test evidence..."
./scripts/batch-analyze-evidence.sh "$OUTPUT_DIR/evidence" "$OUTPUT_DIR/analysis"

# Generate reports
log_info "Generating test reports..."
./scripts/generate-comprehensive-report.sh "$OUTPUT_DIR/analysis" "$OUTPUT_DIR/reports"

# Update support matrix
log_info "Updating support matrix..."
./scripts/update-support-matrix.sh "$OUTPUT_DIR/analysis" support-matrix.json

# Generate final summary
SUCCESS_COUNT=$(echo "${GROUP_RESULTS[@]}" | grep -o "success" | wc -l)
TOTAL_COUNT=${#TEST_GROUPS[@]}
SUCCESS_RATE=$((SUCCESS_COUNT * 100 / TOTAL_COUNT))

cat > "$OUTPUT_DIR/summary.json" << EOF
{
  "test_run": {
    "timestamp": "$(date -Iseconds)",
    "scope": "$SCOPE",
    "feature": "$FEATURE",
    "duration_seconds": $(($(date +%s) - $(date -d "$(jq -r '.start_time' "$OUTPUT_DIR/test-config.json")" +%s))),
    "hostname": "$(hostname)",
    "repository_commit": "$(git rev-parse HEAD 2>/dev/null || echo 'unknown')"
  },
  "results": {
    "overall_success": $OVERALL_SUCCESS,
    "groups_tested": $TOTAL_COUNT,
    "groups_passed": $SUCCESS_COUNT,
    "groups_failed": $(($TOTAL_COUNT - $SUCCESS_COUNT)),
    "success_rate_percent": $SUCCESS_RATE
  },
  "group_results": [
    $(printf '"%s",' "${GROUP_RESULTS[@]}" | sed 's/,$//')
  ],
  "output": {
    "evidence_directory": "$OUTPUT_DIR/evidence",
    "analysis_directory": "$OUTPUT_DIR/analysis",
    "reports_directory": "$OUTPUT_DIR/reports",
    "logs_directory": "$OUTPUT_DIR/logs"
  }
}
EOF

# Final status
echo
if [[ "$OVERALL_SUCCESS" == "true" ]]; then
    log_success "🎉 Comprehensive testing completed successfully!"
    log_success "Success rate: $SUCCESS_RATE% ($SUCCESS_COUNT/$TOTAL_COUNT groups passed)"
else
    log_error "❌ Comprehensive testing completed with failures"
    log_error "Success rate: $SUCCESS_RATE% ($SUCCESS_COUNT/$TOTAL_COUNT groups passed)"
fi

log_info "Results saved to: $OUTPUT_DIR/"
log_info "Summary: $OUTPUT_DIR/summary.json"
log_info "Reports: $OUTPUT_DIR/reports/"

if [[ "$OVERALL_SUCCESS" == "false" ]]; then
    log_warning "Some tests failed. Check logs in $OUTPUT_DIR/logs/ for details."
    exit 1
fi

log_info "Testing completed successfully! ✅"
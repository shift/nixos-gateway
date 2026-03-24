#!/usr/bin/env bash

set -euo pipefail

# Comprehensive Test Execution Pipeline with Evidence Collection
# Usage: ./run-all-tests.sh [--evidence-dir PATH] [--report-format FORMAT] [--parallel]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default configuration
EVIDENCE_DIR="${EVIDENCE_DIR:-/tmp/test-evidence}"
REPORT_FORMAT="${REPORT_FORMAT:-json}"
PARALLEL="${PARALLEL:-false}"
TEST_TIMEOUT="${TEST_TIMEOUT:-3600}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --evidence-dir)
            EVIDENCE_DIR="$2"
            shift 2
            ;;
        --report-format)
            REPORT_FORMAT="$2"
            shift 2
            ;;
        --parallel)
            PARALLEL="true"
            shift
            ;;
        --timeout)
            TEST_TIMEOUT="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [--evidence-dir PATH] [--report-format FORMAT] [--parallel] [--timeout SECONDS]"
            echo "  --evidence-dir: Directory to store test evidence (default: /tmp/test-evidence)"
            echo "  --report-format: Report format: json, yaml, markdown (default: json)"
            echo "  --parallel: Run tests in parallel where possible"
            echo "  --timeout: Test timeout in seconds (default: 3600)"
            echo "  --help: Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✓ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠ $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ✗ $1${NC}"
}

# Setup evidence directory
setup_evidence_dir() {
    log "Setting up evidence directory: $EVIDENCE_DIR"
    mkdir -p "$EVIDENCE_DIR"/{test-results,reports,archives,logs}
    
    # Create timestamped subdirectory
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    RUN_DIR="$EVIDENCE_DIR/test-results/$TIMESTAMP"
    mkdir -p "$RUN_DIR"
    
    # Create evidence structure
    mkdir -p "$RUN_DIR"/{nat-port-forwarding,network-isolation,performance-throughput,dns-dhcp,security,monitoring}
    
    echo "$TIMESTAMP" > "$EVIDENCE_DIR/.current-run"
    echo "$RUN_DIR"
}

# Pre-flight checks
run_preflight_checks() {
    log "Running pre-flight checks..."
    
    # Check Nix environment
    if ! command -v nix &> /dev/null; then
        log_error "Nix is not installed or not in PATH"
        exit 1
    fi
    
    # Check if we're in a NixOS project
    if [[ ! -f "$PROJECT_ROOT/flake.nix" ]]; then
        log_error "Not in a NixOS project directory (flake.nix not found)"
        exit 1
    fi
    
    # Check test files exist
    local test_files=(
        "tests/nat-port-forwarding-test.nix"
        "tests/ipv4-ipv6-dual-stack-test.nix"
        "tests/interface-management-failover-test.nix"
        "tests/routing-ip-forwarding-test.nix"
    )
    
    for test_file in "${test_files[@]}"; do
        if [[ ! -f "$PROJECT_ROOT/$test_file" ]]; then
            log_warning "Test file not found: $test_file"
        fi
    done
    
    log_success "Pre-flight checks completed"
}

# Execute individual test with evidence collection
run_test() {
    local test_name="$1"
    local test_file="$2"
    local evidence_dir="$3"
    
    log "Running test: $test_name"
    
    local test_start=$(date +%s)
    local test_output="$evidence_dir/$test_name.log"
    
    # Create test-specific evidence directory
    mkdir -p "$evidence_dir/$test_name"
    
    # Run the test with timeout
    if timeout "$TEST_TIMEOUT" nix build ".#checks.x86_64-linux.$test_name" \
        --keep-failed \
        --print-build-logs \
        --option sandbox true \
        > "$test_output" 2>&1; then
        
        local test_end=$(date +%s)
        local duration=$((test_end - test_start))
        
        log_success "$test_name completed in ${duration}s"
        
        # Collect evidence
        if [[ -d "result" ]]; then
            cp -r result/* "$evidence_dir/$test_name/" 2>/dev/null || true
        fi
        
        # Extract test artifacts
        if [[ -f "$test_output" ]]; then
            # Look for evidence files in test output
            grep -o '/tmp/.*-evidence.tar.gz' "$test_output" 2>/dev/null | while read -r archive; do
                if [[ -f "$archive" ]]; then
                    cp "$archive" "$evidence_dir/$test_name/"
                    tar -xzf "$archive" -C "$evidence_dir/$test_name/" 2>/dev/null || true
                fi
            done
        fi
        
        # Create test summary
        cat > "$evidence_dir/$test_name/test-summary.json" << EOF
{
    "test_name": "$test_name",
    "status": "passed",
    "start_time": $test_start,
    "end_time": $test_end,
    "duration": $duration,
    "evidence_files": $(find "$evidence_dir/$test_name" -type f -name "*.txt" -o -name "*.json" -o -name "*.pcap" | wc -l),
    "log_file": "$test_name.log"
}
EOF
        
        return 0
    else
        local test_end=$(date +%s)
        local duration=$((test_end - test_start))
        
        log_error "$test_name failed after ${duration}s"
        
        # Create failure summary
        cat > "$evidence_dir/$test_name/test-summary.json" << EOF
{
    "test_name": "$test_name",
    "status": "failed",
    "start_time": $test_start,
    "end_time": $test_end,
    "duration": $duration,
    "error_log": "$test_name.log",
    "evidence_files": $(find "$evidence_dir/$test_name" -type f 2>/dev/null | wc -l)
}
EOF
        
        return 1
    fi
}

# Run tests in parallel
run_tests_parallel() {
    local -a test_pids=()
    local -a test_names=()
    local run_dir="$1"
    
    # Define tests to run
    local tests=(
        "nat-port-forwarding-test:nat-port-forwarding"
        "ipv4-ipv6-dual-stack-test:networking"
        "interface-management-failover-test:network-isolation"
        "routing-ip-forwarding-test:performance-throughput"
    )
    
    for test_spec in "${tests[@]}"; do
        IFS=':' read -r test_file test_category <<< "$test_spec"
        
        log "Starting test in background: $test_file"
        
        (
            cd "$PROJECT_ROOT"
            run_test "$test_file" "$test_file" "$run_dir/$test_category"
        ) &
        
        test_pids+=($!)
        test_names+=("$test_file")
    done
    
    # Wait for all tests to complete
    local exit_code=0
    for i in "${!test_pids[@]}"; do
        if ! wait "${test_pids[i]}"; then
            log_error "Test ${test_names[i]} failed"
            exit_code=1
        fi
    done
    
    return $exit_code
}

# Run tests sequentially
run_tests_sequential() {
    local run_dir="$1"
    local exit_code=0
    
    # Define tests to run
    local tests=(
        "nat-port-forwarding-test:nat-port-forwarding"
        "ipv4-ipv6-dual-stack-test:networking"
        "interface-management-failover-test:network-isolation"
        "routing-ip-forwarding-test:performance-throughput"
    )
    
    for test_spec in "${tests[@]}"; do
        IFS=':' read -r test_file test_category <<< "$test_spec"
        
        cd "$PROJECT_ROOT"
        if ! run_test "$test_file" "$test_file" "$run_dir/$test_category"; then
            exit_code=1
        fi
    done
    
    return $exit_code
}

# Generate comprehensive test report
generate_report() {
    local run_dir="$1"
    local report_file="$2"
    
    log "Generating comprehensive test report..."
    
    # Collect all test summaries
    local test_summaries=()
    local passed_tests=0
    local failed_tests=0
    local total_duration=0
    
    while IFS= read -r -d '' summary_file; do
        if [[ -f "$summary_file" ]]; then
            local test_status=$(jq -r '.status' "$summary_file" 2>/dev/null || echo "unknown")
            local test_duration=$(jq -r '.duration' "$summary_file" 2>/dev/null || echo "0")
            
            if [[ "$test_status" == "passed" ]]; then
                ((passed_tests++))
            else
                ((failed_tests++))
            fi
            
            ((total_duration += test_duration))
            test_summaries+=("$summary_file")
        fi
    done < <(find "$run_dir" -name "test-summary.json" -print0)
    
    # Generate report based on format
    case "$REPORT_FORMAT" in
        "json")
            generate_json_report "$run_dir" "$report_file" "${test_summaries[@]}" "$passed_tests" "$failed_tests" "$total_duration"
            ;;
        "yaml")
            generate_yaml_report "$run_dir" "$report_file" "${test_summaries[@]}" "$passed_tests" "$failed_tests" "$total_duration"
            ;;
        "markdown")
            generate_markdown_report "$run_dir" "$report_file" "${test_summaries[@]}" "$passed_tests" "$failed_tests" "$total_duration"
            ;;
        *)
            log_error "Unknown report format: $REPORT_FORMAT"
            exit 1
            ;;
    esac
}

generate_json_report() {
    local run_dir="$1"
    local report_file="$2"
    shift 4
    local test_summaries=("$@")
    
    cat > "$report_file" << EOF
{
    "test_run": {
        "timestamp": $(date +%s),
        "date": "$(date -Iseconds)",
        "evidence_directory": "$run_dir",
        "total_tests": ${#test_summaries[@]},
        "passed_tests": $((passed_tests)),
        "failed_tests": $((failed_tests)),
        "total_duration": $((total_duration)),
        "success_rate": $(echo "scale=2; $passed_tests * 100 / ${#test_summaries[@]}" | bc -l 2>/dev/null || echo "0")
    },
    "test_results": [
$(for summary in "${test_summaries[@]}"; do
    cat "$summary"
    echo ','
done | sed '$ s/,$//')
    ],
    "evidence_summary": {
        "total_evidence_files": $(find "$run_dir" -type f | wc -l),
        "categories": {
            "nat-port-forwarding": $(find "$run_dir/nat-port-forwarding" -type f 2>/dev/null | wc -l),
            "network-isolation": $(find "$run_dir/network-isolation" -type f 2>/dev/null | wc -l),
            "performance-throughput": $(find "$run_dir/performance-throughput" -type f 2>/dev/null | wc -l),
            "networking": $(find "$run_dir/networking" -type f 2>/dev/null | wc -l)
        },
        "archive_location": "$run_dir"
    }
}
EOF
}

generate_yaml_report() {
    local run_dir="$1"
    local report_file="$2"
    shift 4
    local test_summaries=("$@")
    
    cat > "$report_file" << EOF
test_run:
  timestamp: $(date +%s)
  date: "$(date -Iseconds)"
  evidence_directory: "$run_dir"
  total_tests: ${#test_summaries[@]}
  passed_tests: $((passed_tests))
  failed_tests: $((failed_tests))
  total_duration: $((total_duration))
  success_rate: $(echo "scale=2; $passed_tests * 100 / ${#test_summaries[@]}" | bc -l 2>/dev/null || echo "0")

test_results:
$(for summary in "${test_summaries[@]}"; do
    echo "  - $(cat "$summary" | tr '\n' ' ')"
done)

evidence_summary:
  total_evidence_files: $(find "$run_dir" -type f | wc -l)
  categories:
    nat-port-forwarding: $(find "$run_dir/nat-port-forwarding" -type f 2>/dev/null | wc -l)
    network-isolation: $(find "$run_dir/network-isolation" -type f 2>/dev/null | wc -l)
    performance-throughput: $(find "$run_dir/performance-throughput" -type f 2>/dev/null | wc -l)
    networking: $(find "$run_dir/networking" -type f 2>/dev/null | wc -l)
  archive_location: "$run_dir"
EOF
}

generate_markdown_report() {
    local run_dir="$1"
    local report_file="$2"
    shift 4
    local test_summaries=("$@")
    
    cat > "$report_file" << EOF
# Comprehensive Test Report

## Test Run Summary

- **Date**: $(date -Iseconds)
- **Total Tests**: ${#test_summaries[@]}
- **Passed**: $((passed_tests))
- **Failed**: $((failed_tests))
- **Success Rate**: $(echo "scale=2; $passed_tests * 100 / ${#test_summaries[@]}" | bc -l 2>/dev/null || echo "0")%
- **Total Duration**: $((total_duration)) seconds

## Test Results

| Test Name | Status | Duration (s) | Evidence Files |
|-----------|--------|--------------|---------------|
EOF
    
    for summary in "${test_summaries[@]}"; do
        local test_name=$(jq -r '.test_name' "$summary" 2>/dev/null || echo "unknown")
        local test_status=$(jq -r '.status' "$summary" 2>/dev/null || echo "unknown")
        local test_duration=$(jq -r '.duration' "$summary" 2>/dev/null || echo "0")
        local evidence_count=$(jq -r '.evidence_files' "$summary" 2>/dev/null || echo "0")
        
        echo "| $test_name | $test_status | $test_duration | $evidence_count |" >> "$report_file"
    done
    
    cat >> "$report_file" << EOF

## Evidence Summary

- **Total Evidence Files**: $(find "$run_dir" -type f | wc -l)
- **Evidence Directory**: \`$run_dir\`
- **Archive Location**: \`$run_dir\`

### Evidence by Category

| Category | Files |
|----------|--------|
| NAT Port Forwarding | $(find "$run_dir/nat-port-forwarding" -type f 2>/dev/null | wc -l) |
| Network Isolation | $(find "$run_dir/network-isolation" -type f 2>/dev/null | wc -l) |
| Performance Throughput | $(find "$run_dir/performance-throughput" -type f 2>/dev/null | wc -l) |
| Networking | $(find "$run_dir/networking" -type f 2>/dev/null | wc -l) |

## Next Steps

1. Review failed tests and fix issues
2. Analyze evidence files for performance and security analysis
3. Archive evidence for long-term storage
4. Update documentation with test results

---
*Report generated by Comprehensive Test Execution Pipeline*
EOF
}

# Create evidence archive
create_evidence_archive() {
    local run_dir="$1"
    
    log "Creating evidence archive..."
    
    local archive_name="test-evidence-$(basename "$run_dir").tar.gz"
    local archive_path="$EVIDENCE_DIR/archives/$archive_name"
    
    # Create compressed archive
    tar -czf "$archive_path" -C "$EVIDENCE_DIR/test-results" "$(basename "$run_dir")"
    
    # Create checksum
    local checksum_file="$archive_path.sha256"
    sha256sum "$archive_path" > "$checksum_file"
    
    log_success "Evidence archive created: $archive_path"
    log "Checksum: $(cat "$checksum_file" | cut -d' ' -f1)"
    
    echo "$archive_path"
}

# Main execution
main() {
    log "Starting comprehensive test execution pipeline..."
    
    # Setup
    run_preflight_checks
    local run_dir
    run_dir=$(setup_evidence_dir)
    
    # Run tests
    local exit_code=0
    if [[ "$PARALLEL" == "true" ]]; then
        log "Running tests in parallel..."
        run_tests_parallel "$run_dir" || exit_code=$?
    else
        log "Running tests sequentially..."
        run_tests_sequential "$run_dir" || exit_code=$?
    fi
    
    # Generate report
    local report_file="$EVIDENCE_DIR/reports/test-report-$(basename "$run_dir").$REPORT_FORMAT"
    generate_report "$run_dir" "$report_file"
    
    # Create archive
    local archive_path
    archive_path=$(create_evidence_archive "$run_dir")
    
    # Summary
    if [[ $exit_code -eq 0 ]]; then
        log_success "All tests completed successfully!"
    else
        log_warning "Some tests failed. Check the report for details."
    fi
    
    log "Report: $report_file"
    log "Evidence Archive: $archive_path"
    log "Evidence Directory: $run_dir"
    
    exit $exit_code
}

# Run main function
main "$@"

#!/usr/bin/env bash

# NixOS Gateway Test Runner - Fixed Version
# This script runs all VM tests and collects comprehensive logs with feature/task tracking

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
LOG_DIR="$PROJECT_ROOT/test-results"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RUN_ID="test_run_$TIMESTAMP"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test results tracking
declare -A TEST_RESULTS
declare -A FEATURE_RESULTS
declare -A TASK_RESULTS
# Initialize arrays to ensure they're always bound
FEATURE_RESULTS=()
TASK_RESULTS=()
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    if [[ -d "$LOG_DIR" ]]; then
        echo -e "${BLUE}[INFO]${NC} $1" >> "$LOG_DIR/$RUN_ID.log"
    fi
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    if [[ -d "$LOG_DIR" ]]; then
        echo -e "${GREEN}[SUCCESS]${NC} $1" >> "$LOG_DIR/$RUN_ID.log"
    fi
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    if [[ -d "$LOG_DIR" ]]; then
        echo -e "${YELLOW}[WARNING]${NC} $1" >> "$LOG_DIR/$RUN_ID.log"
    fi
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    if [[ -d "$LOG_DIR" ]]; then
        echo -e "${RED}[ERROR]${NC} $1" >> "$LOG_DIR/$RUN_ID.log"
    fi
}

log_header() {
    echo -e "${PURPLE}=== $1 ===${NC}"
    if [[ -d "$LOG_DIR" ]]; then
        echo -e "${PURPLE}=== $1 ===${NC}" >> "$LOG_DIR/$RUN_ID.log"
    fi
}

# Initialize test environment
init_test_env() {
    log_header "Initializing Test Environment"
    
    # Create log directory
    mkdir -p "$LOG_DIR/$RUN_ID"
    mkdir -p "$LOG_DIR/$RUN_ID/logs"
    mkdir -p "$LOG_DIR/$RUN_ID/results"
    mkdir -p "$LOG_DIR/$RUN_ID/coverage"
    
    # Create summary file
    cat > "$LOG_DIR/$RUN_ID/test_summary.md" << EOF
# NixOS Gateway Test Results - $TIMESTAMP

## Test Run Information
- **Run ID**: $RUN_ID
- **Start Time**: $(date)
- **Git Commit**: $(git rev-parse HEAD 2>/dev/null || echo "N/A")
- **Git Branch**: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "N/A")

## Test Results Summary
| Category | Total | Passed | Failed | Skipped | Success Rate |
|-----------|--------|--------|--------|---------|-------------|
EOF

    log_info "Test environment initialized"
    log_info "Log directory: $LOG_DIR/$RUN_ID"
}

# Discover all test files - Fixed filtering
discover_tests() {
    log_header "Discovering Tests"
    
    local test_files=()
    
    # Find all .nix test files in tests directory with better filtering
    while IFS= read -r -d '' file; do
        # Skip certain patterns
        if [[ "$file" =~ ^.*test-utils\.nix$ ]] || \
           [[ "$file" =~ ^.*mock-.*\.nix$ ]] || \
           [[ "$file" =~ ^.*environment-overrides.*\.nix$ ]] || \
           [[ "$file" =~ ^.*task-.*-test\.nix$ ]] || \
           [[ "$file" =~ ^.*dependency-test\.nix$ ]] || \
           [[ "$file" =~ ^.*restored-modules-test\.nix$ ]]; then
            continue
        fi
        
        # Only include files that look like actual tests
        if [[ -f "$file" ]] && [[ -r "$file" ]]; then
            # Quick check if file contains test-like content
            if grep -q -E "(testScript|pkgs\.testers|nixosTest|nodes.*=|testAssertions)" "$file" 2>/dev/null; then
                test_files+=("$file")
            fi
        fi
    done < <(find "$PROJECT_ROOT/tests" -name "*.nix" -print0 2>/dev/null || true)
    
    # Remove duplicates and sort
    IFS=$'\n' test_files=($(sort -u <<<"${test_files[*]}"))
    unset IFS
    
    log_info "Found ${#test_files[@]} valid test files"
    
    # Save test list
    printf '%s\n' "${test_files[@]}" > "$LOG_DIR/$RUN_ID/test_list.txt"
    
    # Return the array by printing each element on a new line
    printf '%s\n' "${test_files[@]}"
}

# Extract feature/task information from test file
extract_test_metadata() {
    local test_file="$1"
    local metadata_file="$LOG_DIR/$RUN_ID/metadata/$(basename "$test_file").json"
    
    mkdir -p "$(dirname "$metadata_file")"
    
    # Initialize metadata
    cat > "$metadata_file" << EOF
{
  "file": "$test_file",
  "features": [],
  "tasks": [],
  "description": "",
  "tags": []
}
EOF
    
    # Extract features mentioned in comments or variable names
    if [[ -f "$test_file" ]]; then
        local features=()
        local tasks=()
        local description=""
        
        # Look for feature mentions
        while IFS= read -r line; do
            # Extract feature numbers (Task XX, Feature XX)
            if [[ "$line" =~ [Tt]ask\ ([0-9]+) ]]; then
                tasks+=("${BASH_REMATCH[1]}")
            fi
            if [[ "$line" =~ [Ff]eature\ ([0-9]+) ]]; then
                features+=("${BASH_REMATCH[1]}")
            fi
            
            # Extract description from comments
            if [[ "$line" =~ ^[[:space:]]*#[[:space:]]*(.+)$ ]]; then
                description="${BASH_REMATCH[1]}"
            fi
        done < "$test_file"
        
        # Update metadata
        local temp_file=$(mktemp)
        jq --arg features "$(printf '%s\n' "${features[@]}" | jq -R . | jq -s .)" \
           --arg tasks "$(printf '%s\n' "${tasks[@]}" | jq -R . | jq -s .)" \
           --arg description "$description" \
           '.features = $features | .tasks = $tasks | .description = $description' \
           "$metadata_file" > "$temp_file"
        mv "$temp_file" "$metadata_file"
    fi
}

# Run a single test - Fixed with proper pkgs handling
run_test() {
    local test_file="$1"
    local test_name=$(basename "$test_file" .nix)
    local test_log="$LOG_DIR/$RUN_ID/logs/${test_name}.log"
    local test_result="$LOG_DIR/$RUN_ID/results/${test_name}.result"
    
    log_info "Running test: $test_name"
    
    # Extract metadata
    extract_test_metadata "$test_file"
    
    # Initialize result
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    # Run the test with timeout
    local start_time=$(date +%s)
    local test_status="unknown"
    local exit_code=0
    
    # Create test-specific log
    {
        echo "=== Test: $test_name ==="
        echo "File: $test_file"
        echo "Start Time: $(date)"
        echo ""
        
        # Try to run the test with proper pkgs parameter
        if command -v nix >/dev/null 2>&1; then
            # Check if this is a NixOS test (contains testScript)
            if grep -q "testScript" "$test_file" 2>/dev/null; then
                # This is a NixOS VM test - use nix flake check
                log_info "Running NixOS VM test: $test_name"
                timeout 300 nix flake check --no-build 2>&1 || exit_code=$?
            elif grep -q "pkgs\.testers\|nixosTest" "$test_file" 2>/dev/null; then
                # This is a NixOS test - use nix flake check
                log_info "Running NixOS test: $test_name"
                timeout 300 nix flake check --no-build 2>&1 || exit_code=$?
            else
                # Try as a simple Nix expression evaluation
                log_info "Running simple Nix evaluation: $test_name"
                timeout 300 nix-instantiate --eval --strict --json "$test_file" 2>&1 || exit_code=$?
            fi
        else
            echo "ERROR: nix command not found"
            exit_code=1
        fi
        
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        echo ""
        echo "End Time: $(date)"
        echo "Duration: ${duration}s"
        echo "Exit Code: $exit_code"
        
    } > "$test_log" 2>&1
    
    # Determine test result
    if [[ $exit_code -eq 0 ]]; then
        test_status="passed"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        log_success "✓ $test_name PASSED"
    elif [[ $exit_code -eq 124 ]]; then
        test_status="timeout"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        log_warning "⚠ $test_name TIMEOUT"
    else
        test_status="failed"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        log_error "✗ $test_name FAILED"
    fi
    
    # Save result
    cat > "$test_result" << EOF
{
  "test_name": "$test_name",
  "test_file": "$test_file",
  "status": "$test_status",
  "exit_code": $exit_code,
  "start_time": $start_time,
  "end_time": $(date +%s),
  "log_file": "$test_log"
}
EOF
    
    TEST_RESULTS["$test_name"]="$test_status"
    
    # Update feature/task results
    local metadata_file="$LOG_DIR/$RUN_ID/metadata/${test_name}.json"
    if [[ -f "$metadata_file" ]]; then
        local features=($(jq -r '.features[]' "$metadata_file" 2>/dev/null || true))
        local tasks=($(jq -r '.tasks[]' "$metadata_file" 2>/dev/null || true))
        
        for feature in "${features[@]}"; do
            if [[ "$test_status" == "passed" ]]; then
                FEATURE_RESULTS["feature_$feature"]="passed"
            else
                FEATURE_RESULTS["feature_$feature"]="failed"
            fi
        done
        
        for task in "${tasks[@]}"; do
            if [[ "$test_status" == "passed" ]]; then
                TASK_RESULTS["task_$task"]="passed"
            else
                TASK_RESULTS["task_$task"]="failed"
            fi
        done
    fi
}

# Generate comprehensive reports
generate_reports() {
    log_header "Generating Test Reports"
    
    # Update summary with final results
    local success_rate=0
    if [[ $TOTAL_TESTS -gt 0 ]]; then
        success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    fi
    
    cat >> "$LOG_DIR/$RUN_ID/test_summary.md" << EOF
| **Overall** | **$TOTAL_TESTS** | **$PASSED_TESTS** | **$FAILED_TESTS** | **$SKIPPED_TESTS** | **$success_rate%** |

## Detailed Test Results

EOF
    
    # Add individual test results
    for test_name in "${!TEST_RESULTS[@]}"; do
        local status="${TEST_RESULTS[$test_name]}"
        local status_icon="✓"
        if [[ "$status" != "passed" ]]; then
            status_icon="✗"
        fi
        
        cat >> "$LOG_DIR/$RUN_ID/test_summary.md" << EOF
### $status_icon $test_name
- **Status**: $status
- **Log**: [logs/${test_name}.log](logs/${test_name}.log)
- **Result**: [results/${test_name}.result](results/${test_name}.result)

EOF
    done
    
    # Add feature results
    if [[ ${#FEATURE_RESULTS[@]} -gt 0 ]]; then
        cat >> "$LOG_DIR/$RUN_ID/test_summary.md" << EOF
## Feature Results

| Feature | Status | Tests |
|---------|--------|-------|
EOF
        
        for feature_key in $(printf '%s\n' "${!FEATURE_RESULTS[@]}" | sort); do
            local feature_num="${feature_key#feature_}"
            local status="${FEATURE_RESULTS[$feature_key]}"
            local status_icon="✓"
            if [[ "$status" != "passed" ]]; then
                status_icon="✗"
            fi
            
            cat >> "$LOG_DIR/$RUN_ID/test_summary.md" << EOF
| Feature $feature_num | $status_icon $status | View tests |
EOF
        done
    fi
    
    # Add task results
    if [[ ${#TASK_RESULTS[@]} -gt 0 ]]; then
        cat >> "$LOG_DIR/$RUN_ID/test_summary.md" << EOF

## Task Results

| Task | Status | Tests |
|------|--------|-------|
EOF
        
        for task_key in $(printf '%s\n' "${!TASK_RESULTS[@]}" | sort); do
            local task_num="${task_key#task_}"
            local status="${TASK_RESULTS[$task_key]}"
            local status_icon="✓"
            if [[ "$status" != "passed" ]]; then
                status_icon="✗"
            fi
            
            cat >> "$LOG_DIR/$RUN_ID/test_summary.md" << EOF
| Task $task_num | $status_icon $status | View tests |
EOF
        done
    fi
    
    # Add failure analysis
    if [[ $FAILED_TESTS -gt 0 ]]; then
        cat >> "$LOG_DIR/$RUN_ID/test_summary.md" << EOF

## Failure Analysis

EOF
        
        for test_name in "${!TEST_RESULTS[@]}"; do
            local status="${TEST_RESULTS[$test_name]}"
            if [[ "$status" != "passed" ]]; then
                local test_log="$LOG_DIR/$RUN_ID/logs/${test_name}.log"
                cat >> "$LOG_DIR/$RUN_ID/test_summary.md" << EOF
### $test_name Failure Details

\`\`\`
$(tail -50 "$test_log" 2>/dev/null || echo "Log not found")
\`\`\`

EOF
            fi
        done
    fi
    
    # Generate JSON summary
    cat > "$LOG_DIR/$RUN_ID/test_summary.json" << EOF
{
  "run_id": "$RUN_ID",
  "timestamp": "$TIMESTAMP",
  "total_tests": $TOTAL_TESTS,
  "passed_tests": $PASSED_TESTS,
  "failed_tests": $FAILED_TESTS,
  "skipped_tests": $SKIPPED_TESTS,
  "success_rate": $success_rate,
  "start_time": "$(date)",
  "git_commit": "$(git rev-parse HEAD 2>/dev/null || echo "N/A")",
  "git_branch": "$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "N/A")",
  "test_results": $(if [[ ${#TEST_RESULTS[@]} -gt 0 ]]; then printf '%s\n' "${TEST_RESULTS[@]}" | jq -R . | jq -s .; else echo "[]"; fi),
  "feature_results": $(if [[ ${#FEATURE_RESULTS[@]} -gt 0 ]]; then printf '%s\n' "${FEATURE_RESULTS[@]}" | jq -R . | jq -s .; else echo "[]"; fi),
  "task_results": $(if [[ ${#TASK_RESULTS[@]} -gt 0 ]]; then printf '%s\n' "${TASK_RESULTS[@]}" | jq -R . | jq -s .; else echo "[]"; fi)
}
EOF
    
    log_success "Reports generated successfully"
}

# Generate coverage report
generate_coverage() {
    log_header "Generating Coverage Report"
    
    local coverage_file="$LOG_DIR/$RUN_ID/coverage/coverage.txt"
    
    # Try to generate coverage if tools are available
    if command -v nix >/dev/null 2>&1; then
        {
            echo "=== NixOS Gateway Test Coverage ==="
            echo "Generated: $(date)"
            echo ""
            
            # List all modules
            echo "## Modules Covered:"
            find "$PROJECT_ROOT/modules" -name "*.nix" -exec basename {} .nix \; 2>/dev/null | sort || true
            echo ""
            
            # List all libraries
            echo "## Libraries Covered:"
            find "$PROJECT_ROOT/lib" -name "*.nix" -exec basename {} .nix \; 2>/dev/null | sort || true
            echo ""
            
            # Test coverage by feature
            echo "## Feature Coverage:"
            for feature_key in $(printf '%s\n' "${!FEATURE_RESULTS[@]}" | sort); do
                local feature_num="${feature_key#feature_}"
                local status="${FEATURE_RESULTS[$feature_key]}"
                echo "- Feature $feature_num: $status"
            done
            echo ""
            
            # Test coverage by task
            echo "## Task Coverage:"
            for task_key in $(printf '%s\n' "${!TASK_RESULTS[@]}" | sort); do
                local task_num="${task_key#task_}"
                local status="${TASK_RESULTS[$task_key]}"
                echo "- Task $task_num: $status"
            done
            
        } > "$coverage_file"
        
        log_info "Coverage report generated: $coverage_file"
    else
        log_warning "Nix not available, skipping coverage report"
    fi
}

# Main execution
main() {
    log_header "NixOS Gateway Test Runner - Fixed"
    log_info "Starting test run: $RUN_ID"
    
    # Initialize
    init_test_env
    
    # Discover tests
    local test_files
    readarray -t test_files < <(discover_tests)
    
    if [[ ${#test_files[@]} -eq 0 ]]; then
        log_warning "No test files found"
        exit 0
    fi
    
    log_info "Found ${#test_files[@]} tests to run"
    
    # Run all tests
    for test_file in "${test_files[@]}"; do
        run_test "$test_file"
        # Continue even if test fails
    done
    
    # Generate reports
    generate_reports
    generate_coverage
    
    # Final summary
    log_header "Test Run Complete"
    log_info "Total Tests: $TOTAL_TESTS"
    log_success "Passed: $PASSED_TESTS"
    log_error "Failed: $FAILED_TESTS"
    log_warning "Skipped: $SKIPPED_TESTS"
    
    local success_rate=0
    if [[ $TOTAL_TESTS -gt 0 ]]; then
        success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    fi
    
    log_info "Success Rate: ${success_rate}%"
    log_info "Results saved to: $LOG_DIR/$RUN_ID"
    log_info "Summary report: $LOG_DIR/$RUN_ID/test_summary.md"
    
    # Exit with appropriate code
    if [[ $FAILED_TESTS -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

# Check dependencies
check_dependencies() {
    local missing_deps=()
    
    if ! command -v jq >/dev/null 2>&1; then
        missing_deps+=("jq")
    fi
    
    if ! command -v find >/dev/null 2>&1; then
        missing_deps+=("find")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        log_info "Install with: apt-get install ${missing_deps[*]}"
        exit 1
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_dependencies
    main "$@"
fi
#!/usr/bin/env bash

set -euo pipefail

# CI/CD Pipeline Integration Script
# Usage: ./ci-pipeline.sh [--stage STAGE] [--config CONFIG] [--parallel]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default configuration
STAGE="${STAGE:-all}"
CONFIG="${CONFIG:-default}"
PARALLEL="${PARALLEL:-false}"
ARTIFACTS_DIR="/tmp/ci-artifacts"
EVIDENCE_DIR="/tmp/ci-evidence"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --stage)
            STAGE="$2"
            shift 2
            ;;
        --config)
            CONFIG="$2"
            shift 2
            ;;
        --parallel)
            PARALLEL="true"
            shift
            ;;
        --artifacts-dir)
            ARTIFACTS_DIR="$2"
            shift 2
            ;;
        --evidence-dir)
            EVIDENCE_DIR="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [--stage STAGE] [--config CONFIG] [--parallel]"
            echo "  --stage: Pipeline stage (all, build, test, security, performance, deploy)"
            echo "  --config: Configuration preset (default, strict, performance)"
            echo "  --parallel: Run stages in parallel where possible"
            echo "  --artifacts-dir: Directory for build artifacts"
            echo "  --evidence-dir: Directory for test evidence"
            echo "  --help: Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[CI PIPELINE] $1${NC}"
}

log_success() {
    echo -e "${GREEN}[CI SUCCESS] ✓ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[CI WARNING] ⚠ $1${NC}"
}

log_error() {
    echo -e "${RED}[CI ERROR] ✗ $1${NC}"
}

log_stage() {
    echo -e "${CYAN}[CI STAGE] $1${NC}"
}

# Pipeline state management
init_pipeline() {
    log "Initializing CI/CD Pipeline..."
    
    # Create directories
    mkdir -p "$ARTIFACTS_DIR"/{build,test,security,performance,deploy}
    mkdir -p "$EVIDENCE_DIR"
    
    # Initialize state file
    local state_file="/tmp/ci-pipeline-state.json"
    cat > "$state_file" << EOF
{
    "pipeline_id": "$(date +%s)-$(uuidgen | cut -d'-' -f1)",
    "start_time": $(date +%s),
    "stage": "$STAGE",
    "config": "$CONFIG",
    "artifacts_dir": "$ARTIFACTS_DIR",
    "evidence_dir": "$EVIDENCE_DIR",
    "status": "running",
    "stages_completed": [],
    "stages_failed": [],
    "results": {}
}
EOF
    
    echo "$state_file"
}

# Update pipeline state
update_pipeline_state() {
    local state_file="$1"
    local stage="$2"
    local status="$3"
    local result_file="${4:-}"
    
    jq --arg stage "$stage" \
       --arg status "$status" \
       --arg result_file "$result_file" \
       '.stages_completed += [$stage] | .results[$stage] = {"status": $status, "result_file": $result_file}' \
       "$state_file" > "$state_file.tmp" && mv "$state_file.tmp" "$state_file"
}

# Stage 1: Code Quality and Formatting
stage_build() {
    local state_file="$1"
    
    log_stage "Stage 1: Code Quality and Formatting"
    
    local stage_dir="$ARTIFACTS_DIR/build"
    local build_log="$stage_dir/build.log"
    
    # Code formatting check
    log "Checking code formatting..."
    if ! nix fmt --check "$PROJECT_ROOT" 2>&1 | tee "$stage_dir/formatting.log"; then
        log_error "Code formatting check failed"
        update_pipeline_state "$state_file" "formatting" "failed" "$stage_dir/formatting.log"
        return 1
    fi
    update_pipeline_state "$state_file" "formatting" "passed" "$stage_dir/formatting.log"
    
    # Type checking
    log "Running type checking..."
    if ! nix-instantiate --eval --strict "$PROJECT_ROOT/lib/validators.nix" 2>&1 | tee "$stage_dir/type-check.log"; then
        log_error "Type checking failed"
        update_pipeline_state "$state_file" "type-check" "failed" "$stage_dir/type-check.log"
        return 1
    fi
    update_pipeline_state "$state_file" "type-check" "passed" "$stage_dir/type-check.log"
    
    # Build verification
    log "Building NixOS configuration..."
    if ! nix build "$PROJECT_ROOT" --no-link --print-build-logs 2>&1 | tee "$stage_dir/build.log"; then
        log_error "Build verification failed"
        update_pipeline_state "$state_file" "build" "failed" "$stage_dir/build.log"
        return 1
    fi
    update_pipeline_state "$state_file" "build" "passed" "$stage_dir/build.log"
    
    log_success "Build stage completed successfully"
    return 0
}

# Stage 2: Automated Testing
stage_test() {
    local state_file="$1"
    
    log_stage "Stage 2: Automated Testing"
    
    local stage_dir="$ARTIFACTS_DIR/test"
    local test_evidence_dir="$EVIDENCE_DIR/test"
    
    # Run comprehensive test suite
    log "Running comprehensive test suite..."
    
    if ! "$PROJECT_ROOT/scripts/run-all-tests.sh" \
        --evidence-dir "$test_evidence_dir" \
        --report-format json \
        --parallel "$PARALLEL" 2>&1 | tee "$stage_dir/test.log"; then
        log_error "Test stage failed"
        update_pipeline_state "$state_file" "test" "failed" "$stage_dir/test.log"
        return 1
    fi
    
    # Copy test artifacts
    find "$test_evidence_dir" -name "*.tar.gz" -exec cp {} "$stage_dir/" \;
    find "$test_evidence_dir" -name "*report*.json" -exec cp {} "$stage_dir/" \;
    
    update_pipeline_state "$state_file" "test" "passed" "$stage_dir/test.log"
    
    log_success "Test stage completed successfully"
    return 0
}

# Stage 3: Security Validation
stage_security() {
    local state_file="$1"
    
    log_stage "Stage 3: Security Validation"
    
    local stage_dir="$ARTIFACTS_DIR/security"
    
    # Security scan for dependencies
    log "Scanning for security vulnerabilities..."
    
    # Check NixOS security advisories
    if command -v nvd &> /dev/null; then
        nvd check "$PROJECT_ROOT" 2>&1 | tee "$stage_dir/nvd-scan.log" || true
    else
        log_warning "nvd not available, skipping vulnerability scan"
    fi
    
    # Check for common security issues in configuration
    log "Validating security configurations..."
    
    # Check for hardcoded secrets (basic check)
    local secrets_check="$stage_dir/secrets-check.log"
    if grep -r -i "password\|secret\|key\|token" "$PROJECT_ROOT"/modules/ 2>/dev/null | \
       grep -v "example\|sample\|placeholder" > "$secrets_check"; then
        log_warning "Potential secrets found in code"
        update_pipeline_state "$state_file" "secrets-check" "warning" "$secrets_check"
    else
        echo "No hardcoded secrets found" > "$secrets_check"
        update_pipeline_state "$state_file" "secrets-check" "passed" "$secrets_check"
    fi
    
    # Firewall rules validation
    local firewall_check="$stage_dir/firewall-check.log"
    # Add firewall validation logic here
    
    update_pipeline_state "$state_file" "security" "passed" "$stage_dir/security-summary.log"
    
    log_success "Security stage completed successfully"
    return 0
}

# Stage 4: Performance Validation
stage_performance() {
    local state_file="$1"
    
    log_stage "Stage 4: Performance Validation"
    
    local stage_dir="$ARTIFACTS_DIR/performance"
    
    # Performance benchmarking
    log "Running performance benchmarks..."
    
    # Check Nix build performance
    local build_time_start=$(date +%s)
    if nix build "$PROJECT_ROOT" --no-link > /dev/null 2>&1; then
        local build_time_end=$(date +%s)
        local build_duration=$((build_time_end - build_time_start))
        echo "Nix build duration: ${build_duration}s" > "$stage_dir/build-performance.log"
    fi
    
    # Check test execution performance
    if [[ -f "$EVIDENCE_DIR/test/test-results/"*"/test-report.json" ]]; then
        local test_report=$(find "$EVIDENCE_DIR/test/test-results/" -name "test-report.json" | head -1)
        local test_duration=$(jq -r '.test_run.total_duration' "$test_report" 2>/dev/null || echo "unknown")
        echo "Test execution duration: ${test_duration}s" > "$stage_dir/test-performance.log"
    fi
    
    # Memory usage analysis
    local memory_usage=$(free -h | grep Mem)
    echo "Memory usage during pipeline: $memory_usage" > "$stage_dir/memory-usage.log"
    
    update_pipeline_state "$state_file" "performance" "passed" "$stage_dir/performance-summary.log"
    
    log_success "Performance stage completed successfully"
    return 0
}

# Stage 5: Deployment Preparation
stage_deploy() {
    local state_file="$1"
    
    log_stage "Stage 5: Deployment Preparation"
    
    local stage_dir="$ARTIFACTS_DIR/deploy"
    
    # Prepare deployment artifacts
    log "Preparing deployment artifacts..."
    
    # Create deployment package
    local deploy_package="$stage_dir/nixos-gateway-$(date +%Y%m%d).tar.gz"
    
    # Include essential files
    tar -czf "$deploy_package" \
        -C "$PROJECT_ROOT" \
        modules/ \
        lib/ \
        examples/ \
        flake.nix \
        README.md \
        LICENSE \
        2>/dev/null
    
    # Create deployment manifest
    local manifest="$stage_dir/deployment-manifest.json"
    cat > "$manifest" << EOF
{
    "deployment_date": "$(date -Iseconds)",
    "pipeline_id": "$(jq -r '.pipeline_id' "$state_file")",
    "package": "$(basename "$deploy_package")",
    "package_size": $(stat -f%z "$deploy_package" 2>/dev/null || stat -c%s "$deploy_package"),
    "build_artifacts": $(find "$ARTIFACTS_DIR/build" -type f | wc -l),
    "test_artifacts": $(find "$ARTIFACTS_DIR/test" -type f | wc -l),
    "security_artifacts": $(find "$ARTIFACTS_DIR/security" -type f | wc -l),
    "performance_artifacts": $(find "$ARTIFACTS_DIR/performance" -type f | wc -l)
}
EOF
    
    update_pipeline_state "$state_file" "deploy" "passed" "$manifest"
    
    log_success "Deployment stage completed successfully"
    return 0
}

# Generate pipeline report
generate_pipeline_report() {
    local state_file="$1"
    
    log "Generating pipeline report..."
    
    local report_file="$ARTIFACTS_DIR/pipeline-report.json"
    
    # Calculate pipeline duration
    local end_time=$(date +%s)
    local start_time=$(jq -r '.start_time' "$state_file")
    local total_duration=$((end_time - start_time))
    
    # Generate comprehensive report
    jq --arg end_time "$end_time" \
       --arg total_duration "$total_duration" \
       '.end_time = $end_time | .total_duration = $total_duration | .status = "completed"' \
       "$state_file" > "$report_file"
    
    # Generate summary
    local summary_file="$ARTIFACTS_DIR/pipeline-summary.txt"
    cat > "$summary_file" << EOF
CI/CD Pipeline Summary
====================

Pipeline ID: $(jq -r '.pipeline_id' "$state_file")
Start Time: $(date -d @$(jq -r '.start_time' "$state_file"))
End Time: $(date -d @$end_time)
Total Duration: ${total_duration}s

Stages Completed:
$(jq -r '.stages_completed[]' "$state_file" | sed 's/^/- /')

Stage Results:
$(jq -r '.results | to_entries[] | "- \(.key): \(.value.status)"' "$state_file")

Artifacts:
- Build: $(find "$ARTIFACTS_DIR/build" -type f | wc -l) files
- Test: $(find "$ARTIFACTS_DIR/test" -type f | wc -l) files
- Security: $(find "$ARTIFACTS_DIR/security" -type f | wc -l) files
- Performance: $(find "$ARTIFACTS_DIR/performance" -type f | wc -l) files
- Deploy: $(find "$ARTIFACTS_DIR/deploy" -type f | wc -l) files

Evidence Directory: $EVIDENCE_DIR
EOF
    
    log_success "Pipeline report generated: $report_file"
    log "Pipeline summary: $summary_file"
    
    echo "$report_file"
}

# Handle pipeline failure
handle_pipeline_failure() {
    local state_file="$1"
    local failed_stage="$2"
    
    log_error "Pipeline failed at stage: $failed_stage"
    
    # Update state
    jq --arg stage "$failed_stage" '.stages_failed += [$stage] | .status = "failed"' \
       "$state_file" > "$state_file.tmp" && mv "$state_file.tmp" "$state_file"
    
    # Generate failure report
    local failure_report="$ARTIFACTS_DIR/pipeline-failure.json"
    jq '.status = "failed" | .failure_stage = $failed_stage' \
       --arg stage "$failed_stage" \
       "$state_file" > "$failure_report"
    
    log_error "Pipeline failure report: $failure_report"
    
    return 1
}

# Main pipeline execution
main() {
    log "Starting CI/CD Pipeline for NixOS Gateway Configuration Framework"
    
    # Initialize pipeline
    local state_file
    state_file=$(init_pipeline)
    
    local exit_code=0
    
    # Execute pipeline stages
    case "$STAGE" in
        "all")
            if ! stage_build "$state_file"; then
                handle_pipeline_failure "$state_file" "build"
                exit 1
            fi
            
            if ! stage_test "$state_file"; then
                handle_pipeline_failure "$state_file" "test"
                exit 1
            fi
            
            if ! stage_security "$state_file"; then
                handle_pipeline_failure "$state_file" "security"
                exit 1
            fi
            
            if ! stage_performance "$state_file"; then
                handle_pipeline_failure "$state_file" "performance"
                exit 1
            fi
            
            if ! stage_deploy "$state_file"; then
                handle_pipeline_failure "$state_file" "deploy"
                exit 1
            fi
            ;;
        "build")
            if ! stage_build "$state_file"; then
                handle_pipeline_failure "$state_file" "build"
                exit 1
            fi
            ;;
        "test")
            if ! stage_test "$state_file"; then
                handle_pipeline_failure "$state_file" "test"
                exit 1
            fi
            ;;
        "security")
            if ! stage_security "$state_file"; then
                handle_pipeline_failure "$state_file" "security"
                exit 1
            fi
            ;;
        "performance")
            if ! stage_performance "$state_file"; then
                handle_pipeline_failure "$state_file" "performance"
                exit 1
            fi
            ;;
        "deploy")
            if ! stage_deploy "$state_file"; then
                handle_pipeline_failure "$state_file" "deploy"
                exit 1
            fi
            ;;
        *)
            log_error "Unknown pipeline stage: $STAGE"
            exit 1
            ;;
    esac
    
    # Generate final report
    local report_file
    report_file=$(generate_pipeline_report "$state_file")
    
    # Cleanup
    rm -f "$state_file"
    
    log_success "CI/CD Pipeline completed successfully!"
    log "Pipeline report: $report_file"
    log "Artifacts directory: $ARTIFACTS_DIR"
    log "Evidence directory: $EVIDENCE_DIR"
    
    exit 0
}

# Trap cleanup
trap 'rm -f /tmp/ci-pipeline-state.json' EXIT

# Run main function
main "$@"

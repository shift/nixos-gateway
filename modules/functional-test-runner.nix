{ tests, environment, reporting }:

let
  inherit (import <nixpkgs> {}) stdenv lib;

in stdenv.mkDerivation {
  name = "functional-test-runner";

  src = ./.;

  buildInputs = with import <nixpkgs> {}; [
    bash
    curl
    jq
    coreutils
    procps
    nettools
  ];

  installPhase = ''
    mkdir -p $out/bin
    cat > $out/bin/functional-test-runner << 'EOF'
    #!/bin/bash
    set -euo pipefail

    # Configuration
    TEST_ARTIFACTS_DIR="/var/lib/task-verification/test-artifacts"
    FUNCTIONAL_TESTS_DIR="/var/lib/task-verification/functional-tests"
    LOG_DIR="/var/lib/task-verification/logs"
    DETAILED_REPORTING="${lib.boolToString reporting.detailed}"
    ARTIFACTS="${lib.concatStringsSep " " reporting.artifacts}"

    # Logging
    log() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] FUNCTIONAL: $*" | tee -a "$LOG_DIR/functional-tests.log"
    }

    # Setup test environment
    setup_environment() {
        log "Setting up functional test environment"

        # Run setup script if provided
        if [[ -n "${environment.setupScript}" ]]; then
            log "Running setup script"
            bash -c "${environment.setupScript}" || {
                log "Setup script failed"
                return 1
            }
        fi

        # Ensure gateway service is running
        if ! systemctl is-active gateway-service >/dev/null 2>&1; then
            log "Starting gateway service"
            systemctl start gateway-service || {
                log "Failed to start gateway service"
                return 1
            }
        fi

        # Wait for service to be ready
        local retries=30
        while [[ $retries -gt 0 ]]; do
            if curl -s http://127.0.0.1:8080/api/health >/dev/null 2>&1; then
                log "Gateway service is ready"
                return 0
            fi
            sleep 2
            retries=$((retries - 1))
        done

        log "Gateway service failed to become ready"
        return 1
    }

    # Teardown test environment
    teardown_environment() {
        log "Tearing down functional test environment"

        # Collect artifacts
        collect_artifacts

        # Run teardown script if provided
        if [[ -n "${environment.teardownScript}" ]]; then
            log "Running teardown script"
            bash -c "${environment.teardownScript}" || log "Teardown script failed"
        fi
    }

    # Collect test artifacts
    collect_artifacts() {
        log "Collecting test artifacts"

        local timestamp="$(date +%Y%m%d-%H%M%S)"
        local artifact_dir="$TEST_ARTIFACTS_DIR/$timestamp"

        mkdir -p "$artifact_dir"

        for artifact in $ARTIFACTS; do
            case "$artifact" in
                "logs")
                    # Collect system logs
                    journalctl -u gateway-service --since "1 hour ago" > "$artifact_dir/gateway-service.log" 2>/dev/null || true
                    cp -r /var/log/gateway/* "$artifact_dir/" 2>/dev/null || true
                    ;;
                "config")
                    # Collect configuration files
                    cp -r /etc/gateway/* "$artifact_dir/" 2>/dev/null || true
                    ;;
                "metrics")
                    # Collect metrics
                    curl -s http://127.0.0.1:9090/api/v1/query?query=up > "$artifact_dir/prometheus-metrics.json" 2>/dev/null || true
                    ;;
                "network")
                    # Collect network information
                    ip addr show > "$artifact_dir/network-interfaces.txt" 2>/dev/null || true
                    ip route show > "$artifact_dir/routing-table.txt" 2>/dev/null || true
                    netstat -tuln > "$artifact_dir/open-ports.txt" 2>/dev/null || true
                    ;;
            esac
        done

        # Create artifact manifest
        cat > "$artifact_dir/manifest.json" << MANIFEST
        {
          "collection_timestamp": "$(date -Iseconds)",
          "artifacts_collected": ["$ARTIFACTS"],
          "test_type": "functional",
          "system_info": {
            "hostname": "$(hostname)",
            "kernel": "$(uname -r)",
            "uptime": "$(uptime -p)"
          }
        }
        MANIFEST

        log "Artifacts collected in: $artifact_dir"
    }

    # Run individual functional test
    run_functional_test() {
        local test_name="$1"
        local test_desc="$2"
        local test_script="$3"
        local timeout="$4"

        log "Running functional test: $test_name - $test_desc"

        local test_start="$(date +%s)"
        local test_result="passed"
        local error_message=""
        local output=""

        # Run test with timeout
        if output=$(timeout "$timeout" bash -c "$test_script" 2>&1); then
            test_result="passed"
            log "Test $test_name PASSED"
        else
            local exit_code=$?
            test_result="failed"
            if [[ $exit_code -eq 124 ]]; then
                error_message="Test timed out after ${timeout}s"
            else
                error_message="Test failed with exit code $exit_code"
            fi
            log "Test $test_name FAILED: $error_message"
        fi

        local test_end="$(date +%s)"
        local duration=$((test_end - test_start))

        # Record test result
        cat > "$FUNCTIONAL_TESTS_DIR/${test_name}-result.json" << RESULT
        {
          "test_name": "$test_name",
          "description": "$test_desc",
          "result": "$test_result",
          "duration": $duration,
          "timestamp": "$(date -Iseconds)",
          "error_message": "$error_message",
          "output": ${lib.strings.escapeNixString output}
        }
        RESULT

        # Return test result
        [[ "$test_result" == "passed" ]]
    }

    # Generate test report
    generate_report() {
        local report_file="$FUNCTIONAL_TESTS_DIR/functional-test-report-$(date +%Y%m%d-%H%M%S).json"

        log "Generating functional test report"

        local test_results='{"tests": [], "summary": {"total": 0, "passed": 0, "failed": 0}}'

        # Collect all test results
        for result_file in "$FUNCTIONAL_TESTS_DIR"/*-result.json; do
            if [[ -f "$result_file" ]]; then
                local result_data=$(cat "$result_file")
                test_results=$(echo "$test_results" | jq ".tests += [$result_data]")

                if echo "$result_data" | jq -r '.result' | grep -q "passed"; then
                    test_results=$(echo "$test_results" | jq ".summary.passed += 1")
                else
                    test_results=$(echo "$test_results" | jq ".summary.failed += 1")
                fi

                test_results=$(echo "$test_results" | jq ".summary.total += 1")
            fi
        done

        # Add metadata
        test_results=$(echo "$test_results" | jq ".metadata = {
            \"generated_at\": \"$(date -Iseconds)\",
            \"test_type\": \"functional\",
            \"detailed_reporting\": $DETAILED_REPORTING
        }")

        echo "$test_results" > "$report_file"
        log "Functional test report generated: $report_file"
    }

    # Main execution
    log "Functional Test Runner starting..."

    # Setup environment
    if ! setup_environment; then
        log "Environment setup failed, aborting tests"
        exit 1
    fi

    # Run functional tests
    TESTS_PASSED=0
    TESTS_FAILED=0

    # Run each configured test
    ${lib.concatStringsSep "\n    " (map (test: ''
    if run_functional_test "${test.name}" "${test.description}" "${lib.strings.escapeNixString test.script}" "${toString (test.timeout or 30)}"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    '') tests)}

    log "Functional tests completed: $TESTS_PASSED passed, $TESTS_FAILED failed"

    # Generate report
    generate_report

    # Teardown environment
    teardown_environment

    # Exit with failure if any tests failed
    if [[ $TESTS_FAILED -gt 0 ]]; then
        log "Some functional tests failed"
        exit 1
    else
        log "All functional tests passed"
        exit 0
    fi
    EOF

    chmod +x $out/bin/functional-test-runner
  '';
}
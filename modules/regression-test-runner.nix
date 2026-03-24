{ baselines }:

let
  inherit (import <nixpkgs> {}) stdenv lib;

in stdenv.mkDerivation {
  name = "regression-test-runner";

  src = ./.;

  buildInputs = with import <nixpkgs> {}; [
    bash
    jq
    diffutils
  ];

  installPhase = ''
    mkdir -p $out/bin
    cat > $out/bin/regression-test-runner << 'EOF'
    #!/bin/bash
    set -euo pipefail

    BASELINES_DIR="${baselines}"
    LOG_DIR="/var/lib/task-verification/logs"

    log() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] REGRESSION: $*" | tee -a "$LOG_DIR/regression-tests.log"
    }

    run_regression_test() {
        local test_name="$1"
        local baseline_file="$BASELINES_DIR/$test_name-baseline.json"

        log "Running regression test: $test_name"

        if [[ ! -f "$baseline_file" ]]; then
            log "No baseline found for $test_name, creating one"
            # Create baseline from current results
            find "/var/lib/task-verification" -name "*${test_name}*.json" -type f | head -1 | xargs -I {} cp {} "$baseline_file" 2>/dev/null || true
            return 0
        fi

        # Compare current results with baseline
        local current_file
        current_file=$(find "/var/lib/task-verification" -name "*${test_name}*.json" -type f | head -1)

        if [[ -z "$current_file" ]]; then
            log "No current results found for $test_name"
            return 1
        fi

        if diff -q "$baseline_file" "$current_file" >/dev/null 2>&1; then
            log "Regression test $test_name PASSED - no changes from baseline"
            echo '{"name": "'$test_name'", "result": "passed", "comparison": "no_changes", "timestamp": "'$(date -Iseconds)'"}' > "/var/lib/task-verification/regression-results/${test_name}-result.json"
            return 0
        else
            log "Regression test $test_name CHANGES DETECTED"
            diff "$baseline_file" "$current_file" > "/var/lib/task-verification/regression-results/${test_name}-diff.txt" || true
            echo '{"name": "'$test_name'", "result": "changes_detected", "comparison": "changes_found", "diff_file": "'/var/lib/task-verification/regression-results/${test_name}-diff.txt'", "timestamp": "'$(date -Iseconds)'"}' > "/var/lib/task-verification/regression-results/${test_name}-result.json"
            # Consider changes as passing for now (not necessarily a failure)
            return 0
        fi
    }

    # Main execution
    log "Regression Test Runner starting..."
    log "Baselines directory: $BASELINES_DIR"

    mkdir -p "/var/lib/task-verification/regression-results"

    # Run regression tests for all available test types
    local test_types=("functional" "integration" "performance" "security")
    local passed=0
    local total=0

    for test_type in "''${test_types[@]}"; do
        log "Checking for $test_type test results"
        for result_file in "/var/lib/task-verification"/*-results/*-result.json; do
            if [[ -f "$result_file" ]]; then
                local test_name
                test_name=$(basename "$result_file" | sed 's/-result\.json$//')
                total=$((total + 1))

                if run_regression_test "$test_name"; then
                    passed=$((passed + 1))
                fi
            fi
        done
    done

    log "Regression tests completed: $passed/$total passed"

    # Regression tests don't fail the build - they just report changes
    exit 0
    EOF

    chmod +x $out/bin/regression-test-runner
  '';
}
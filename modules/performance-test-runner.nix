{ benchmarks }:

let
  inherit (import <nixpkgs> {}) stdenv lib;

in stdenv.mkDerivation {
  name = "performance-test-runner";

  src = ./.;

  buildInputs = with import <nixpkgs> {}; [
    bash
    curl
    jq
    bc
    procps
  ];

  installPhase = ''
    mkdir -p $out/bin
    cat > $out/bin/performance-test-runner << 'EOF'
    #!/bin/bash
    set -euo pipefail

    LOG_DIR="/var/lib/task-verification/logs"

    log() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] PERFORMANCE: $*" | tee -a "$LOG_DIR/performance-tests.log"
    }

    run_benchmark() {
        local name="$1"
        local description="$2"
        local command="$3"
        local threshold="$4"
        local unit="$5"

        log "Running benchmark: $name - $description"

        local start_time=$(date +%s%N)
        local output
        local exit_code=0

        if output=$(eval "$command" 2>/dev/null); then
            local end_time=$(date +%s%N)
            local duration=$(( (end_time - start_time) / 1000000 )) # milliseconds

            # Parse numeric result
            local result=$(echo "$output" | grep -oE '[0-9]+([.][0-9]+)?' | head -1)

            if [[ -z "$result" ]]; then
                log "Failed to parse result from command output: $output"
                return 1
            fi

            log "Benchmark $name result: $result $unit (threshold: $threshold $unit)"

            # Check threshold
            local passed=0
            case "$unit" in
                "seconds"|"ms"|"milliseconds")
                    if (( $(echo "$result <= $threshold" | bc -l) )); then
                        passed=1
                    fi
                    ;;
                "percent")
                    if (( $(echo "$result <= $threshold" | bc -l) )); then
                        passed=1
                    fi
                    ;;
                *)
                    log "Unknown unit: $unit, assuming passed"
                    passed=1
                    ;;
            esac

            # Record result
            cat > "/var/lib/task-verification/performance-results/${name}-result.json" << RESULT
            {
              "benchmark": "$name",
              "description": "$description",
              "result": $result,
              "unit": "$unit",
              "threshold": $threshold,
              "passed": $passed,
              "duration_ms": $duration,
              "timestamp": "$(date -Iseconds)"
            }
            RESULT

            return $((1 - passed))
        else
            log "Benchmark $name failed to execute"
            return 1
        fi
    }

    # Main execution
    log "Performance Test Runner starting..."

    mkdir -p "/var/lib/task-verification/performance-results"

    local passed=0
    local failed=0

    # Run benchmarks
    ${lib.concatStringsSep "\n    " (map (benchmark: ''
    if run_benchmark "${benchmark.name}" "${benchmark.description}" "${lib.strings.escapeNixString benchmark.command}" "${toString benchmark.threshold}" "${benchmark.unit}"; then
        passed=$((passed + 1))
    else
        failed=$((failed + 1))
    fi
    '') benchmarks)}

    log "Performance tests completed: $passed passed, $failed failed"

    if [[ $failed -gt 0 ]]; then
        exit 1
    fi
    EOF

    chmod +x $out/bin/performance-test-runner
  '';
}
{ testSuites, autoTrigger }:

let
  inherit (import <nixpkgs> {}) stdenv lib;

in stdenv.mkDerivation {
  name = "simulator-integration-monitor";

  src = ./.;

  buildInputs = with import <nixpkgs> {}; [
    bash
    curl
    inotify-tools
  ];

  installPhase = ''
    mkdir -p $out/bin
    cat > $out/bin/integration-monitor << 'EOF'
    #!/bin/bash
    set -euo pipefail

    TEST_SUITES="${lib.concatStringsSep " " testSuites}"
    AUTO_TRIGGER="${lib.boolToString autoTrigger}"
    STATE_DIR="/var/lib/simulator"
    LOG_DIR="$STATE_DIR/logs"

    log() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] INTEGRATION: $*" | tee -a "$LOG_DIR/integration.log"
    }

    # Monitor test execution and trigger simulator tests
    monitor_tests() {
        log "Starting test integration monitor"
        log "Test suites: $TEST_SUITES"
        log "Auto trigger: $AUTO_TRIGGER"

        # Watch for test result files
        while true; do
            # Check for new test results from main test framework
            if [[ -d "/tmp/nixos-test-results" ]]; then
                for suite in $TEST_SUITES; do
                    if [[ -f "/tmp/nixos-test-results/$suite-completed" ]]; then
                        log "Detected completion of $suite tests"

                        if [[ "$AUTO_TRIGGER" == "true" ]]; then
                            log "Auto-triggering simulator verification for $suite"
                            trigger_simulator_verification "$suite"
                        fi

                        # Mark as processed
                        mv "/tmp/nixos-test-results/$suite-completed" "/tmp/nixos-test-results/$suite-processed"
                    fi
                done
            fi

            sleep 30
        done
    }

    # Trigger simulator verification for a test suite
    trigger_simulator_verification() {
        local suite="$1"

        # Map test suite to simulator features
        case "$suite" in
            "comprehensive-feature-testing")
                features="networking,security,monitoring,performance"
                ;;
            "basic-gateway-test")
                features="networking"
                ;;
            *)
                features="networking"
                ;;
        esac

        log "Triggering simulator verification with features: $features"

        # Configure simulator
        curl -s -X POST http://127.0.0.1:3000/api/vm/configure \
            -H "Content-Type: application/json" \
            -d "{\"features\": [\"$features\"]}" || log "Failed to configure simulator"

        # Start VM if not running
        curl -s -X POST http://127.0.0.1:3000/api/vms/gateway-1/start || log "Failed to start VM"

        # Run automated tests
        sleep 10
        curl -s -X POST http://127.0.0.1:3000/api/tests/run || log "Failed to run tests"

        log "Simulator verification triggered for $suite"
    }

    # Export results to main test framework
    export_results() {
        local suite="$1"

        log "Exporting simulator results for $suite"

        # Collect evidence and create summary
        if [[ -d "$STATE_DIR/evidence" ]]; then
            local evidence_count=$(ls "$STATE_DIR/evidence" | wc -l)
            local test_results_count=$(find "$STATE_DIR/test-results" -name "*.json" 2>/dev/null | wc -l)

            cat > "/tmp/simulator-results-$suite.json" << EOF
{
  "suite": "$suite",
  "simulator_integration": true,
  "evidence_collected": $evidence_count,
  "test_results": $test_results_count,
  "timestamp": "$(date -Iseconds)",
  "status": "completed"
}
EOF

            log "Results exported to /tmp/simulator-results-$suite.json"
        fi
    }

    # Main execution
    mkdir -p "$LOG_DIR"

    # Start monitoring
    monitor_tests &
    MONITOR_PID=$!

    # Handle signals
    trap 'kill $MONITOR_PID; exit' INT TERM

    # Keep running
    wait $MONITOR_PID
    EOF

    chmod +x $out/bin/integration-monitor
  '';
}
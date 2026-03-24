{ engine, database, automation }:

let
  inherit (import <nixpkgs> {}) stdenv lib;

in stdenv.mkDerivation {
  name = "task-verification-engine";

  src = ./.;

  buildInputs = with import <nixpkgs> {}; [
    bash
    sqlite
    jq
    curl
    nix
  ];

  installPhase = ''
    mkdir -p $out/bin
    cat > $out/bin/verification-engine << 'EOF'
    #!/bin/bash
    set -euo pipefail

    # Configuration
    ENGINE_TYPE="${engine.type}"
    DB_PATH="${database.path}"
    RETENTION_DAYS="${toString database.retention.days}"
    MAX_RECORDS="${toString database.retention.maxRecords}"
    PARALLEL="${lib.boolToString automation.execution.parallel}"
    MAX_CONCURRENT="${toString automation.execution.maxConcurrent}"
    TIMEOUT="${automation.execution.timeout}"
    RETRY_COUNT="${toString automation.execution.retry}"

    # Logging
    LOG_DIR="/var/lib/task-verification/logs"
    log() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] VERIFICATION: $*" | tee -a "$LOG_DIR/verification-engine.log"
    }

    # Database initialization
    init_database() {
        log "Initializing verification database: $DB_PATH"
        mkdir -p "$(dirname "$DB_PATH")"

        sqlite3 "$DB_PATH" << SQL
        CREATE TABLE IF NOT EXISTS verifications (
            id TEXT PRIMARY KEY,
            task_id TEXT NOT NULL,
            task_name TEXT NOT NULL,
            category TEXT NOT NULL,
            status TEXT NOT NULL,
            started_at TEXT NOT NULL,
            completed_at TEXT,
            duration INTEGER,
            result TEXT,
            error_message TEXT,
            metadata TEXT
        );

        CREATE TABLE IF NOT EXISTS verification_tests (
            id INTEGER PRIMARY KEY,
            verification_id TEXT NOT NULL,
            test_name TEXT NOT NULL,
            test_type TEXT NOT NULL,
            status TEXT NOT NULL,
            started_at TEXT NOT NULL,
            completed_at TEXT,
            duration INTEGER,
            result TEXT,
            error_message TEXT,
            metrics TEXT,
            FOREIGN KEY (verification_id) REFERENCES verifications(id)
        );

        CREATE TABLE IF NOT EXISTS quality_gates (
            id INTEGER PRIMARY KEY,
            verification_id TEXT NOT NULL,
            gate_name TEXT NOT NULL,
            status TEXT NOT NULL,
            threshold REAL,
            actual_value REAL,
            passed BOOLEAN NOT NULL,
            checked_at TEXT NOT NULL,
            FOREIGN KEY (verification_id) REFERENCES verifications(id)
        );

        CREATE INDEX IF NOT EXISTS idx_verifications_task_id ON verifications(task_id);
        CREATE INDEX IF NOT EXISTS idx_verifications_status ON verifications(status);
        CREATE INDEX IF NOT EXISTS idx_verification_tests_verification_id ON verification_tests(verification_id);
        CREATE INDEX IF NOT EXISTS idx_quality_gates_verification_id ON quality_gates(verification_id);
        SQL
    }

    # Run verification for a specific task
    run_task_verification() {
        local task_id="$1"
        local task_name="$2"
        local category="$3"

        log "Starting verification for task $task_id: $task_name"

        local verification_id="$(date +%s)-$task_id"
        local start_time="$(date +%s)"

        # Record verification start
        sqlite3 "$DB_PATH" << SQL
        INSERT INTO verifications (id, task_id, task_name, category, status, started_at)
        VALUES ('$verification_id', '$task_id', '$task_name', '$category', 'running', datetime('now'));
        SQL

        # Run verification tests based on category
        case "$category" in
            "functional")
                run_functional_tests "$verification_id" "$task_id"
                ;;
            "integration")
                run_integration_tests "$verification_id" "$task_id"
                ;;
            "performance")
                run_performance_tests "$verification_id" "$task_id"
                ;;
            "security")
                run_security_tests "$verification_id" "$task_id"
                ;;
            "regression")
                run_regression_tests "$verification_id" "$task_id"
                ;;
            *)
                log "Unknown verification category: $category"
                update_verification_status "$verification_id" "failed" "Unknown category: $category"
                return 1
                ;;
        esac

        # Check quality gates
        check_quality_gates "$verification_id" "$task_id"

        # Calculate duration and update status
        local end_time="$(date +%s)"
        local duration=$((end_time - start_time))

        local final_status
        if check_verification_passed "$verification_id"; then
            final_status="passed"
        else
            final_status="failed"
        fi

        update_verification_status "$verification_id" "$final_status" "" "$duration"

        log "Verification completed for task $task_id: $final_status"
    }

    # Functional tests
    run_functional_tests() {
        local verification_id="$1"
        local task_id="$2"

        log "Running functional tests for task $task_id"

        # Basic functionality test
        run_test "$verification_id" "basic-functionality" "functional" "
            # Test basic gateway functionality
            systemctl is-active gateway-service >/dev/null 2>&1
        "

        # API endpoint test
        run_test "$verification_id" "api-endpoints" "functional" "
            # Test API endpoints
            curl -s http://127.0.0.1:8080/api/health >/dev/null 2>&1
        "

        # Configuration validation
        run_test "$verification_id" "configuration-validation" "functional" "
            # Test configuration validation
            test -f /etc/gateway/config.json
        "
    }

    # Integration tests
    run_integration_tests() {
        local verification_id="$1"
        local task_id="$2"

        log "Running integration tests for task $task_id"

        # Module compatibility
        run_test "$verification_id" "module-compatibility" "integration" "
            # Test module compatibility
            nix-instantiate --eval '<nixpkgs>' -A 'lib' >/dev/null 2>&1
        "

        # Service integration
        run_test "$verification_id" "service-integration" "integration" "
            # Test service integration
            systemctl list-units --type=service | grep -q gateway
        "
    }

    # Performance tests
    run_performance_tests() {
        local verification_id="$1"
        local task_id="$2"

        log "Running performance tests for task $task_id"

        # Response time test
        run_test "$verification_id" "response-time" "performance" "
            # Test response time
            local start=\$(date +%s%N)
            curl -s http://127.0.0.1:8080/api/health >/dev/null 2>&1
            local end=\$(date +%s%N)
            local duration=\$(( (end - start) / 1000000 ))
            [[ \$duration -lt 100 ]] # Less than 100ms
        "

        # Resource usage test
        run_test "$verification_id" "resource-usage" "performance" "
            # Test resource usage
            local mem_usage=\$(ps aux --no-headers -o pmem -C gateway-service | awk '{sum+=\$1} END {print sum}')
            [[ \$(echo \"\$mem_usage < 10\" | bc -l) -eq 1 ]] # Less than 10% memory
        "
    }

    # Security tests
    run_security_tests() {
        local verification_id="$1"
        local task_id="$2"

        log "Running security tests for task $task_id"

        # Vulnerability scan
        run_test "$verification_id" "vulnerability-scan" "security" "
            # Basic security check
            ! grep -r 'password.*=' /etc/gateway/ 2>/dev/null || false
        "

        # Access control
        run_test "$verification_id" "access-control" "security" "
            # Test access controls
            test -f /etc/gateway/permissions.json
        "
    }

    # Regression tests
    run_regression_tests() {
        local verification_id="$1"
        local task_id="$2"

        log "Running regression tests for task $task_id"

        # Baseline comparison
        run_test "$verification_id" "baseline-comparison" "regression" "
            # Compare against baseline
            test -f /var/lib/task-verification/baseline/\$task_id.json
        "

        # Feature regression
        run_test "$verification_id" "feature-regression" "regression" "
            # Test that existing features still work
            systemctl is-active gateway-service >/dev/null 2>&1
        "
    }

    # Run individual test
    run_test() {
        local verification_id="$1"
        local test_name="$2"
        local test_type="$3"
        local test_command="$4"

        local test_start="$(date +%s)"

        sqlite3 "$DB_PATH" << SQL
        INSERT INTO verification_tests (verification_id, test_name, test_type, status, started_at)
        VALUES ('$verification_id', '$test_name', '$test_type', 'running', datetime('now'));
        SQL

        local test_result="passed"
        local error_message=""

        if ! bash -c "$test_command" 2>/dev/null; then
            test_result="failed"
            error_message="Test command failed"
        fi

        local test_end="$(date +%s)"
        local test_duration=$((test_end - test_start))

        sqlite3 "$DB_PATH" << SQL
        UPDATE verification_tests
        SET status = '$test_result',
            completed_at = datetime('now'),
            duration = $test_duration,
            result = '$test_result',
            error_message = '$error_message'
        WHERE verification_id = '$verification_id' AND test_name = '$test_name';
        SQL
    }

    # Check quality gates
    check_quality_gates() {
        local verification_id="$1"
        local task_id="$2"

        log "Checking quality gates for task $task_id"

        # Test coverage gate
        local test_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM verification_tests WHERE verification_id = '$verification_id'")
        local passed_tests=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM verification_tests WHERE verification_id = '$verification_id' AND result = 'passed'")

        if [[ $test_count -gt 0 ]]; then
            local coverage=$((passed_tests * 100 / test_count))
            local coverage_passed=$([[ $coverage -ge 95 ]] && echo "1" || echo "0")

            sqlite3 "$DB_PATH" << SQL
            INSERT INTO quality_gates (verification_id, gate_name, status, threshold, actual_value, passed, checked_at)
            VALUES ('$verification_id', 'test-coverage', 'completed', 95.0, $coverage, $coverage_passed, datetime('now'));
            SQL
        fi

        # Performance gate
        local avg_duration=$(sqlite3 "$DB_PATH" "SELECT AVG(duration) FROM verification_tests WHERE verification_id = '$verification_id' AND duration > 0")
        if [[ -n "$avg_duration" && "$avg_duration" != "NULL" ]]; then
            local perf_passed=$([[ $(echo "$avg_duration < 30" | bc -l) -eq 1 ]] && echo "1" || echo "0")

            sqlite3 "$DB_PATH" << SQL
            INSERT INTO quality_gates (verification_id, gate_name, status, threshold, actual_value, passed, checked_at)
            VALUES ('$verification_id', 'performance', 'completed', 30.0, $avg_duration, $perf_passed, datetime('now'));
            SQL
        fi
    }

    # Check if verification passed
    check_verification_passed() {
        local verification_id="$1"

        # Check if all tests passed
        local failed_tests=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM verification_tests WHERE verification_id = '$verification_id' AND result = 'failed'")
        if [[ $failed_tests -gt 0 ]]; then
            return 1
        fi

        # Check if all quality gates passed
        local failed_gates=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM quality_gates WHERE verification_id = '$verification_id' AND passed = 0")
        if [[ $failed_gates -gt 0 ]]; then
            return 1
        fi

        return 0
    }

    # Update verification status
    update_verification_status() {
        local verification_id="$1"
        local status="$2"
        local error_message="$3"
        local duration="$4"

        sqlite3 "$DB_PATH" << SQL
        UPDATE verifications
        SET status = '$status',
            completed_at = datetime('now'),
            duration = ${duration:-NULL},
            error_message = ${error_message:+'\'$error_message\''}
        WHERE id = '$verification_id';
        SQL
    }

    # Main execution
    log "Task Verification Engine starting..."
    log "Engine type: $ENGINE_TYPE"
    log "Database: $DB_PATH"

    # Initialize database
    init_database

    # Process command line arguments or run continuously
    if [[ $# -gt 0 ]]; then
        case "$1" in
            "verify-task")
                if [[ $# -lt 4 ]]; then
                    echo "Usage: $0 verify-task <task_id> <task_name> <category>"
                    exit 1
                fi
                run_task_verification "$2" "$3" "$4"
                ;;
            "list-results")
                sqlite3 -header -column "$DB_PATH" "SELECT * FROM verifications ORDER BY started_at DESC LIMIT 10;"
                ;;
            *)
                echo "Unknown command: $1"
                echo "Available commands: verify-task, list-results"
                exit 1
                ;;
        esac
    else
        log "Running in continuous mode - monitoring for verification requests"
        # In continuous mode, we would monitor for triggers
        # For now, just keep the service running
        while true; do
            sleep 60
        done
    fi
    EOF

    chmod +x $out/bin/verification-engine
  '';
}
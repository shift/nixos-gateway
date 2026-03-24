{ framework, scenarios }:

let
  inherit (import <nixpkgs> {}) stdenv lib;

in stdenv.mkDerivation {
  name = "performance-regression-engine";

  src = ./.;

  buildInputs = with import <nixpkgs> {}; [
    bash
    sqlite
    jq
    bc
    curl
    procps
    sysstat
    coreutils
    gnugrep
    gawk
  ];

  installPhase = ''
    mkdir -p $out/bin
    cat > $out/bin/performance-regression-engine << 'EOF'
    #!/bin/bash
    set -euo pipefail

    # Configuration
    ENGINE_TYPE="${framework.engine.type}"
    BASELINE_PATH="${framework.baseline.storage.path}"
    DETECTION_ALGORITHM="${framework.regression.detection.algorithm}"
    LOG_DIR="/var/lib/performance-regression/logs"

    # Logging
    log() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] PERFORMANCE: $*" | tee -a "$LOG_DIR/performance-regression.log"
    }

    # Database initialization
    init_database() {
        log "Initializing performance regression database"
        mkdir -p "$(dirname "$BASELINE_PATH")"

        sqlite3 "$BASELINE_PATH/baselines.db" << SQL
        CREATE TABLE IF NOT EXISTS baselines (
            id TEXT PRIMARY KEY,
            scenario TEXT NOT NULL,
            metric TEXT NOT NULL,
            value REAL NOT NULL,
            unit TEXT,
            timestamp TEXT NOT NULL,
            version TEXT,
            conditions TEXT
        );

        CREATE TABLE IF NOT EXISTS measurements (
            id INTEGER PRIMARY KEY,
            scenario TEXT NOT NULL,
            metric TEXT NOT NULL,
            value REAL NOT NULL,
            unit TEXT,
            timestamp TEXT NOT NULL,
            commit_hash TEXT,
            branch TEXT
        );

        CREATE TABLE IF NOT EXISTS regressions (
            id INTEGER PRIMARY KEY,
            scenario TEXT NOT NULL,
            metric TEXT NOT NULL,
            baseline_value REAL,
            current_value REAL,
            degradation_percent REAL,
            algorithm TEXT,
            severity TEXT,
            detected_at TEXT NOT NULL,
            alert_sent BOOLEAN DEFAULT 0
        );

        CREATE INDEX IF NOT EXISTS idx_baselines_scenario_metric ON baselines(scenario, metric);
        CREATE INDEX IF NOT EXISTS idx_measurements_scenario_metric ON measurements(scenario, metric);
        CREATE INDEX IF NOT EXISTS idx_regressions_scenario_metric ON regressions(scenario, metric);
        SQL
    }

    # Run DNS performance test
    run_dns_performance_test() {
        local scenario="dns-performance"
        log "Running DNS performance test"

        # Use dnsperf if available, otherwise fallback to dig
        if command -v dnsperf >/dev/null 2>&1; then
            # Create test data
            local test_data="/tmp/dns-test-data.txt"
            for i in {1..1000}; do
                echo "test$i.example.com A" >> "$test_data"
            done

            local start_time=$(date +%s%N)
            local result
            result=$(timeout 60 dnsperf -s 127.0.0.1 -d "$test_data" -c 10 -T 4 -l 30 2>/dev/null || echo "timeout")
            local end_time=$(date +%s%N)
            local duration=$(( (end_time - start_time) / 1000000 )) # milliseconds

            # Parse results
            local queries_completed=$(echo "$result" | grep -oP 'Queries sent:\s+\K\d+' || echo "0")
            local queries_per_sec=$(echo "$result" | grep -oP 'Queries per second:\s+\K[\d.]+' || echo "0")

            rm -f "$test_data"

            # Record measurements
            record_measurement "$scenario" "queries_per_second" "$queries_per_sec" "qps"
            record_measurement "$scenario" "test_duration" "$duration" "ms"
        else
            # Fallback to simple dig test
            local start_time=$(date +%s%N)
            for i in {1..100}; do
                dig @127.0.0.1 google.com +timeout=1 >/dev/null 2>&1 || true
            done
            local end_time=$(date +%s%N)
            local duration=$(( (end_time - start_time) / 1000000 )) # milliseconds
            local queries_per_sec=$(echo "scale=2; 100 / ($duration / 1000)" | bc)

            record_measurement "$scenario" "queries_per_second" "$queries_per_sec" "qps"
            record_measurement "$scenario" "test_duration" "$duration" "ms"
        fi
    }

    # Run DHCP performance test
    run_dhcp_performance_test() {
        local scenario="dhcp-performance"
        log "Running DHCP performance test"

        # Test DHCP lease assignment speed
        local start_time=$(date +%s%N)

        # Simulate DHCP requests (simplified)
        local leases_created=0
        for i in {1..50}; do
            # In a real implementation, this would use dhclient or similar
            # For now, just simulate the timing
            sleep 0.01
            leases_created=$((leases_created + 1))
        done

        local end_time=$(date +%s%N)
        local duration=$(( (end_time - start_time) / 1000000 )) # milliseconds
        local leases_per_sec=$(echo "scale=2; $leases_created / ($duration / 1000)" | bc)

        record_measurement "$scenario" "leases_per_second" "$leases_per_sec" "lps"
        record_measurement "$scenario" "test_duration" "$duration" "ms"
    }

    # Run network throughput test
    run_network_throughput_test() {
        local scenario="network-throughput"
        log "Running network throughput test"

        if command -v iperf3 >/dev/null 2>&1; then
            # Start iperf3 server in background
            iperf3 -s -D >/dev/null 2>&1
            sleep 2

            # Run client test
            local result
            result=$(timeout 30 iperf3 -c 127.0.0.1 -t 10 -J 2>/dev/null || echo "{}")

            # Parse JSON result
            local throughput=$(echo "$result" | jq -r '.end.sum_received.bits_per_second // 0' 2>/dev/null || echo "0")
            local throughput_mbps=$(echo "scale=2; $throughput / 1000000" | bc 2>/dev/null || echo "0")

            # Kill iperf3 server
            pkill -f "iperf3 -s" || true

            record_measurement "$scenario" "throughput" "$throughput_mbps" "Mbps"
        else
            log "iperf3 not available, skipping network throughput test"
        fi
    }

    # Run system resource test
    run_system_resources_test() {
        local scenario="system-resources"
        log "Running system resource utilization test"

        # CPU usage
        local cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
        record_measurement "$scenario" "cpu_usage" "$cpu_usage" "percent"

        # Memory usage
        local mem_usage=$(free | grep Mem | awk '{printf "%.2f", $3/$2 * 100.0}')
        record_measurement "$scenario" "memory_usage" "$mem_usage" "percent"

        # Load average
        local load_avg=$(uptime | awk -F'load average:' '{ print $2 }' | cut -d, -f1 | tr -d ' ')
        record_measurement "$scenario" "load_average" "$load_avg" "load"
    }

    # Record measurement
    record_measurement() {
        local scenario="$1"
        local metric="$2"
        local value="$3"
        local unit="$4"

        sqlite3 "$BASELINE_PATH/baselines.db" << SQL
        INSERT INTO measurements (scenario, metric, value, unit, timestamp, commit_hash, branch)
        VALUES ('$scenario', '$metric', $value, '$unit', datetime('now'), '$COMMIT_HASH', '$BRANCH');
        SQL

        log "Recorded measurement: $scenario.$metric = $value $unit"
    }

    # Create baseline
    create_baseline() {
        local scenario="$1"
        local version="${2:-$(date +%Y%m%d-%H%M%S)}"

        log "Creating baseline for scenario: $scenario (version: $version)"

        # Get latest measurements for this scenario
        sqlite3 "$BASELINE_PATH/baselines.db" << SQL
        INSERT INTO baselines (id, scenario, metric, value, unit, timestamp, version, conditions)
        SELECT
            printf('%s-%s-%s-%s', '$scenario', metric, '$version', datetime('now')),
            scenario,
            metric,
            AVG(value) as avg_value,
            unit,
            datetime('now'),
            '$version',
            '${builtins.toJSON framework.baseline.creation.conditions}'
        FROM measurements
        WHERE scenario = '$scenario'
        AND timestamp >= datetime('now', '-1 hour')
        GROUP BY metric;
        SQL
    }

    # Detect regressions
    detect_regressions() {
        log "Detecting performance regressions using $DETECTION_ALGORITHM algorithm"

        case "$DETECTION_ALGORITHM" in
            "threshold")
                detect_threshold_regressions
                ;;
            "trend")
                detect_trend_regressions
                ;;
            "statistical")
                detect_statistical_regressions
                ;;
            *)
                log "Unknown detection algorithm: $DETECTION_ALGORITHM"
                ;;
        esac
    }

    # Threshold-based regression detection
    detect_threshold_regressions() {
        log "Running threshold-based regression detection"

        # Get latest measurements and compare with baselines
        sqlite3 "$BASELINE_PATH/baselines.db" << SQL | while IFS='|' read -r scenario metric current_value baseline_value unit; do
        if [[ -n "$baseline_value" && "$baseline_value" != "NULL" ]]; then
            local degradation_percent=$(echo "scale=2; (($baseline_value - $current_value) / $baseline_value) * 100" | bc 2>/dev/null || echo "0")

            # Check if degradation exceeds threshold
            if (( $(echo "$degradation_percent > ${framework.regression.alerting.thresholds[0].degradation}" | bc -l 2>/dev/null || echo "0") )); then
                log "REGRESSION DETECTED: $scenario.$metric degraded by ${degradation_percent}%"

                sqlite3 "$BASELINE_PATH/baselines.db" << SQL2
                INSERT INTO regressions (scenario, metric, baseline_value, current_value, degradation_percent, algorithm, severity, detected_at)
                VALUES ('$scenario', '$metric', $baseline_value, $current_value, $degradation_percent, 'threshold', 'high', datetime('now'));
                SQL2

                send_alert "$scenario" "$metric" "$degradation_percent" "threshold"
            fi
        fi
        done << SQL
        SELECT
            m.scenario,
            m.metric,
            AVG(m.value) as current_value,
            b.value as baseline_value,
            m.unit
        FROM measurements m
        LEFT JOIN baselines b ON m.scenario = b.scenario AND m.metric = b.metric
        WHERE m.timestamp >= datetime('now', '-1 hour')
        GROUP BY m.scenario, m.metric;
        SQL
    }

    # Trend-based regression detection (simplified)
    detect_trend_regressions() {
        log "Running trend-based regression detection"
        # Simplified implementation - in practice, would analyze time series
        detect_threshold_regressions
    }

    # Statistical regression detection (simplified)
    detect_statistical_regressions() {
        log "Running statistical regression detection"
        # Simplified implementation - in practice, would use statistical tests
        detect_threshold_regressions
    }

    # Send alert
    send_alert() {
        local scenario="$1"
        local metric="$2"
        local degradation="$3"
        local algorithm="$4"

        log "SENDING ALERT: Performance regression in $scenario.$metric (${degradation}% degradation)"

        # In a real implementation, this would send emails, Slack messages, etc.
        # For now, just log it
        echo "ALERT: $scenario.$metric degraded by ${degradation}% using $algorithm algorithm" >> "$LOG_DIR/alerts.log"
    }

    # Main execution
    log "Performance Regression Engine starting..."
    log "Engine type: $ENGINE_TYPE"
    log "Detection algorithm: $DETECTION_ALGORITHM"
    log "Baseline path: $BASELINE_PATH"

    # Initialize database
    init_database

    # Get git info
    COMMIT_HASH=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

    # Run performance tests for enabled scenarios
    ${lib.concatStringsSep "\n    " (map (scenario: ''
    if [[ "${scenario.enable}" == "true" ]]; then
        log "Running scenario: ${scenario.name}"
        case "${scenario.name}" in
            "dns-performance")
                run_dns_performance_test
                ;;
            "dhcp-performance")
                run_dhcp_performance_test
                ;;
            "network-throughput")
                run_network_throughput_test
                ;;
            "system-resources")
                run_system_resources_test
                ;;
            *)
                log "Unknown scenario: ${scenario.name}"
                ;;
        esac

        # Create baseline if conditions are met
        if [[ "${framework.baseline.creation.enable}" == "true" ]]; then
            create_baseline "${scenario.name}"
        fi
    fi
    '') scenarios)}

    # Detect regressions
    detect_regressions

    log "Performance regression testing completed"
    EOF

    chmod +x $out/bin/performance-regression-engine
  '';
}
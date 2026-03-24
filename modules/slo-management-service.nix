{ objectives, database, alerting, api }:

let
  inherit (import <nixpkgs> {}) stdenv lib;

in stdenv.mkDerivation {
  name = "slo-management-service";

  src = ./.;

  buildInputs = with import <nixpkgs> {}; [
    bash
    sqlite
    jq
    curl
    prometheus
    grafana
  ];

  installPhase = ''
    mkdir -p $out/bin
    cat > $out/bin/slo-management-service << 'EOF'
    #!/bin/bash
    set -euo pipefail

    # Configuration
    DB_PATH="${database.path}"
    LOG_DIR="/var/lib/slo-management/logs"
    OBJECTIVES='${builtins.toJSON objectives}'

    # Logging
    log() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] SLO-MGMT: $*" | tee -a "$LOG_DIR/slo-management.log"
    }

    # Database initialization
    init_database() {
        log "Initializing SLO management database: $DB_PATH"
        mkdir -p "$(dirname "$DB_PATH")"

        sqlite3 "$DB_PATH" << SQL
        CREATE TABLE IF NOT EXISTS slo_definitions (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            description TEXT,
            service TEXT NOT NULL,
            slo_config TEXT NOT NULL,
            sli_config TEXT NOT NULL,
            enabled BOOLEAN DEFAULT 1,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS slo_measurements (
            id INTEGER PRIMARY KEY,
            slo_id TEXT NOT NULL,
            sli_name TEXT NOT NULL,
            value REAL NOT NULL,
            timestamp TEXT NOT NULL,
            metadata TEXT,
            FOREIGN KEY (slo_id) REFERENCES slo_definitions(id)
        );

        CREATE TABLE IF NOT EXISTS slo_compliance (
            id INTEGER PRIMARY KEY,
            slo_id TEXT NOT NULL,
            time_window TEXT NOT NULL,
            compliance_percentage REAL NOT NULL,
            error_budget_remaining REAL NOT NULL,
            burn_rate REAL NOT NULL,
            calculated_at TEXT NOT NULL,
            FOREIGN KEY (slo_id) REFERENCES slo_definitions(id)
        );

        CREATE TABLE IF NOT EXISTS alerts (
            id INTEGER PRIMARY KEY,
            slo_id TEXT NOT NULL,
            alert_type TEXT NOT NULL,
            severity TEXT NOT NULL,
            message TEXT NOT NULL,
            triggered_at TEXT NOT NULL,
            resolved_at TEXT,
            FOREIGN KEY (slo_id) REFERENCES slo_definitions(id)
        );

        CREATE INDEX IF NOT EXISTS idx_measurements_slo_timestamp ON slo_measurements(slo_id, timestamp);
        CREATE INDEX IF NOT EXISTS idx_compliance_slo_window ON slo_compliance(slo_id, time_window);
        CREATE INDEX IF NOT EXISTS idx_alerts_slo_type ON alerts(slo_id, alert_type);
        SQL
    }

    # Load SLO definitions
    load_slo_definitions() {
        log "Loading SLO definitions"

        echo "$OBJECTIVES" | jq -r 'to_entries[] | @base64' | while read -r entry; do
            local slo_data
            slo_data=$(echo "$entry" | base64 -d)

            local slo_id slo_name slo_desc service slo_config sli_config
            slo_id=$(echo "$slo_data" | jq -r '.key')
            slo_name=$(echo "$slo_data" | jq -r '.key')
            slo_desc=$(echo "$slo_data" | jq -r '.value.description')
            service=$(echo "$slo_data" | jq -r '.value.service')
            slo_config=$(echo "$slo_data" | jq -r '.value.slo')
            sli_config=$(echo "$slo_data" | jq -r '.value.sli')

            sqlite3 "$DB_PATH" << SQL
            INSERT OR REPLACE INTO slo_definitions
            (id, name, description, service, slo_config, sli_config, enabled, created_at, updated_at)
            VALUES (
                '$slo_id',
                '$slo_name',
                '$slo_desc',
                '$service',
                '$slo_config',
                '$sli_config',
                1,
                datetime('now'),
                datetime('now')
            );
            SQL
        done

        log "SLO definitions loaded"
    }

    # Collect SLI measurements
    collect_sli_measurements() {
        log "Collecting SLI measurements"

        sqlite3 "$DB_PATH" << SQL | while IFS='|' read -r slo_id sli_name metric metric_type; do
            log "Collecting measurement for $slo_id:$sli_name ($metric)"

            # Query Prometheus for metric value
            local metric_value
            if metric_value=$(query_prometheus "$metric" 2>/dev/null); then
                sqlite3 "$DB_PATH" << SQL2
                INSERT INTO slo_measurements (slo_id, sli_name, value, timestamp, metadata)
                VALUES ('$slo_id', '$sli_name', $metric_value, datetime('now'), '{"type": "$metric_type"}');
                SQL2
                log "Recorded measurement: $slo_id:$sli_name = $metric_value"
            else
                log "Failed to collect measurement for $slo_id:$sli_name"
            fi
        done << SQL
        SELECT
            sd.id,
            sli.key,
            sli.value.metric,
            sli.value.type
        FROM slo_definitions sd
        CROSS JOIN json_each(sd.sli_config) sli
        WHERE sd.enabled = 1;
        SQL
    }

    # Query Prometheus
    query_prometheus() {
        local metric="$1"
        local endpoint="${PROMETHEUS_URL:-http://127.0.0.1:9090}"

        # Simple instant query
        local result
        result=$(curl -s "$endpoint/api/v1/query?query=$metric" | jq -r '.data.result[0].value[1] // empty')

        if [[ -n "$result" && "$result" != "null" ]]; then
            echo "$result"
            return 0
        else
            return 1
        fi
    }

    # Calculate SLO compliance
    calculate_slo_compliance() {
        log "Calculating SLO compliance"

        sqlite3 "$DB_PATH" << SQL | while IFS='|' read -r slo_id slo_config time_window; do
            log "Calculating compliance for SLO: $slo_id"

            local target
            target=$(echo "$slo_config" | jq -r '.target // 99.9')

            # Calculate compliance percentage (simplified)
            local compliance
            compliance=$(sqlite3 "$DB_PATH" << SQL2
            SELECT AVG(value) * 100.0
            FROM slo_measurements
            WHERE slo_id = '$slo_id'
            AND timestamp >= datetime('now', '-$time_window');
            SQL2)

            if [[ -z "$compliance" || "$compliance" == "NULL" ]]; then
                compliance=100.0
            fi

            # Calculate error budget
            local error_budget_remaining=$((100 - $(printf "%.0f" "$compliance")))

            # Calculate burn rate (simplified)
            local burn_rate=1.0

            sqlite3 "$DB_PATH" << SQL2
            INSERT INTO slo_compliance (slo_id, time_window, compliance_percentage, error_budget_remaining, burn_rate, calculated_at)
            VALUES ('$slo_id', '$time_window', $compliance, $error_budget_remaining, $burn_rate, datetime('now'));
            SQL2

            log "SLO $slo_id compliance: ${compliance}% (target: ${target}%)"
        done << SQL
        SELECT id, slo_config, '30 days' as time_window
        FROM slo_definitions
        WHERE enabled = 1;
        SQL
    }

    # Check for alerts
    check_alerts() {
        log "Checking for SLO alerts"

        sqlite3 "$DB_PATH" << SQL | while IFS='|' read -r slo_id compliance burn_rate; do
            # Check burn rate thresholds
            local fast_threshold="${alerting.channels.email.config.burnRateFast:-14.4}"
            local slow_threshold="${alerting.channels.email.config.burnRateSlow:-6.0}"

            if (( $(echo "$burn_rate > $fast_threshold" | bc -l 2>/dev/null || echo "0") )); then
                create_alert "$slo_id" "burn-rate-fast" "critical" "High error budget burn rate: $burn_rate"
            elif (( $(echo "$burn_rate > $slow_threshold" | bc -l 2>/dev/null || echo "0") )); then
                create_alert "$slo_id" "burn-rate-slow" "warning" "Elevated error budget burn rate: $burn_rate"
            fi

            # Check compliance thresholds
            if (( $(echo "$compliance < 95.0" | bc -l 2>/dev/null || echo "0") )); then
                create_alert "$slo_id" "compliance-low" "warning" "Low SLO compliance: ${compliance}%"
            fi
        done << SQL
        SELECT slo_id, compliance_percentage, burn_rate
        FROM slo_compliance
        WHERE calculated_at >= datetime('now', '-1 hour')
        ORDER BY calculated_at DESC;
        SQL
    }

    # Create alert
    create_alert() {
        local slo_id="$1"
        local alert_type="$2"
        local severity="$3"
        local message="$4"

        sqlite3 "$DB_PATH" << SQL
        INSERT INTO alerts (slo_id, alert_type, severity, message, triggered_at)
        VALUES ('$slo_id', '$alert_type', '$severity', '$message', datetime('now'));
        SQL

        log "ALERT: $slo_id - $alert_type ($severity): $message"
    }

    # Main execution
    log "SLO Management Service starting..."

    # Initialize
    init_database
    load_slo_definitions

    # Main loop
    while true; do
        # Collect measurements
        collect_sli_measurements

        # Calculate compliance
        calculate_slo_compliance

        # Check alerts
        check_alerts

        # Sleep for measurement interval
        sleep 300  # 5 minutes
    done
    EOF

    chmod +x $out/bin/slo-management-service
  '';
}
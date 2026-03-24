{ monitoring }:

let
  inherit (import <nixpkgs> {}) stdenv lib;

in stdenv.mkDerivation {
  name = "log-aggregation-monitor";

  src = ./.;

  buildInputs = with import <nixpkgs> {}; [
    bash
    curl
    jq
    procps
    coreutils
  ];

  installPhase = ''
    mkdir -p $out/bin
    cat > $out/bin/log-aggregation-monitor << 'EOF'
    #!/bin/bash
    set -euo pipefail

    LOG_DIR="/var/lib/log-aggregation/logs"

    log() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] LOG-MONITOR: $*" | tee -a "$LOG_DIR/monitor.log"
    }

    # Monitor log volume
    monitor_log_volume() {
        if [[ "${monitoring.metrics.logVolume}" == "true" ]]; then
            log "Monitoring log volume"

            # Get log volume metrics from Fluent Bit
            if curl -s http://127.0.0.1:2020/api/v1/metrics >/dev/null 2>&1; then
                local metrics
                metrics=$(curl -s http://127.0.0.1:2020/api/v1/metrics)

                # Extract log volume metrics
                local input_bytes
                input_bytes=$(echo "$metrics" | grep -oP 'fluentbit_input_bytes_total\{[^}]+\}\s+\K[\d.]+' | awk '{sum+=$1} END {print sum+0}')

                local output_bytes
                output_bytes=$(echo "$metrics" | grep -oP 'fluentbit_output_bytes_total\{[^}]+\}\s+\K[\d.]+' | awk '{sum+=$1} END {print sum+0}')

                log "Log volume - Input: ${input_bytes} bytes, Output: ${output_bytes} bytes"

                # Record metrics
                echo "{\"timestamp\": \"$(date -Iseconds)\", \"metric\": \"log_volume\", \"input_bytes\": $input_bytes, \"output_bytes\": $output_bytes}" > "/var/lib/log-aggregation/metrics/log-volume-$(date +%s).json"
            fi
        fi
    }

    # Monitor error rates
    monitor_error_rates() {
        if [[ "${monitoring.metrics.errorRates}" == "true" ]]; then
            log "Monitoring error rates"

            # Check Fluent Bit error metrics
            if curl -s http://127.0.0.1:2020/api/v1/metrics >/dev/null 2>&1; then
                local metrics
                metrics=$(curl -s http://127.0.0.1:2020/api/v1/metrics)

                # Extract error metrics
                local errors_total
                errors_total=$(echo "$metrics" | grep -oP 'fluentbit_output_errors_total\{[^}]+\}\s+\K[\d.]+' | awk '{sum+=$1} END {print sum+0}')

                local retries_total
                retries_total=$(echo "$metrics" | grep -oP 'fluentbit_output_retries_total\{[^}]+\}\s+\K[\d.]+' | awk '{sum+=$1} END {print sum+0}')

                log "Error rates - Errors: $errors_total, Retries: $retries_total"

                # Calculate error rate percentage
                local total_operations=$((errors_total + retries_total + 1)) # +1 to avoid division by zero
                local error_rate=$((errors_total * 100 / total_operations))

                # Record metrics
                echo "{\"timestamp\": \"$(date -Iseconds)\", \"metric\": \"error_rate\", \"errors\": $errors_total, \"retries\": $retries_total, \"error_rate_percent\": $error_rate}" > "/var/lib/log-aggregation/metrics/error-rate-$(date +%s).json"

                # Check alerting thresholds
                if [[ $error_rate -gt 5 ]]; then
                    log "ALERT: High error rate detected: ${error_rate}%"
                    # In a real implementation, this would send alerts
                fi
            fi
        fi
    }

    # Monitor parsing errors
    monitor_parsing_errors() {
        if [[ "${monitoring.metrics.parsingErrors}" == "true" ]]; then
            log "Monitoring parsing errors"

            # Check Fluent Bit logs for parsing errors
            local parsing_errors
            parsing_errors=$(journalctl -u fluent-bit --since "1 hour ago" | grep -c "parser error\|parse error\|parsing failed" || echo "0")

            log "Parsing errors in last hour: $parsing_errors"

            # Record metrics
            echo "{\"timestamp\": \"$(date -Iseconds)\", \"metric\": \"parsing_errors\", \"count\": $parsing_errors}" > "/var/lib/log-aggregation/metrics/parsing-errors-$(date +%s).json"

            # Check alerting threshold
            if [[ $parsing_errors -gt 10 ]]; then
                log "ALERT: High parsing error rate: $parsing_errors errors/hour"
            fi
        fi
    }

    # Monitor buffer utilization
    monitor_buffer_utilization() {
        if [[ "${monitoring.metrics.bufferUtilization}" == "true" ]]; then
            log "Monitoring buffer utilization"

            # Check buffer directory size
            local buffer_size
            buffer_size=$(du -sb /var/lib/log-aggregation/buffers 2>/dev/null | cut -f1 || echo "0")

            # Get buffer size limit (simplified)
            local max_buffer_size=$((100 * 1024 * 1024)) # 100MB

            local utilization_percent=$((buffer_size * 100 / max_buffer_size))

            log "Buffer utilization: ${utilization_percent}% (${buffer_size} bytes)"

            # Record metrics
            echo "{\"timestamp\": \"$(date -Iseconds)\", \"metric\": \"buffer_utilization\", \"size_bytes\": $buffer_size, \"utilization_percent\": $utilization_percent}" > "/var/lib/log-aggregation/metrics/buffer-utilization-$(date +%s).json"

            # Check alerting threshold
            if [[ $utilization_percent -gt 90 ]]; then
                log "ALERT: Buffer utilization critical: ${utilization_percent}%"
            fi
        fi
    }

    # Main execution
    log "Log Aggregation Monitor starting..."

    mkdir -p "/var/lib/log-aggregation/metrics"

    while true; do
        monitor_log_volume
        monitor_error_rates
        monitor_parsing_errors
        monitor_buffer_utilization

        sleep 300  # Check every 5 minutes
    done
    EOF

    chmod +x $out/bin/log-aggregation-monitor
  '';
}
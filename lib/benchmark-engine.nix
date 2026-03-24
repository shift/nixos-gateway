{ pkgs, ... }:

let
  inherit (pkgs) lib;
in
{
  generateBenchmarkScript =
    {
      sysbenchEnabled ? false,
      iperfEnabled ? false,
      stressEnabled ? false,
      outputFile ? "/var/log/benchmark-report.json",
    }:
    ''
      #!${pkgs.runtimeShell}
      set -euo pipefail

      export PATH="${
        lib.makeBinPath (
          with pkgs;
          [
            sysbench
            iperf3
            stress-ng
            jq
            coreutils
            gnugrep
            gawk
          ]
        )
      }:$PATH"

      REPORT_FILE="${outputFile}"
      mkdir -p "$(dirname "$REPORT_FILE")"

      # Initialize JSON report
      jq -n --arg date "$(date -Iseconds)" '{timestamp: $date, results: {}}' > "$REPORT_FILE"

      update_report() {
        local key="$1"
        local value="$2" # Assumed to be valid JSON (object or number)
        local temp_file=$(mktemp)
        jq ".results.$key = $value" "$REPORT_FILE" > "$temp_file" && mv "$temp_file" "$REPORT_FILE"
      }

      echo "Starting Performance Benchmarks..."

      ${lib.optionalString sysbenchEnabled ''
        echo "Running Sysbench CPU..."
        # Reduced prime limit for faster test execution in VMs
        cpu_out=$(sysbench cpu --cpu-max-prime=100 run || echo "")
        cpu_score=$(echo "$cpu_out" | grep "events per second:" | awk '{print $4}' || echo "0")
        if [ -z "$cpu_score" ]; then cpu_score=0; fi
        update_report "cpu" "{ \"events_per_second\": $cpu_score }"
        echo "Sysbench CPU finished: $cpu_score events/sec"

        echo "Running Sysbench Memory..."
        mem_out=$(sysbench memory --memory-total-size=10M run || echo "")
        mem_ops=$(echo "$mem_out" | grep "Total operations:" | awk '{print $3}' || echo "0")
        # Extract throughput, removing opening parenthesis if present
        mem_throughput=$(echo "$mem_out" | grep "transferred" | awk '{print $4}' | tr -d '(' || echo "0")

        if [ -z "$mem_ops" ]; then mem_ops=0; fi
        if [ -z "$mem_throughput" ]; then mem_throughput=0; fi

        update_report "memory" "{ \"total_operations\": $mem_ops, \"throughput_mib_sec\": $mem_throughput }"
        echo "Sysbench Memory finished."
      ''}

      ${lib.optionalString stressEnabled ''
        echo "Running Stress-ng (Load Test)..."
        # Use JSON output for reliable parsing
        stress_json=$(mktemp)
        if stress-ng --cpu 1 --timeout 1s --json "$stress_json"; then
            bogops=$(jq '.metrics[0]."bogo-ops"' "$stress_json" || echo "0")
        else
            echo "Stress-ng failed or timed out"
            bogops=0
        fi
        rm -f "$stress_json"
        update_report "stress" "{ \"bogops\": $bogops }"
        echo "Stress-ng finished."
      ''}

      ${lib.optionalString iperfEnabled ''
        echo "Running iperf3 (Loopback)..."
        # Start server in background
        iperf3 -s -p 5201 -D >/dev/null 2>&1
        sleep 1
        # Run client - reduced time to 1s
        iperf_json=$(iperf3 -c 127.0.0.1 -p 5201 -t 1 -J || echo "{}")
        # Extract bits_per_second from end structure
        bps=$(echo "$iperf_json" | jq '.end.sum_received.bits_per_second // 0')
        update_report "network_loopback" "{ \"bits_per_second\": $bps }"
        echo "iperf3 finished: $bps bps"
        pkill iperf3 || true
      ''}

      echo "Benchmarks completed. Report saved to $REPORT_FILE"
      cat "$REPORT_FILE"
    '';
}

{ pkgs, lib, ... }:

let
  inherit (lib) mkOption types;

  # Performance metrics structure
  metricTypes = {
    latency = "latency";
    throughput = "throughput";
    cpu = "cpu-usage";
    memory = "memory-usage";
  };

  # Helper to create benchmark configuration
  mkBenchmark =
    {
      name,
      type,
      duration ? "5m",
      metrics,
    }:
    {
      inherit
        name
        type
        duration
        metrics
        ;
      type = "benchmark-scenario";
    };

  # Helper for baseline definition
  mkBaseline =
    {
      metric,
      threshold,
      unit,
    }:
    {
      inherit metric threshold unit;
      type = "performance-baseline";
    };

in
{
  inherit metricTypes mkBenchmark mkBaseline;

  # Validation helpers
  validators = {
    regression =
      {
        metric,
        current,
        baseline,
        tolerance ? 0.05,
      }:
      let
        diff = (current - baseline) / baseline;
      in
      if diff > tolerance then "failed" else "passed";
  };

  # Tool wrappers
  tools = {
    iperf3 = "${pkgs.iperf3}/bin/iperf3";
    wrk = "${pkgs.wrk}/bin/wrk";
    stress = "${pkgs.stress}/bin/stress";
  };

  generateRegressionScript =
    {
      baselineFile ? "/var/lib/performance-baseline/baseline.json",
      currentFile ? "/var/log/benchmark-report.json",
      thresholdPercent ? 10,
    }:
    ''
      #!${pkgs.runtimeShell}
      set -euo pipefail

      export PATH="${
        lib.makeBinPath (
          with pkgs;
          [
            jq
            coreutils
            bc
          ]
        )
      }:$PATH"

      BASELINE="${baselineFile}"
      CURRENT="${currentFile}"
      THRESHOLD="${toString thresholdPercent}"

      if [ ! -f "$BASELINE" ]; then
        echo "No baseline found at $BASELINE. Creating new baseline from current results."
        mkdir -p "$(dirname "$BASELINE")"
        cp "$CURRENT" "$BASELINE"
        echo "Baseline created."
        exit 0
      fi

      echo "Comparing current results against baseline..."

      # Helper to check metric regression
      # Usage: check_metric "Category" "MetricName" "Direction"
      # Direction: "higher" (better) or "lower" (better)
      check_metric() {
        local category=$1
        local metric=$2
        local direction=$3
        
        local base_val=$(jq -r ".results[\"$category\"][\"$metric\"] // empty" "$BASELINE")
        local curr_val=$(jq -r ".results[\"$category\"][\"$metric\"] // empty" "$CURRENT")
        
        if [ -z "$base_val" ] || [ -z "$curr_val" ]; then
          echo "Skipping $category.$metric: missing data."
          return 0
        fi
        
        # Calculate change percentage
        # (current - baseline) / baseline * 100
        local diff=$(echo "scale=2; $curr_val - $base_val" | bc)
        
        # Avoid division by zero
        if [ "$base_val" = "0" ]; then
           echo "Skipping $category.$metric: baseline is zero."
           return 0
        fi

        local percent=$(echo "scale=2; ($diff / $base_val) * 100" | bc)
        
        echo "Metric: $category.$metric | Baseline: $base_val | Current: $curr_val | Change: $percent%"
        
        if [ "$direction" = "higher" ]; then
          # Logic: If current < baseline - threshold, FAIL
          # e.g., Base 100, Curr 80, Threshold 10%.  Change -20%. -20 < -10 -> Regression
          if (( $(echo "$percent < -$THRESHOLD" | bc -l) )); then
            echo "❌ REGRESSION DETECTED: $category.$metric dropped by $percent% (Threshold: $THRESHOLD%)"
            return 1
          fi
        elif [ "$direction" = "lower" ]; then
          # Logic: If current > baseline + threshold, FAIL (e.g., Latency)
          # e.g., Base 10ms, Curr 20ms, Threshold 10%. Change +100%. 100 > 10 -> Regression
          if (( $(echo "$percent > $THRESHOLD" | bc -l) )); then
            echo "❌ REGRESSION DETECTED: $category.$metric increased by $percent% (Threshold: $THRESHOLD%)"
            return 1
          fi
        fi
        
        echo "✅ OK"
        return 0
      }

      # Check CPU Events (Higher is better)
      check_metric "cpu" "events_per_second" "higher" || exit 1

      # Check Memory Throughput (Higher is better)
      check_metric "memory" "throughput_mib_sec" "higher" || exit 1

      # Check Network Loopback (Higher is better)
      check_metric "network_loopback" "bits_per_second" "higher" || exit 1

      # Check Stress BogoOps (Higher is better)
      check_metric "stress" "bogops" "higher" || exit 1

      echo "Performance Regression Test Passed."
    '';
}

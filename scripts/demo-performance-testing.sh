#!/usr/bin/env nix-shell
#!nix-shell -i bash -p jq sysbench iperf3 stress-ng

set -euo pipefail

echo "=== NixOS Gateway Performance Testing Demonstration ==="
echo

# Create temporary benchmark report
REPORT_FILE="/tmp/demo-benchmark.json"
mkdir -p "$(dirname "$REPORT_FILE")"

# Initialize JSON report
jq -n --arg date "$(date -Iseconds)" '{timestamp: $date, results: {}}' > "$REPORT_FILE"

update_report() {
  local key="$1"
  local value="$2"
  local temp_file=$(mktemp)
  jq ".results.$key = $value" "$REPORT_FILE" > "$temp_file" && mv "$temp_file" "$REPORT_FILE"
}

echo "🔥 Running CPU Benchmark..."
cpu_out=$(sysbench cpu --cpu-max-prime=100 run 2>/dev/null || echo "")
cpu_score=$(echo "$cpu_out" | grep "events per second:" | awk '{print $4}' || echo "0")
if [ -z "$cpu_score" ]; then cpu_score=0; fi
update_report "cpu" "{ \"events_per_second\": $cpu_score }"
echo "   CPU Score: $cpu_score events/sec"

echo "💾 Running Memory Benchmark..."
mem_out=$(sysbench memory --memory-total-size=10M run 2>/dev/null || echo "")
mem_ops=$(echo "$mem_out" | grep "Total operations:" | awk '{print $3}' || echo "0")
mem_throughput=$(echo "$mem_out" | grep "transferred" | awk '{print $4}' | tr -d '(' || echo "0")

if [ -z "$mem_ops" ]; then mem_ops=0; fi
if [ -z "$mem_throughput" ]; then mem_throughput=0; fi

update_report "memory" "{ \"total_operations\": $mem_ops, \"throughput_mib_sec\": $mem_throughput }"
echo "   Memory Operations: $mem_ops"
echo "   Memory Throughput: $mem_throughput MiB/s"

echo "🌐 Running Network Benchmark..."
# Start server in background
iperf3 -s -p 5201 -D >/dev/null 2>&1
sleep 1
# Run client
iperf_json=$(iperf3 -c 127.0.0.1 -p 5201 -t 1 -J 2>/dev/null || echo "{}")
bps=$(echo "$iperf_json" | jq '.end.sum_received.bits_per_second // 0')
update_report "network_loopback" "{ \"bits_per_second\": $bps }"
echo "   Network Throughput: $bps bits/sec"
pkill iperf3 2>/dev/null || true

echo "⚡ Running Stress Test..."
stress_json=$(mktemp)
if stress-ng --cpu 1 --timeout 1s --json "$stress_json" 2>/dev/null; then
    bogops=$(jq '.metrics[0]."bogo-ops"' "$stress_json" 2>/dev/null || echo "0")
else
    echo "   Stress test failed or timed out"
    bogops=0
fi
rm -f "$stress_json"
update_report "stress" "{ \"bogops\": $bogops }"
echo "   Stress BogoOps: $bogops"

echo
echo "📊 Benchmark Results Summary:"
echo "=============================="
cat "$REPORT_FILE" | jq .

echo
echo "✅ Performance Testing Demonstration Complete!"
echo "📁 Results saved to: $REPORT_FILE"

# Validate results
echo
echo "🔍 Validation Results:"
if (( $(echo "$cpu_score > 0" | bc -l) )); then
    echo "✅ CPU benchmark: PASSED"
else
    echo "❌ CPU benchmark: FAILED"
fi

if (( $(echo "$mem_ops > 0" | bc -l) )); then
    echo "✅ Memory benchmark: PASSED"
else
    echo "❌ Memory benchmark: FAILED"
fi

if (( $(echo "$bps > 0" | bc -l) )); then
    echo "✅ Network benchmark: PASSED"
else
    echo "❌ Network benchmark: FAILED"
fi

if (( $(echo "$bogops > 0" | bc -l) )); then
    echo "✅ Stress benchmark: PASSED"
else
    echo "❌ Stress benchmark: FAILED"
fi

echo
echo "🎯 Performance Testing Features Validated Successfully!"
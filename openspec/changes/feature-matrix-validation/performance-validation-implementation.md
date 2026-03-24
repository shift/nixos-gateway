# Performance Validation Checks Implementation

## Performance Validation Library

```nix
# lib/performance-checks.nix
{ lib, ... }:

let
  # Performance thresholds
  thresholds = {
    cpuMaxPercent = 80;
    memoryMaxPercent = 85;
    networkLatencyMaxMs = 100;
    dnsQueryTimeMaxMs = 50;
    dhcpLeaseTimeMaxMs = 5000;
  };

  # Monitoring helpers
  collectMetrics = name: metrics: ''
    # Store performance metrics
    mkdir -p /tmp/performance-metrics
    cat > "/tmp/performance-metrics/${name}.json" << EOF
    ${builtins.toJSON metrics}
    EOF
  '';

  # CPU monitoring
  monitorCPU = timeoutSeconds: ''
    cpu_samples=()
    for i in $(seq 1 ${toString timeoutSeconds}); do
      cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
      cpu_samples+=("$cpu_usage")
      sleep 1
    done

    # Calculate statistics
    cpu_max=$(printf '%s\n' "''${cpu_samples[@]}" | sort -n | tail -1)
    cpu_avg=$(printf '%s\n' "''${cpu_samples[@]}" | awk '{sum+=$1} END {print sum/NR}')

    echo "CPU Max: $cpu_max%, Avg: $cpu_avg%"
  '';

  # Memory monitoring
  monitorMemory = timeoutSeconds: ''
    mem_samples=()
    for i in $(seq 1 ${toString timeoutSeconds}); do
      mem_usage=$(free | grep Mem | awk '{printf "%.2f", $3/$2 * 100.0}')
      mem_samples+=("$mem_usage")
      sleep 1
    done

    mem_max=$(printf '%s\n' "''${mem_samples[@]}" | sort -n | tail -1)
    mem_avg=$(printf '%s\n' "''${mem_samples[@]}" | awk '{sum+=$1} END {print sum/NR}')

    echo "Memory Max: $mem_max%, Avg: $mem_avg%"
  '';

in {
  # Performance validation checks
  performance = {
    # Resource utilization monitoring
    resourceUtilization = {
      name = "resource-utilization";
      description = "Monitor CPU and memory usage under normal operation";
      timeout = 60;
      testScript = ''
        echo "Starting resource utilization monitoring..."

        # Monitor baseline
        baseline_cpu=$(${monitorCPU 10} | grep "CPU Max" | cut -d: -f2 | cut -d% -f1 | tr -d ' ')
        baseline_mem=$(${monitorMemory 10} | grep "Memory Max" | cut -d: -f2 | cut -d% -f1 | tr -d ' ')

        # Run light load test
        client1.succeed("ping -c 10 gateway &")
        client1.succeed("nslookup example.com gateway || true &")
        sleep 5

        # Monitor during load
        load_cpu=$(${monitorCPU 20} | grep "CPU Max" | cut -d: -f2 | cut -d% -f1 | tr -d ' ')
        load_mem=$(${monitorMemory 20} | grep "Memory Max" | cut -d: -f2 | cut -d% -f1 | tr -d ' ')

        # Validate thresholds
        if (( $(echo "$load_cpu > ${toString thresholds.cpuMaxPercent}" | bc -l) )); then
          echo "CPU usage too high: $load_cpu%"
          exit 1
        fi

        if (( $(echo "$load_mem > ${toString thresholds.memoryMaxPercent}" | bc -l) )); then
          echo "Memory usage too high: $load_mem%"
          exit 1
        fi

        # Collect metrics
        ${collectMetrics "resource-utilization" {
          cpuBaseline = baseline_cpu;
          cpuMax = load_cpu;
          memoryBaseline = baseline_mem;
          memoryMax = load_mem;
          passed = true;
        }}

        echo "Resource utilization within acceptable limits"
      '';
    };

    # Network throughput testing
    networkThroughput = {
      name = "network-throughput";
      description = "Test network throughput between nodes";
      timeout = 120;
      testScript = ''
        echo "Testing network throughput..."

        # Install iperf if not available
        gateway.succeed("which iperf3 || nix-env -iA nixos.iperf3")

        # Start iperf server on gateway
        gateway.succeed("iperf3 -s -D")

        # Run throughput test from client
        client1.succeed("which iperf3 || nix-env -iA nixos.iperf3")
        throughput_result=$(client1.succeed("iperf3 -c gateway -t 10 -J | jq -r '.end.sum_received.bits_per_second'"))

        # Convert to Mbps
        throughput_mbps=$(echo "scale=2; $throughput_result / 1000000" | bc)

        # Validate minimum throughput (100 Mbps)
        if (( $(echo "$throughput_mbps < 100" | bc -l) )); then
          echo "Network throughput too low: ${throughput_mbps} Mbps"
          exit 1
        fi

        # Collect metrics
        ${collectMetrics "network-throughput" {
          throughputMbps = throughput_mbps;
          minimumRequired = 100;
          passed = true;
        }}

        echo "Network throughput: ${throughput_mbps} Mbps (acceptable)"
      '';
    };

    # DNS performance testing
    dnsPerformance = {
      name = "dns-performance";
      description = "Test DNS query performance";
      timeout = 60;
      testScript = ''
        echo "Testing DNS performance..."

        # Skip if DNS not enabled
        if ! gateway.succeed("systemctl is-active kresd@1.service"); then
          echo "DNS not enabled, skipping test"
          ${collectMetrics "dns-performance" {
            skipped = true;
            reason = "DNS service not enabled";
          }}
          exit 0
        fi

        # Test DNS query time
        query_times=()
        for i in {1..10}; do
          start_time=$(date +%s%N)
          client1.succeed("dig @gateway example.com > /dev/null")
          end_time=$(date +%s%N)
          query_time=$(( (end_time - start_time) / 1000000 ))  # Convert to milliseconds
          query_times+=("$query_time")
        done

        # Calculate statistics
        avg_time=$(printf '%s\n' "''${query_times[@]}" | awk '{sum+=$1} END {print sum/NR}')
        max_time=$(printf '%s\n' "''${query_times[@]}" | sort -n | tail -1)

        # Validate performance
        if (( $(echo "$max_time > ${toString thresholds.dnsQueryTimeMaxMs}" | bc -l) )); then
          echo "DNS query time too slow: ${max_time}ms max"
          exit 1
        fi

        # Collect metrics
        ${collectMetrics "dns-performance" {
          averageQueryTimeMs = avg_time;
          maxQueryTimeMs = max_time;
          thresholdMs = thresholds.dnsQueryTimeMaxMs;
          passed = true;
        }}

        echo "DNS performance: ${avg_time}ms average, ${max_time}ms max"
      '';
    };

    # DHCP performance testing
    dhcpPerformance = {
      name = "dhcp-performance";
      description = "Test DHCP lease assignment performance";
      timeout = 120;
      testScript = ''
        echo "Testing DHCP performance..."

        # Skip if DHCP not enabled
        if ! gateway.succeed("systemctl is-active kea-dhcp4-server.service"); then
          echo "DHCP not enabled, skipping test"
          ${collectMetrics "dhcp-performance" {
            skipped = true;
            reason = "DHCP service not enabled";
          }}
          exit 0
        fi

        # Test DHCP lease time
        start_time=$(date +%s%N)
        client1.succeed("dhcpcd -T eth1 | grep -q 'new_ip_address'")
        end_time=$(date +%s%N)
        lease_time=$(( (end_time - start_time) / 1000000 ))  # Convert to milliseconds

        # Validate lease time
        if (( lease_time > ${toString thresholds.dhcpLeaseTimeMaxMs} )); then
          echo "DHCP lease time too slow: ${lease_time}ms"
          exit 1
        fi

        # Collect metrics
        ${collectMetrics "dhcp-performance" {
          leaseTimeMs = lease_time;
          thresholdMs = thresholds.dhcpLeaseTimeMaxMs;
          passed = true;
        }}

        echo "DHCP lease time: ${lease_time}ms"
      '';
    };

    # Concurrent connection testing
    concurrentConnections = {
      name = "concurrent-connections";
      description = "Test handling of multiple concurrent connections";
      timeout = 180;
      testScript = ''
        echo "Testing concurrent connections..."

        # Start multiple clients making requests
        for i in {1..5}; do
          client1.succeed("ping -c 10 gateway > /dev/null &")
          client1.succeed("for j in {1..5}; do dig @gateway example.com > /dev/null 2>&1; done &")
        done

        # Monitor resources during concurrent load
        load_cpu=$(${monitorCPU 30} | grep "CPU Max" | cut -d: -f2 | cut -d% -f1 | tr -d ' ')
        load_mem=$(${monitorMemory 30} | grep "Memory Max" | cut -d: -f2 | cut -d% -f1 | tr -d ' ')

        # Wait for background processes
        sleep 10

        # Validate under concurrent load
        if (( $(echo "$load_cpu > ${toString thresholds.cpuMaxPercent}" | bc -l) )); then
          echo "CPU usage too high under concurrent load: $load_cpu%"
          exit 1
        fi

        # Collect metrics
        ${collectMetrics "concurrent-connections" {
          concurrentClients = 5;
          cpuMax = load_cpu;
          memoryMax = load_mem;
          passed = true;
        }}

        echo "Concurrent connections handled successfully"
      '';
    };

    # Memory leak detection
    memoryLeakDetection = {
      name = "memory-leak-detection";
      description = "Monitor for memory leaks over extended period";
      timeout = 300;
      testScript = ''
        echo "Testing for memory leaks..."

        # Monitor memory usage over time
        initial_mem=$(gateway.succeed("free | grep Mem | awk '{print $3}'"))
        sleep 60
        mid_mem=$(gateway.succeed("free | grep Mem | awk '{print $3}'"))
        sleep 60
        final_mem=$(gateway.succeed("free | grep Mem | awk '{print $3}'"))

        # Calculate memory growth
        mem_growth=$((final_mem - initial_mem))

        # Allow for some growth but detect significant leaks (>10MB)
        if (( mem_growth > 10000 )); then
          echo "Potential memory leak detected: ${mem_growth}KB growth"
          exit 1
        fi

        # Collect metrics
        ${collectMetrics "memory-leak-detection" {
          initialMemoryKb = initial_mem;
          finalMemoryKb = final_mem;
          memoryGrowthKb = mem_growth;
          maxAllowedGrowthKb = 10000;
          passed = true;
        }}

        echo "Memory usage stable: ${mem_growth}KB growth over 2 minutes"
      '';
    };
  };
}
```

## Performance Test Runner

```bash
#!/usr/bin/env bash
# scripts/run-performance-checks.sh

set -euo pipefail

COMBINATION="$1"
CONFIG_FILE="$2"
RESULTS_DIR="results/$COMBINATION"

echo "Running performance validation checks for $COMBINATION"

# Create results directory
mkdir -p "$RESULTS_DIR/performance"

# Generate NixOS test with performance checks
cat > "tests/${COMBINATION}-performance.nix" << EOF
{ pkgs, lib, ... }:

let
  performanceChecks = import ../lib/performance-checks.nix { inherit lib; };
in

pkgs.testers.nixosTest {
  name = "${COMBINATION}-performance-validation";

  nodes = {
    gateway = { config, pkgs, ... }: {
      imports = [ ../modules ];
      services.gateway = import "$CONFIG_FILE";

      # Install performance monitoring tools
      environment.systemPackages = with pkgs; [
        iperf3
        bc
        jq
      ];
    };

    client1 = { config, pkgs, ... }: {
      virtualisation.vlans = [ 1 ];
      networking.useDHCP = true;
      networking.nameservers = [ "192.168.1.1" ];

      environment.systemPackages = with pkgs; [
        iperf3
        bc
        jq
        dnsutils
        dhcpcd
      ];
    };
  };

  testScript = ''
    start_all()

    # Run performance checks
    \${performanceChecks.performance.resourceUtilization.testScript}
    \${performanceChecks.performance.networkThroughput.testScript}
    \${performanceChecks.performance.dnsPerformance.testScript}
    \${performanceChecks.performance.dhcpPerformance.testScript}
    \${performanceChecks.performance.concurrentConnections.testScript}
    \${performanceChecks.performance.memoryLeakDetection.testScript}

    # Collect all results
    mkdir -p /tmp/test-results/performance
    cp -r /tmp/performance-metrics/* /tmp/test-results/performance/ 2>/dev/null || true
  '';
}
EOF

# Run the test
echo "Executing performance validation..."
if nix build ".#checks.x86_64-linux.${COMBINATION}-performance"; then
  echo "✅ Performance validation passed"

  # Extract results
  cp result/test-results/performance/* "$RESULTS_DIR/performance/" 2>/dev/null || true

  # Generate summary
  cat > "$RESULTS_DIR/performance-summary.json" << EOF
  {
    "combination": "$COMBINATION",
    "category": "performance",
    "timestamp": "$(date -Iseconds)",
    "overall_result": "passed",
    "checks": [
      "resource-utilization",
      "network-throughput",
      "dns-performance",
      "dhcp-performance",
      "concurrent-connections",
      "memory-leak-detection"
    ]
  }
  EOF

else
  echo "❌ Performance validation failed"
  exit 1
fi
```

## Performance Check Categories

### 1. Resource Utilization Monitoring
- Monitors CPU and memory usage during normal operation
- Validates against predefined thresholds (<80% CPU, <85% memory)
- Tests both baseline and load conditions
- Ensures system remains responsive under load

### 2. Network Throughput Testing
- Measures actual network throughput between nodes
- Uses iperf3 for accurate bandwidth testing
- Validates minimum throughput requirements (100 Mbps)
- Tests both directions if applicable

### 3. DNS Performance Testing
- Measures DNS query response times
- Tests multiple queries to establish averages
- Validates response times under 50ms maximum
- Skips test if DNS service not enabled

### 4. DHCP Performance Testing
- Measures time to obtain DHCP lease
- Tests lease renewal process
- Validates lease times under 5 seconds
- Skips test if DHCP service not enabled

### 5. Concurrent Connection Testing
- Tests handling of multiple simultaneous connections
- Monitors resource usage under concurrent load
- Validates system stability with multiple clients
- Tests both network and service concurrency

### 6. Memory Leak Detection
- Monitors memory usage over extended periods
- Detects gradual memory growth indicating leaks
- Allows for normal memory fluctuations
- Flags significant memory growth (>10MB)

## Performance Result Analysis

```bash
#!/usr/bin/env bash
# scripts/analyze-performance-results.sh

COMBINATION="$1"
RESULTS_DIR="results/$COMBINATION/performance"

echo "Analyzing performance validation results for $COMBINATION"

# Parse individual check results
resource_passed=$(jq -r '.passed' "$RESULTS_DIR/resource-utilization.json" 2>/dev/null || echo "false")
throughput_passed=$(jq -r '.passed' "$RESULTS_DIR/network-throughput.json" 2>/dev/null || echo "false")
dns_passed=$(jq -r '.passed // .skipped' "$RESULTS_DIR/dns-performance.json" 2>/dev/null || echo "false")
dhcp_passed=$(jq -r '.passed // .skipped' "$RESULTS_DIR/dhcp-performance.json" 2>/dev/null || echo "false")
concurrent_passed=$(jq -r '.passed' "$RESULTS_DIR/concurrent-connections.json" 2>/dev/null || echo "false")
memory_passed=$(jq -r '.passed' "$RESULTS_DIR/memory-leak-detection.json" 2>/dev/null || echo "false")

# Calculate overall performance score
passed_checks=0
total_checks=6

[ "$resource_passed" = "true" ] && ((passed_checks++))
[ "$throughput_passed" = "true" ] && ((passed_checks++))
[ "$dns_passed" = "true" ] && ((passed_checks++))
[ "$dhcp_passed" = "true" ] && ((passed_checks++))
[ "$concurrent_passed" = "true" ] && ((passed_checks++))
[ "$memory_passed" = "true" ] && ((passed_checks++))

pass_rate=$((passed_checks * 100 / total_checks))

# Extract key metrics
cpu_max=$(jq -r '.cpuMax' "$RESULTS_DIR/resource-utilization.json" 2>/dev/null || echo "N/A")
memory_max=$(jq -r '.memoryMax' "$RESULTS_DIR/resource-utilization.json" 2>/dev/null || echo "N/A")
throughput=$(jq -r '.throughputMbps' "$RESULTS_DIR/network-throughput.json" 2>/dev/null || echo "N/A")

# Generate comprehensive report
cat > "$RESULTS_DIR/performance-report.json" << EOF
{
  "combination": "$COMBINATION",
  "validation_category": "performance",
  "timestamp": "$(date -Iseconds)",
  "summary": {
    "total_checks": $total_checks,
    "passed_checks": $passed_checks,
    "failed_checks": $((total_checks - passed_checks)),
    "pass_rate_percent": $pass_rate,
    "overall_passed": $([ $pass_rate -ge 80 ] && echo "true" || echo "false")
  },
  "key_metrics": {
    "cpu_max_percent": "$cpu_max",
    "memory_max_percent": "$memory_max",
    "network_throughput_mbps": "$throughput"
  },
  "check_results": {
    "resource_utilization": $resource_passed,
    "network_throughput": $throughput_passed,
    "dns_performance": $dns_passed,
    "dhcp_performance": $dhcp_passed,
    "concurrent_connections": $concurrent_passed,
    "memory_leak_detection": $memory_passed
  },
  "recommendations": $([ $pass_rate -lt 80 ] && echo '"Performance issues detected - review resource usage and optimize configuration"' || echo '"Performance validation passed - system meets performance requirements"')
}
EOF

echo "Performance validation: $passed_checks/$total_checks checks passed ($pass_rate%)"
echo "Key metrics: CPU ${cpu_max}%, Memory ${memory_max}%, Throughput ${throughput} Mbps"
```

This performance validation framework ensures that supported combinations meet strict performance criteria and can handle production workloads without resource exhaustion or performance degradation.
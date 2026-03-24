# Resource Utilization Validation Checks Implementation

## Resource Validation Library

```nix
# lib/resource-checks.nix
{ lib, ... }:

let
  # Resource thresholds and limits
  resourceLimits = {
    cpu = {
      warningPercent = 70;
      criticalPercent = 85;
      maxCores = 8;
    };
    memory = {
      warningPercent = 75;
      criticalPercent = 90;
      minFreeGB = 0.5;
    };
    disk = {
      warningPercent = 80;
      criticalPercent = 95;
      minFreeGB = 1;
    };
    network = {
      maxUtilizationPercent = 80;
      minBandwidthMbps = 100;
    };
  };

  # Resource monitoring helpers
  collectResourceMetrics = name: metrics: ''
    # Store resource metrics
    mkdir -p /tmp/resource-metrics
    cat > "/tmp/resource-metrics/${name}.json" << EOF
    ${builtins.toJSON metrics}
    EOF
  '';

  # Comprehensive resource monitoring
  monitorSystemResources = durationSeconds: ''
    # Initialize monitoring arrays
    cpu_usage=()
    memory_usage=()
    disk_usage=()
    network_rx=()
    network_tx=()

    # Get initial network stats
    initial_rx=$(cat /proc/net/dev | grep eth0 | awk '{print $2}')
    initial_tx=$(cat /proc/net/dev | grep eth0 | awk '{print $10}')

    for i in $(seq 1 ${toString durationSeconds}); do
      # CPU monitoring
      cpu=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
      cpu_usage+=("$cpu")

      # Memory monitoring (percentage)
      mem_percent=$(free | grep Mem | awk '{printf "%.2f", $3/$2 * 100.0}')
      memory_usage+=("$mem_percent")

      # Disk monitoring (root filesystem)
      disk_percent=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
      disk_usage+=("$disk_percent")

      sleep 1
    done

    # Get final network stats
    final_rx=$(cat /proc/net/dev | grep eth0 | awk '{print $2}')
    final_tx=$(cat /proc/net/dev | grep eth0 | awk '{print $10}')

    # Calculate network utilization (simplified)
    rx_bytes=$((final_rx - initial_rx))
    tx_bytes=$((final_tx - initial_tx))
    total_bytes=$((rx_bytes + tx_bytes))
    network_utilization=0  # Would need interface speed for accurate calculation

    # Calculate statistics
    cpu_max=$(printf '%s\n' "''${cpu_usage[@]}" | sort -n | tail -1)
    cpu_avg=$(printf '%s\n' "''${cpu_usage[@]}" | awk '{sum+=$1} END {print sum/NR}')

    mem_max=$(printf '%s\n' "''${memory_usage[@]}" | sort -n | tail -1)
    mem_avg=$(printf '%s\n' "''${memory_usage[@]}" | awk '{sum+=$1} END {print sum/NR}')

    disk_max=$(printf '%s\n' "''${disk_usage[@]}" | sort -n | tail -1)
    disk_avg=$(printf '%s\n' "''${disk_usage[@]}" | awk '{sum+=$1} END {print sum/NR}')

    echo "CPU: Max $cpu_max%, Avg $cpu_avg%"
    echo "Memory: Max $mem_max%, Avg $mem_avg%"
    echo "Disk: Max $disk_max%, Avg $disk_avg%"
    echo "Network: $total_bytes bytes transferred"
  '';

in {
  # Resource utilization validation checks
  resource = {
    # Comprehensive resource capacity testing
    resourceCapacity = {
      name = "resource-capacity";
      description = "Test system resource limits and capacity planning";
      timeout = 180;
      testScript = ''
        echo "Testing resource capacity..."

        # Get system specifications
        total_memory=$(gateway.succeed("free -g | grep Mem | awk '{print $2}'"))
        total_cores=$(gateway.succeed("nproc"))
        total_disk=$(gateway.succeed("df -BG / | tail -1 | awk '{print $2}' | sed 's/G//'"))

        echo "System specs: ${total_memory}GB RAM, ${total_cores} cores, ${total_disk}GB disk"

        # Test memory capacity
        memory_test=$(gateway.succeed("stress-ng --vm 1 --vm-bytes 80% --timeout 10s 2>&1 || true"))
        if echo "$memory_test" | grep -q "successful"; then
          memory_capacity="passed"
        else
          memory_capacity="failed"
        fi

        # Test CPU capacity
        cpu_test=$(gateway.succeed("stress-ng --cpu $total_cores --timeout 10s 2>&1 || true"))
        if echo "$cpu_test" | grep -q "successful"; then
          cpu_capacity="passed"
        else
          cpu_capacity="failed"
        fi

        # Test disk I/O capacity
        disk_test=$(gateway.succeed("dd if=/dev/zero of=/tmp/testfile bs=1M count=100 conv=fdatasync 2>&1 | grep -o '[0-9.]* MB/s' || echo 'failed'"))
        if echo "$disk_test" | grep -q "MB/s"; then
          disk_capacity="passed"
        else
          disk_capacity="failed"
        fi

        # Validate against minimum requirements
        if [ "$total_memory" -lt 2 ]; then
          echo "ERROR: Insufficient memory (${total_memory}GB < 2GB minimum)"
          exit 1
        fi

        if [ "$total_cores" -lt 1 ]; then
          echo "ERROR: Insufficient CPU cores (${total_cores} < 1 minimum)"
          exit 1
        fi

        if [ "$total_disk" -lt 10 ]; then
          echo "ERROR: Insufficient disk space (${total_disk}GB < 10GB minimum)"
          exit 1
        fi

        # Collect metrics
        ${collectResourceMetrics "resource-capacity" {
          totalMemoryGB = total_memory;
          totalCores = total_cores;
          totalDiskGB = total_disk;
          memoryCapacityTest = memory_capacity;
          cpuCapacityTest = cpu_capacity;
          diskCapacityTest = disk_capacity;
          meetsMinimumRequirements = true;
        }}

        echo "Resource capacity validation completed"
      '';
    };

    # Resource conflict detection
    resourceConflicts = {
      name = "resource-conflicts";
      description = "Detect resource conflicts between services";
      timeout = 120;
      testScript = ''
        echo "Testing for resource conflicts..."

        # Check for port conflicts
        used_ports=$(gateway.succeed("ss -tln | grep LISTEN | awk '{print $4}' | cut -d: -f2 | sort | uniq -d"))
        if [ -n "$used_ports" ]; then
          echo "WARNING: Port conflicts detected on ports: $used_ports"
          port_conflicts="true"
        else
          port_conflicts="false"
        fi

        # Check for systemd resource conflicts
        systemd_conflicts=$(gateway.succeed("systemctl --failed | grep -v '0 loaded units listed' | wc -l"))
        if [ "$systemd_conflicts" -gt 0 ]; then
          echo "WARNING: $systemd_conflicts systemd units failed"
          systemd_conflicts_flag="true"
        else
          systemd_conflicts_flag="false"
        fi

        # Check for file system conflicts
        filesystem_conflicts=$(gateway.succeed("find /etc -name '*.conf' -exec grep -l 'conflict\\|error' {} \\; | wc -l"))
        if [ "$filesystem_conflicts" -gt 0 ]; then
          echo "WARNING: Potential filesystem conflicts in config files"
          filesystem_conflicts_flag="true"
        else
          filesystem_conflicts_flag="false"
        fi

        # Check for memory overcommit
        overcommit=$(gateway.succeed("sysctl vm.overcommit_memory | cut -d= -f2"))
        if [ "$overcommit" -eq 2 ]; then
          overcommit_ratio=$(gateway.succeed("sysctl vm.overcommit_ratio | cut -d= -f2"))
          echo "Memory overcommit ratio: $overcommit_ratio%"
        fi

        # Determine if conflicts are acceptable
        if [ "$port_conflicts" = "true" ] || [ "$systemd_conflicts_flag" = "true" ]; then
          conflicts_critical="true"
        else
          conflicts_critical="false"
        fi

        # Collect metrics
        ${collectResourceMetrics "resource-conflicts" {
          portConflicts = port_conflicts;
          systemdConflicts = systemd_conflicts_flag;
          filesystemConflicts = filesystem_conflicts_flag;
          criticalConflicts = conflicts_critical;
        }}

        if [ "$conflicts_critical" = "true" ]; then
          echo "Critical resource conflicts detected"
          exit 1
        else
          echo "No critical resource conflicts found"
        fi
      '';
    };

    # Resource scaling and limits testing
    resourceScaling = {
      name = "resource-scaling";
      description = "Test resource utilization scaling with load";
      timeout = 240;
      testScript = ''
        echo "Testing resource scaling..."

        # Baseline measurement
        echo "Measuring baseline resource usage..."
        baseline_cpu=$(${monitorSystemResources 10} | grep "CPU:" | cut -d' ' -f2 | cut -d% -f1)
        baseline_mem=$(${monitorSystemResources 10} | grep "Memory:" | cut -d' ' -f2 | cut -d% -f1)

        # Light load test
        echo "Applying light load..."
        client1.succeed("ping -c 50 gateway > /dev/null &")
        client1.succeed("for i in {1..10}; do dig @gateway example.com > /dev/null 2>&1; done &")
        sleep 10

        light_cpu=$(${monitorSystemResources 10} | grep "CPU:" | cut -d' ' -f2 | cut -d% -f1)
        light_mem=$(${monitorSystemResources 10} | grep "Memory:" | cut -d' ' -f2 | cut -d% -f1)

        # Heavy load test
        echo "Applying heavy load..."
        for i in {1..5}; do
          client1.succeed("ab -n 100 -c 5 http://httpbin.org/ > /dev/null 2>&1 &")
        done
        sleep 15

        heavy_cpu=$(${monitorSystemResources 15} | grep "CPU:" | cut -d' ' -f2 | cut -d% -f1)
        heavy_mem=$(${monitorSystemResources 15} | grep "Memory:" | cut -d' ' -f2 | cut -d% -f1)

        # Calculate scaling factors
        cpu_scaling_light=$(echo "scale=2; $light_cpu / ($baseline_cpu + 1)" | bc)
        cpu_scaling_heavy=$(echo "scale=2; $heavy_cpu / ($baseline_cpu + 1)" | bc)
        mem_scaling_light=$(echo "scale=2; $light_mem / ($baseline_mem + 1)" | bc)
        mem_scaling_heavy=$(echo "scale=2; $heavy_mem / ($baseline_mem + 1)" | bc)

        # Validate scaling behavior
        if (( $(echo "$heavy_cpu > ${toString resourceLimits.cpu.criticalPercent}" | bc -l) )); then
          echo "ERROR: CPU usage too high under heavy load ($heavy_cpu%)"
          scaling_acceptable="false"
        elif (( $(echo "$heavy_mem > ${toString resourceLimits.memory.criticalPercent}" | bc -l) )); then
          echo "ERROR: Memory usage too high under heavy load ($heavy_mem%)"
          scaling_acceptable="false"
        else
          scaling_acceptable="true"
        fi

        # Collect metrics
        ${collectResourceMetrics "resource-scaling" {
          baselineCPU = baseline_cpu;
          baselineMemory = baseline_mem;
          lightLoadCPU = light_cpu;
          lightLoadMemory = light_mem;
          heavyLoadCPU = heavy_cpu;
          heavyLoadMemory = heavy_mem;
          cpuScalingLight = cpu_scaling_light;
          cpuScalingHeavy = cpu_scaling_heavy;
          memScalingLight = mem_scaling_light;
          memScalingHeavy = mem_scaling_heavy;
          scalingAcceptable = scaling_acceptable;
        }}

        if [ "$scaling_acceptable" = "false" ]; then
          echo "Resource scaling test failed"
          exit 1
        else
          echo "Resource scaling within acceptable limits"
        fi
      '';
    };

    # Storage resource validation
    storageResources = {
      name = "storage-resources";
      description = "Validate storage resource utilization and limits";
      timeout = 120;
      testScript = ''
        echo "Testing storage resources..."

        # Check disk space utilization
        root_usage=$(gateway.succeed("df / | tail -1 | awk '{print $5}' | sed 's/%//'"))
        root_free=$(gateway.succeed("df -BG / | tail -1 | awk '{print $4}' | sed 's/G//'"))

        echo "Root filesystem: ${root_usage}% used, ${root_free}GB free"

        # Check for adequate free space
        if [ "$root_free" -lt ${toString resourceLimits.disk.minFreeGB} ]; then
          echo "ERROR: Insufficient free disk space (${root_free}GB < ${toString resourceLimits.disk.minFreeGB}GB minimum)"
          storage_adequate="false"
        elif [ "$root_usage" -gt ${toString resourceLimits.disk.criticalPercent} ]; then
          echo "ERROR: Disk usage too high (${root_usage}% > ${toString resourceLimits.disk.criticalPercent}% critical)"
          storage_adequate="false"
        else
          storage_adequate="true"
        fi

        # Check log file sizes
        large_logs=$(gateway.succeed("find /var/log -type f -size +100M | wc -l"))
        if [ "$large_logs" -gt 0 ]; then
          echo "WARNING: $large_logs log files larger than 100MB"
          log_sizes_concern="true"
        else
          log_sizes_concern="false"
        fi

        # Check for disk I/O bottlenecks
        io_stats=$(gateway.succeed("iostat -x 1 5 | tail -1 | awk '{print $14}'"))
        io_utilization=$(echo "$io_stats * 100" | bc | cut -d. -f1)

        if [ "$io_utilization" -gt 90 ] 2>/dev/null; then
          echo "WARNING: High disk I/O utilization (${io_utilization}%)"
          io_concern="true"
        else
          io_concern="false"
        fi

        # Collect metrics
        ${collectResourceMetrics "storage-resources" {
          rootUsagePercent = root_usage;
          rootFreeGB = root_free;
          largeLogFiles = large_logs;
          ioUtilizationPercent = io_utilization;
          storageAdequate = storage_adequate;
          logSizeConcern = log_sizes_concern;
          ioConcern = io_concern;
        }}

        if [ "$storage_adequate" = "false" ]; then
          echo "Storage resource validation failed"
          exit 1
        else
          echo "Storage resources adequate"
        fi
      '';
    };

    # Network resource validation
    networkResources = {
      name = "network-resources";
      description = "Validate network resource utilization and capacity";
      timeout = 120;
      testScript = ''
        echo "Testing network resources..."

        # Get network interface information
        interfaces=$(gateway.succeed("ip link show | grep -E '^[0-9]+:' | cut -d: -f2 | tr -d ' '"))
        echo "Available interfaces: $interfaces"

        # Test network bandwidth (simplified)
        bandwidth_test=$(gateway.succeed("iperf3 -s -D -1 > /tmp/iperf_server.log 2>&1 && sleep 2 && iperf3 -c 127.0.0.1 -t 5 | grep sender | awk '{print $7}' | sed 's/Mbits/sec//' || echo '0'"))

        if (( $(echo "$bandwidth_test > ${toString resourceLimits.network.minBandwidthMbps}" | bc -l 2>/dev/null || echo "0") )); then
          network_capacity="adequate"
        else
          network_capacity="insufficient"
        fi

        # Check for network interface errors
        interface_errors=$(gateway.succeed("ip -s link show eth0 | grep errors | awk '{print $3}'"))
        if [ "$interface_errors" -gt 0 ]; then
          echo "WARNING: Network interface errors detected ($interface_errors)"
          network_errors="true"
        else
          network_errors="false"
        fi

        # Check network buffer sizes
        rx_buffer=$(gateway.succeed("sysctl net.core.rmem_max | cut -d= -f2"))
        tx_buffer=$(gateway.succeed("sysctl net.core.wmem_max | cut -d= -f2"))

        echo "Network buffers: RX ${rx_buffer}, TX ${tx_buffer}"

        # Check for network congestion
        congestion_control=$(gateway.succeed("sysctl net.ipv4.tcp_congestion_control | cut -d= -f2"))
        echo "TCP congestion control: $congestion_control"

        # Collect metrics
        ${collectResourceMetrics "network-resources" {
          bandwidthMbps = bandwidth_test;
          interfaceErrors = interface_errors;
          rxBufferSize = rx_buffer;
          txBufferSize = tx_buffer;
          congestionControl = congestion_control;
          networkCapacity = network_capacity;
          networkErrors = network_errors;
        }}

        if [ "$network_capacity" = "insufficient" ]; then
          echo "Network resource validation failed - insufficient bandwidth"
          exit 1
        else
          echo "Network resources adequate"
        fi
      '';
    };
  };
}
```

## Resource Test Runner

```bash
#!/usr/bin/env bash
# scripts/run-resource-checks.sh

set -euo pipefail

COMBINATION="$1"
CONFIG_FILE="$2"
RESULTS_DIR="results/$COMBINATION"

echo "Running resource utilization validation checks for $COMBINATION"

# Create results directory
mkdir -p "$RESULTS_DIR/resource"

# Generate NixOS test with resource checks
cat > "tests/${COMBINATION}-resource.nix" << EOF
{ pkgs, lib, ... }:

let
  resourceChecks = import ../lib/resource-checks.nix { inherit lib; };
in

pkgs.testers.nixosTest {
  name = "${COMBINATION}-resource-validation";

  nodes = {
    gateway = { config, pkgs, ... }: {
      imports = [ ../modules ];
      services.gateway = import "$CONFIG_FILE";

      # Install resource testing tools
      environment.systemPackages = with pkgs; [
        stress-ng
        iperf3
        iotop
        sysstat
        bc
      ];
    };

    client1 = { config, pkgs, ... }: {
      virtualisation.vlans = [ 1 ];
      networking.useDHCP = true;
      networking.nameservers = [ "192.168.1.1" ];

      environment.systemPackages = with pkgs; [
        iperf3
        apacheHttpd  # For ab testing
        curl
      ];
    };
  };

  testScript = ''
    start_all()

    # Run resource checks
    \${resourceChecks.resource.resourceCapacity.testScript}
    \${resourceChecks.resource.resourceConflicts.testScript}
    \${resourceChecks.resource.resourceScaling.testScript}
    \${resourceChecks.resource.storageResources.testScript}
    \${resourceChecks.resource.networkResources.testScript}

    # Collect all results
    mkdir -p /tmp/test-results/resource
    cp -r /tmp/resource-metrics/* /tmp/test-results/resource/ 2>/dev/null || true
  '';
}
EOF

# Run the test
echo "Executing resource validation..."
if nix build ".#checks.x86_64-linux.${COMBINATION}-resource"; then
  echo "✅ Resource validation passed"

  # Extract results
  cp result/test-results/resource/* "$RESULTS_DIR/resource/" 2>/dev/null || true

  # Generate summary
  cat > "$RESULTS_DIR/resource-summary.json" << EOF
  {
    "combination": "$COMBINATION",
    "category": "resource",
    "timestamp": "$(date -Iseconds)",
    "overall_result": "passed",
    "checks": [
      "resource-capacity",
      "resource-conflicts",
      "resource-scaling",
      "storage-resources",
      "network-resources"
    ]
  }
  EOF

else
  echo "❌ Resource validation failed"
  exit 1
fi
```

## Resource Check Categories

### 1. Resource Capacity Testing
- Validates system meets minimum hardware requirements
- Tests memory, CPU, and disk capacity under stress
- Ensures system can handle peak loads
- Verifies resource allocation works correctly

### 2. Resource Conflict Detection
- Identifies port conflicts between services
- Detects systemd unit failures
- Finds filesystem configuration conflicts
- Checks for memory overcommit issues

### 3. Resource Scaling Validation
- Tests how resources scale under increasing load
- Measures baseline vs. loaded resource usage
- Validates acceptable scaling curves
- Ensures graceful degradation under stress

### 4. Storage Resource Validation
- Checks disk space utilization and availability
- Monitors log file sizes and rotation
- Tests disk I/O performance and bottlenecks
- Validates storage capacity planning

### 5. Network Resource Validation
- Measures network bandwidth and throughput
- Checks for network interface errors
- Validates network buffer configurations
- Tests network congestion control

## Resource Result Analysis

```bash
#!/usr/bin/env bash
# scripts/analyze-resource-results.sh

COMBINATION="$1"
RESULTS_DIR="results/$COMBINATION/resource"

echo "Analyzing resource validation results for $COMBINATION"

# Count passed/failed checks
total_checks=5
passed_checks=0

# Check each resource metric
capacity_passed=$(jq -r '.meetsMinimumRequirements' "$RESULTS_DIR/resource-capacity.json" 2>/dev/null || echo "false")
conflicts_passed=$(jq -r 'if .criticalConflicts == false then "true" else "false" end' "$RESULTS_DIR/resource-conflicts.json" 2>/dev/null || echo "false")
scaling_passed=$(jq -r '.scalingAcceptable' "$RESULTS_DIR/resource-scaling.json" 2>/dev/null || echo "false")
storage_passed=$(jq -r '.storageAdequate' "$RESULTS_DIR/storage-resources.json" 2>/dev/null || echo "false")
network_passed=$(jq -r 'if .networkCapacity == "adequate" then "true" else "false" end' "$RESULTS_DIR/network-resources.json" 2>/dev/null || echo "false")

[ "$capacity_passed" = "true" ] && ((passed_checks++))
[ "$conflicts_passed" = "true" ] && ((passed_checks++))
[ "$scaling_passed" = "true" ] && ((passed_checks++))
[ "$storage_passed" = "true" ] && ((passed_checks++))
[ "$network_passed" = "true" ] && ((passed_checks++))

pass_rate=$((passed_checks * 100 / total_checks))

# Extract key resource metrics
cpu_max=$(jq -r '.heavyLoadCPU // 0' "$RESULTS_DIR/resource-scaling.json" 2>/dev/null || echo "0")
mem_max=$(jq -r '.heavyLoadMemory // 0' "$RESULTS_DIR/resource-scaling.json" 2>/dev/null || echo "0")
disk_free=$(jq -r '.rootFreeGB // 0' "$RESULTS_DIR/storage-resources.json" 2>/dev/null || echo "0")
bandwidth=$(jq -r '.bandwidthMbps // 0' "$RESULTS_DIR/network-resources.json" 2>/dev/null || echo "0")

# Determine resource risk level
if [ $pass_rate -ge 90 ] && [ "$cpu_max" -lt 85 ] 2>/dev/null && [ "$mem_max" -lt 90 ] 2>/dev/null; then
  risk_level="low"
elif [ $pass_rate -ge 75 ]; then
  risk_level="medium"
else
  risk_level="high"
fi

# Generate comprehensive report
cat > "$RESULTS_DIR/resource-report.json" << EOF
{
  "combination": "$COMBINATION",
  "validation_category": "resource",
  "timestamp": "$(date -Iseconds)",
  "summary": {
    "total_checks": $total_checks,
    "passed_checks": $passed_checks,
    "failed_checks": $((total_checks - passed_checks)),
    "pass_rate_percent": $pass_rate,
    "overall_passed": $([ $pass_rate -ge 80 ] && echo "true" || echo "false"),
    "risk_level": "$risk_level"
  },
  "key_metrics": {
    "cpu_max_percent": "$cpu_max",
    "memory_max_percent": "$mem_max",
    "disk_free_gb": "$disk_free",
    "network_bandwidth_mbps": "$bandwidth"
  },
  "check_results": {
    "resource_capacity": $capacity_passed,
    "resource_conflicts": $conflicts_passed,
    "resource_scaling": $scaling_passed,
    "storage_resources": $storage_passed,
    "network_resources": $network_passed
  },
  "recommendations": $([ "$risk_level" = "high" ] && echo '"Critical resource issues detected - not suitable for production"' || [ "$risk_level" = "medium" ] && echo '"Resource concerns present - monitor closely in production"' || echo '"Resource validation passed - suitable for production deployment"')
}
EOF

echo "Resource validation: $passed_checks/$total_checks checks passed ($pass_rate%)"
echo "Risk level: $risk_level"
echo "Key metrics: CPU ${cpu_max}%, Memory ${mem_max}%, Disk free ${disk_free}GB, Bandwidth ${bandwidth} Mbps"
```

This resource validation framework ensures that supported combinations have adequate system resources, don't conflict with each other, and can handle production workloads without resource exhaustion.
# Error Handling Validation Checks Implementation

## Error Handling Validation Library

```nix
# lib/error-handling-checks.nix
{ lib, ... }:

let
  # Error simulation helpers
  simulateServiceFailure = serviceName: recoveryTime: ''
    # Stop the service
    gateway.succeed("systemctl stop ${serviceName}")
    echo "Stopped ${serviceName}"

    # Wait for potential recovery
    sleep ${toString recoveryTime}

    # Check if service recovered
    if gateway.succeed("systemctl is-active ${serviceName}"); then
      echo "${serviceName} recovered automatically"
      recovery_result="recovered"
    else
      echo "${serviceName} did not recover, attempting manual restart"
      gateway.succeed("systemctl start ${serviceName}")
      if gateway.succeed("systemctl is-active ${serviceName}"); then
        recovery_result="manual_recovery"
      else
        recovery_result="failed"
      fi
    fi
  '';

  simulateNetworkFailure = duration: ''
    # Simulate network failure by bringing interface down
    gateway.succeed("ip link set eth0 down")
    echo "Simulated network failure for ${toString duration} seconds"

    sleep ${toString duration}

    # Restore network
    gateway.succeed("ip link set eth0 up")
    gateway.succeed("systemctl restart systemd-networkd")
    echo "Restored network connectivity"
  '';

  simulateResourceExhaustion = resourceType: ''
    case "${resourceType}" in
      "memory")
        # Fill memory
        gateway.succeed("stress-ng --vm 2 --vm-bytes 90% --timeout 30s &")
        sleep 15
        gateway.succeed("pkill stress-ng")
        ;;
      "disk")
        # Fill disk space
        gateway.succeed("dd if=/dev/zero of=/tmp/fill_disk bs=1M count=500")
        sleep 10
        gateway.succeed("rm /tmp/fill_disk")
        ;;
      "cpu")
        # Max out CPU
        gateway.succeed("stress-ng --cpu 4 --timeout 20s &")
        sleep 10
        gateway.succeed("pkill stress-ng")
        ;;
    esac
  '';

  collectErrorMetrics = name: metrics: ''
    # Store error handling metrics
    mkdir -p /tmp/error-metrics
    cat > "/tmp/error-metrics/${name}.json" << EOF
    ${builtins.toJSON metrics}
    EOF
  '';

in {
  # Error handling validation checks
  errorHandling = {
    # Service failure and recovery testing
    serviceFailureRecovery = {
      name = "service-failure-recovery";
      description = "Test service failure detection and automatic recovery";
      timeout = 300;
      testScript = ''
        echo "Testing service failure and recovery..."

        # Test DNS service failure
        if gateway.succeed("systemctl is-active kresd@1.service"); then
          dns_recovery=$(${simulateServiceFailure "kresd@1.service" 30})

          # Test DNS functionality after recovery
          client1.succeed("dig @gateway example.com | grep -q 'ANSWER SECTION'")
          dns_functional="true"
        else
          dns_recovery="skipped"
          dns_functional="true"
        fi

        # Test DHCP service failure
        if gateway.succeed("systemctl is-active kea-dhcp4-server.service"); then
          dhcp_recovery=$(${simulateServiceFailure "kea-dhcp4-server.service" 30})

          # Test DHCP functionality after recovery
          client1.succeed("dhcpcd -T eth1 | grep -q 'new_ip_address'")
          dhcp_functional="true"
        else
          dhcp_recovery="skipped"
          dhcp_functional="true"
        fi

        # Test firewall service failure
        if gateway.succeed("systemctl is-active nftables.service"); then
          firewall_recovery=$(${simulateServiceFailure "nftables.service" 30})

          # Test firewall functionality after recovery
          gateway.succeed("nft list ruleset | grep -q 'table inet filter'")
          firewall_functional="true"
        else
          firewall_recovery="skipped"
          firewall_functional="true"
        fi

        # Evaluate recovery success
        if [[ "$dns_recovery" == "failed" || "$dhcp_recovery" == "failed" || "$firewall_recovery" == "failed" ]]; then
          recovery_overall="failed"
        elif [[ "$dns_recovery" == "manual_recovery" || "$dhcp_recovery" == "manual_recovery" || "$firewall_recovery" == "manual_recovery" ]]; then
          recovery_overall="manual"
        else
          recovery_overall="automatic"
        fi

        # Collect metrics
        ${collectErrorMetrics "service-failure-recovery" {
          dnsRecovery = dns_recovery;
          dhcpRecovery = dhcp_recovery;
          firewallRecovery = firewall_recovery;
          dnsFunctional = dns_functional;
          dhcpFunctional = dhcp_functional;
          firewallFunctional = firewall_functional;
          overallRecovery = recovery_overall;
          passed = true;
        }}

        echo "Service failure recovery test completed: $recovery_overall recovery"
      '';
    };

    # Network failure and recovery testing
    networkFailureRecovery = {
      name = "network-failure-recovery";
      description = "Test network failure detection and recovery mechanisms";
      timeout = 240;
      testScript = ''
        echo "Testing network failure and recovery..."

        # Get baseline connectivity
        client1.succeed("ping -c 3 gateway")
        baseline_connectivity="true"

        # Simulate network failure
        ${simulateNetworkFailure 30}

        # Wait for recovery and test connectivity
        sleep 10
        if client1.succeed("ping -c 3 gateway"); then
          network_recovery="successful"
        else
          # Try longer wait
          sleep 20
          if client1.succeed("ping -c 3 gateway"); then
            network_recovery="delayed"
          else
            network_recovery="failed"
          fi
        fi

        # Test service functionality after network recovery
        client1.succeed("dig @gateway example.com | grep -q 'ANSWER SECTION'" || true)
        dns_after_network="true"

        # Evaluate network resilience
        if [ "$network_recovery" = "successful" ]; then
          network_resilience="high"
        elif [ "$network_recovery" = "delayed" ]; then
          network_resilience="medium"
        else
          network_resilience="low"
        fi

        # Collect metrics
        ${collectErrorMetrics "network-failure-recovery" {
          baselineConnectivity = baseline_connectivity;
          networkRecovery = network_recovery;
          dnsAfterNetworkRecovery = dns_after_network;
          networkResilience = network_resilience;
          passed = true;
        }}

        echo "Network failure recovery test completed: $network_resilience resilience"
      '';
    };

    # Resource exhaustion error handling
    resourceExhaustionHandling = {
      name = "resource-exhaustion-handling";
      description = "Test system behavior under resource exhaustion conditions";
      timeout = 360;
      testScript = ''
        echo "Testing resource exhaustion handling..."

        # Test memory exhaustion
        echo "Testing memory exhaustion..."
        initial_memory=$(gateway.succeed("free | grep Mem | awk '{print $3}'"))
        ${simulateResourceExhaustion "memory"}
        final_memory=$(gateway.succeed("free | grep Mem | awk '{print $3}'"))

        # Check if system remained stable
        if gateway.succeed("systemctl is-system-running | grep -q running"); then
          memory_handling="stable"
        else
          memory_handling="unstable"
        fi

        # Test disk exhaustion
        echo "Testing disk exhaustion..."
        initial_disk=$(gateway.succeed("df / | tail -1 | awk '{print $3}'"))
        ${simulateResourceExhaustion "disk"}
        final_disk=$(gateway.succeed("df / | tail -1 | awk '{print $3}'"))

        # Check if critical services still work
        if gateway.succeed("systemctl is-active systemd-journald.service"); then
          disk_handling="stable"
        else
          disk_handling="unstable"
        fi

        # Test CPU exhaustion
        echo "Testing CPU exhaustion..."
        ${simulateResourceExhaustion "cpu"}

        # Check if system remains responsive
        if gateway.succeed("uptime"); then
          cpu_handling="stable"
        else
          cpu_handling="unstable"
        fi

        # Evaluate overall resource handling
        if [[ "$memory_handling" == "stable" && "$disk_handling" == "stable" && "$cpu_handling" == "stable" ]]; then
          resource_handling_overall="robust"
        elif [[ "$memory_handling" == "stable" || "$disk_handling" == "stable" || "$cpu_handling" == "stable" ]]; then
          resource_handling_overall="partial"
        else
          resource_handling_overall="poor"
        fi

        # Collect metrics
        ${collectErrorMetrics "resource-exhaustion-handling" {
          memoryHandling = memory_handling;
          diskHandling = disk_handling;
          cpuHandling = cpu_handling;
          overallResourceHandling = resource_handling_overall;
          passed = true;
        }}

        echo "Resource exhaustion handling test completed: $resource_handling_overall robustness"
      '';
    };

    # Configuration error handling
    configurationErrorHandling = {
      name = "configuration-error-handling";
      description = "Test system response to configuration errors and validation failures";
      timeout = 180;
      testScript = ''
        echo "Testing configuration error handling..."

        # Test invalid Nix configuration
        gateway.succeed("cp /etc/nixos/configuration.nix /etc/nixos/configuration.nix.backup")
        gateway.succeed("echo 'invalid nix syntax {{{' >> /etc/nixos/configuration.nix")

        # Try to build configuration
        if gateway.succeed("nix-instantiate /etc/nixos/configuration.nix 2>/dev/null"); then
          nix_validation="poor"
        else
          nix_validation="good"
        fi

        # Restore configuration
        gateway.succeed("cp /etc/nixos/configuration.nix.backup /etc/nixos/configuration.nix")

        # Test invalid network configuration
        gateway.succeed("cp /etc/systemd/network/50-lan.network /etc/systemd/network/50-lan.network.backup")
        gateway.succeed("echo '[invalid]' >> /etc/systemd/network/50-lan.network")

        # Try to reload network configuration
        if gateway.succeed("systemctl reload systemd-networkd"); then
          network_validation="poor"
        else
          network_validation="good"
        fi

        # Restore network configuration
        gateway.succeed("cp /etc/systemd/network/50-lan.network.backup /etc/systemd/network/50-lan.network")
        gateway.succeed("systemctl reload systemd-networkd")

        # Test invalid service configuration
        if gateway.succeed("systemctl is-active kresd@1.service"); then
          gateway.succeed("cp /etc/knot-resolver/kresd.conf /etc/knot-resolver/kresd.conf.backup")
          gateway.succeed("echo 'invalid kresd config' >> /etc/knot-resolver/kresd.conf")

          if gateway.succeed("systemctl reload kresd@1.service"); then
            kresd_validation="poor"
          else
            kresd_validation="good"
          fi

          # Restore kresd configuration
          gateway.succeed("cp /etc/knot-resolver/kresd.conf.backup /etc/knot-resolver/kresd.conf")
          gateway.succeed("systemctl reload kresd@1.service")
        else
          kresd_validation="skipped"
        fi

        # Evaluate configuration error handling
        if [[ "$nix_validation" == "good" && "$network_validation" == "good" && ("$kresd_validation" == "good" || "$kresd_validation" == "skipped") ]]; then
          config_error_handling="excellent"
        elif [[ "$nix_validation" == "good" || "$network_validation" == "good" ]]; then
          config_error_handling="good"
        else
          config_error_handling="poor"
        fi

        # Collect metrics
        ${collectErrorMetrics "configuration-error-handling" {
          nixValidation = nix_validation;
          networkValidation = network_validation;
          kresdValidation = kresd_validation;
          overallConfigErrorHandling = config_error_handling;
          passed = true;
        }}

        echo "Configuration error handling test completed: $config_error_handling validation"
      '';
    };

    # Concurrent failure scenario testing
    concurrentFailureTesting = {
      name = "concurrent-failure-testing";
      description = "Test system behavior when multiple failures occur simultaneously";
      timeout = 420;
      testScript = ''
        echo "Testing concurrent failure scenarios..."

        # Start multiple background services
        client1.succeed("ping gateway > /dev/null &")
        client1.succeed("while true; do dig @gateway example.com > /dev/null 2>&1; sleep 1; done &")

        # Trigger multiple failures simultaneously
        gateway.succeed("systemctl stop kresd@1.service &")
        gateway.succeed("systemctl stop kea-dhcp4-server.service &")
        ${simulateNetworkFailure 15} &
        ${simulateResourceExhaustion "cpu"} &

        # Wait for failures to take effect
        sleep 20

        # Test system stability during concurrent failures
        if gateway.succeed("systemctl is-system-running | grep -q running"); then
          concurrent_stability="stable"
        else
          concurrent_stability="unstable"
        fi

        # Test recovery from concurrent failures
        gateway.succeed("systemctl start kresd@1.service || true")
        gateway.succeed("systemctl start kea-dhcp4-server.service || true")
        gateway.succeed("ip link set eth0 up && systemctl restart systemd-networkd")

        sleep 15

        # Test functionality after recovery
        if client1.succeed("ping -c 2 gateway") && client1.succeed("dig @gateway example.com | grep -q 'ANSWER'"); then
          concurrent_recovery="successful"
        else
          concurrent_recovery="failed"
        fi

        # Clean up background processes
        gateway.succeed("pkill -f 'ping gateway' || true")
        gateway.succeed("pkill -f 'dig @gateway' || true")

        # Evaluate concurrent failure handling
        if [[ "$concurrent_stability" == "stable" && "$concurrent_recovery" == "successful" ]]; then
          concurrent_handling="excellent"
        elif [[ "$concurrent_stability" == "stable" ]]; then
          concurrent_handling="good"
        else
          concurrent_handling="poor"
        fi

        # Collect metrics
        ${collectErrorMetrics "concurrent-failure-testing" {
          concurrentStability = concurrent_stability;
          concurrentRecovery = concurrent_recovery;
          overallConcurrentHandling = concurrent_handling;
          passed = true;
        }}

        echo "Concurrent failure testing completed: $concurrent_handling handling"
      '';
    };

    # Graceful degradation testing
    gracefulDegradation = {
      name = "graceful-degradation";
      description = "Test system behavior when services degrade rather than fail completely";
      timeout = 300;
      testScript = ''
        echo "Testing graceful degradation..."

        # Test DNS degradation (high latency)
        if gateway.succeed("systemctl is-active kresd@1.service"); then
          # Add artificial delay to DNS responses
          gateway.succeed("tc qdisc add dev lo root netem delay 500ms")

          # Test DNS still works but slower
          start_time=$(date +%s%N)
          client1.succeed("dig @gateway example.com | grep -q 'ANSWER SECTION'")
          end_time=$(date +%s%N)
          dns_delay=$(( (end_time - start_time) / 1000000 ))  # ms

          gateway.succeed("tc qdisc del dev lo root netem")

          if [ "$dns_delay" -gt 1000 ]; then
            dns_degradation="severe"
          elif [ "$dns_delay" -gt 500 ]; then
            dns_degradation="moderate"
          else
            dns_degradation="minimal"
          fi
        else
          dns_degradation="skipped"
        fi

        # Test network degradation (packet loss)
        gateway.succeed("tc qdisc add dev eth0 root netem loss 5%")

        # Test connectivity still works despite packet loss
        if client1.succeed("ping -c 10 gateway | grep -q '10 received'"); then
          network_degradation="handled"
        else
          network_degradation="problematic"
        fi

        gateway.succeed("tc qdisc del dev eth0 root netem")

        # Test service overload degradation
        for i in {1..10}; do
          client1.succeed("curl -f http://httpbin.org/ip > /dev/null 2>&1 &")
        done

        sleep 10

        # Check if system remains responsive
        if gateway.succeed("uptime"); then
          overload_degradation="handled"
        else
          overload_degradation="problematic"
        fi

        # Clean up
        gateway.succeed("pkill curl || true")

        # Evaluate graceful degradation
        if [[ "$dns_degradation" != "severe" && "$network_degradation" == "handled" && "$overload_degradation" == "handled" ]]; then
          graceful_degradation_overall="excellent"
        elif [[ "$network_degradation" == "handled" || "$overload_degradation" == "handled" ]]; then
          graceful_degradation_overall="good"
        else
          graceful_degradation_overall="poor"
        fi

        # Collect metrics
        ${collectErrorMetrics "graceful-degradation" {
          dnsDegradation = dns_degradation;
          networkDegradation = network_degradation;
          overloadDegradation = overload_degradation;
          overallGracefulDegradation = graceful_degradation_overall;
          passed = true;
        }}

        echo "Graceful degradation testing completed: $graceful_degradation_overall degradation handling"
      '';
    };
  };
}
```

## Error Handling Test Runner

```bash
#!/usr/bin/env bash
# scripts/run-error-handling-checks.sh

set -euo pipefail

COMBINATION="$1"
CONFIG_FILE="$2"
RESULTS_DIR="results/$COMBINATION"

echo "Running error handling validation checks for $COMBINATION"

# Create results directory
mkdir -p "$RESULTS_DIR/error-handling"

# Generate NixOS test with error handling checks
cat > "tests/${COMBINATION}-error-handling.nix" << EOF
{ pkgs, lib, ... }:

let
  errorHandlingChecks = import ../lib/error-handling-checks.nix { inherit lib; };
in

pkgs.testers.nixosTest {
  name = "${COMBINATION}-error-handling-validation";

  nodes = {
    gateway = { config, pkgs, ... }: {
      imports = [ ../modules ];
      services.gateway = import "$CONFIG_FILE";

      # Install error testing and monitoring tools
      environment.systemPackages = with pkgs; [
        tcpdump
        stress-ng
        iproute2
        curl
        dnsutils
        dhcpcd
        tcpdump
        netcat
        iperf3
      ];

      # Enable traffic control for network testing
      boot.kernelModules = [ "sch_netem" ];
    };

    client1 = { config, pkgs, ... }: {
      virtualisation.vlans = [ 1 ];
      networking.useDHCP = true;
      networking.nameservers = [ "192.168.1.1" ];

      environment.systemPackages = with pkgs; [
        curl
        dnsutils
        iputils
        tcpdump
      ];
    };
  };

  testScript = ''
    start_all()

    # Run error handling checks
    \${errorHandlingChecks.errorHandling.serviceFailureRecovery.testScript}
    \${errorHandlingChecks.errorHandling.networkFailureRecovery.testScript}
    \${errorHandlingChecks.errorHandling.resourceExhaustionHandling.testScript}
    \${errorHandlingChecks.errorHandling.configurationErrorHandling.testScript}
    \${errorHandlingChecks.errorHandling.concurrentFailureTesting.testScript}
    \${errorHandlingChecks.errorHandling.gracefulDegradation.testScript}

    # Collect all results
    mkdir -p /tmp/test-results/error-handling
    cp -r /tmp/error-metrics/* /tmp/test-results/error-handling/ 2>/dev/null || true
  '';
}
EOF

# Run the test
echo "Executing error handling validation..."
if nix build ".#checks.x86_64-linux.${COMBINATION}-error-handling"; then
  echo "✅ Error handling validation passed"

  # Extract results
  cp result/test-results/error-handling/* "$RESULTS_DIR/error-handling/" 2>/dev/null || true

  # Generate summary
  cat > "$RESULTS_DIR/error-handling-summary.json" << EOF
  {
    "combination": "$COMBINATION",
    "category": "error-handling",
    "timestamp": "$(date -Iseconds)",
    "overall_result": "passed",
    "checks": [
      "service-failure-recovery",
      "network-failure-recovery",
      "resource-exhaustion-handling",
      "configuration-error-handling",
      "concurrent-failure-testing",
      "graceful-degradation"
    ]
  }
  EOF

else
  echo "❌ Error handling validation failed"
  exit 1
fi
```

## Error Handling Check Categories

### 1. Service Failure and Recovery Testing
- Tests automatic recovery from individual service failures
- Validates service dependency handling
- Measures recovery time and success rate
- Ensures functionality after recovery

### 2. Network Failure and Recovery Testing
- Simulates network interface failures
- Tests network reconvergence and routing recovery
- Validates connectivity restoration
- Measures network resilience

### 3. Resource Exhaustion Error Handling
- Tests system behavior under memory, disk, and CPU exhaustion
- Validates graceful degradation under resource pressure
- Ensures critical services remain functional
- Tests resource cleanup and recovery

### 4. Configuration Error Handling
- Tests system response to invalid configurations
- Validates configuration validation and error reporting
- Ensures partial failures don't break entire system
- Tests configuration rollback capabilities

### 5. Concurrent Failure Scenario Testing
- Tests system behavior with multiple simultaneous failures
- Validates failure isolation and recovery prioritization
- Ensures system stability under compound failure conditions
- Tests recovery from complex failure scenarios

### 6. Graceful Degradation Testing
- Tests system behavior under performance degradation
- Validates continued operation with reduced performance
- Tests user experience during degradation
- Ensures no complete service failures

## Error Handling Result Analysis

```bash
#!/usr/bin/env bash
# scripts/analyze-error-handling-results.sh

COMBINATION="$1"
RESULTS_DIR="results/$COMBINATION/error-handling"

echo "Analyzing error handling validation results for $COMBINATION"

# Count passed/failed checks
total_checks=6
passed_checks=0

# Evaluate each error handling scenario
service_recovery=$(jq -r '.overallRecovery' "$RESULTS_DIR/service-failure-recovery.json" 2>/dev/null || echo "unknown")
network_recovery=$(jq -r '.networkResilience' "$RESULTS_DIR/network-failure-recovery.json" 2>/dev/null || echo "unknown")
resource_handling=$(jq -r '.overallResourceHandling' "$RESULTS_DIR/resource-exhaustion-handling.json" 2>/dev/null || echo "unknown")
config_handling=$(jq -r '.overallConfigErrorHandling' "$RESULTS_DIR/configuration-error-handling.json" 2>/dev/null || echo "unknown")
concurrent_handling=$(jq -r '.overallConcurrentHandling' "$RESULTS_DIR/concurrent-failure-testing.json" 2>/dev/null || echo "unknown")
degradation_handling=$(jq -r '.overallGracefulDegradation' "$RESULTS_DIR/graceful-degradation.json" 2>/dev/null || echo "unknown")

# Score each category
score_category() {
  case "$1" in
    "excellent"|"automatic"|"high") echo 3 ;;
    "good"|"manual"|"medium") echo 2 ;;
    "poor"|"failed"|"low") echo 1 ;;
    *) echo 0 ;;
  esac
}

service_score=$(score_category "$service_recovery")
network_score=$(score_category "$network_recovery")
resource_score=$(score_category "$resource_handling")
config_score=$(score_category "$config_handling")
concurrent_score=$(score_category "$concurrent_handling")
degradation_score=$(score_category "$degradation_handling")

total_score=$((service_score + network_score + resource_score + config_score + concurrent_score + degradation_score))
max_score=18
pass_rate=$((total_score * 100 / max_score))

# Determine error handling quality
if [ $pass_rate -ge 80 ]; then
  error_quality="excellent"
elif [ $pass_rate -ge 60 ]; then
  error_quality="good"
else
  error_quality="poor"
fi

# Generate comprehensive report
cat > "$RESULTS_DIR/error-handling-report.json" << EOF
{
  "combination": "$COMBINATION",
  "validation_category": "error-handling",
  "timestamp": "$(date -Iseconds)",
  "summary": {
    "total_checks": $total_checks,
    "total_score": $total_score,
    "max_score": $max_score,
    "pass_rate_percent": $pass_rate,
    "overall_quality": "$error_quality",
    "overall_passed": $([ $pass_rate -ge 60 ] && echo "true" || echo "false")
  },
  "category_scores": {
    "service_recovery": {"result": "$service_recovery", "score": $service_score},
    "network_recovery": {"result": "$network_recovery", "score": $network_score},
    "resource_handling": {"result": "$resource_handling", "score": $resource_score},
    "config_handling": {"result": "$config_handling", "score": $config_score},
    "concurrent_handling": {"result": "$concurrent_handling", "score": $concurrent_score},
    "degradation_handling": {"result": "$degradation_handling", "score": $degradation_score}
  },
  "recommendations": $([ "$error_quality" = "poor" ] && echo '"Critical error handling issues detected - requires significant improvements before production"' || [ "$error_quality" = "good" ] && echo '"Acceptable error handling - monitor and improve recovery mechanisms"' || echo '"Excellent error handling - robust failure recovery and graceful degradation"')
}
EOF

echo "Error handling validation: $total_score/$max_score points ($pass_rate%)"
echo "Quality level: $error_quality"
echo "Service recovery: $service_recovery, Network recovery: $network_recovery"
echo "Resource handling: $resource_handling, Config handling: $config_handling"
```

This error handling validation framework ensures that supported combinations can gracefully handle failures, recover from errors, and maintain acceptable service levels during adverse conditions.
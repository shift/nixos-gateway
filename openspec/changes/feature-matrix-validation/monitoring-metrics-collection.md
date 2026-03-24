# Monitoring and Metrics Collection Implementation

## Comprehensive Monitoring Framework

```nix
# lib/monitoring-framework.nix
{ lib, ... }:

let
  # Metrics collection helpers
  collectSystemMetrics = interval: ''
    # Create metrics directory
    mkdir -p /tmp/system-metrics

    # Collect CPU metrics
    cat > /tmp/system-metrics/cpu.json << EOF
    {
      "timestamp": "$(date +%s)",
      "cpu": {
        "usage_percent": $(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print $1}'),
        "user_percent": $(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print $2}'),
        "system_percent": $(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print $4}'),
        "idle_percent": $(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print $8}')
      }
    }
    EOF

    # Collect memory metrics
    cat > /tmp/system-metrics/memory.json << EOF
    {
      "timestamp": "$(date +%s)",
      "memory": {
        "total_kb": $(free | grep Mem | awk '{print $2}'),
        "used_kb": $(free | grep Mem | awk '{print $3}'),
        "free_kb": $(free | grep Mem | awk '{print $4}'),
        "buffers_kb": $(free | grep Mem | awk '{print $6}'),
        "cached_kb": $(free | grep Mem | awk '{print $7}'),
        "usage_percent": $(free | grep Mem | awk '{printf "%.2f", $3/$2 * 100.0}')
      }
    }
    EOF

    # Collect disk metrics
    cat > /tmp/system-metrics/disk.json << EOF
    {
      "timestamp": "$(date +%s)",
      "disk": {
        "root_total_kb": $(df / | tail -1 | awk '{print $2}'),
        "root_used_kb": $(df / | tail -1 | awk '{print $3}'),
        "root_available_kb": $(df / | tail -1 | awk '{print $4}'),
        "root_usage_percent": $(df / | tail -1 | awk '{print $5}' | sed 's/%//')
      }
    }
    EOF

    # Collect network metrics
    cat > /tmp/system-metrics/network.json << EOF
    {
      "timestamp": "$(date +%s)",
      "network": {
        "interfaces": $(ip -j addr show | jq -c '[.[] | {name: .ifname, state: .operstate, address: .addr_info[0].local}]')
      }
    }
    EOF
  '';

  # Service health monitoring
  monitorServiceHealth = services: lib.concatMapStrings (service: ''
    # Check service status
    if systemctl is-active ${service} > /dev/null 2>&1; then
      service_status="active"
      service_pid=$(systemctl show ${service} -p MainPID | cut -d= -f2)
      service_memory=$(ps -o rss= -p $service_pid 2>/dev/null || echo "0")
    else
      service_status="inactive"
      service_pid="0"
      service_memory="0"
    fi

    # Record service health
    cat >> /tmp/service-health.json << EOF
    {
      "service": "${service}",
      "timestamp": "$(date +%s)",
      "status": "$service_status",
      "pid": "$service_pid",
      "memory_kb": "$service_memory"
    }
    EOF
  '') services;

  # Application-specific metrics
  collectApplicationMetrics = apps: lib.concatMapStrings (app: ''
    case "${app}" in
      "dnsmasq")
        # DNS-specific metrics
        dns_queries=$(journalctl -u dnsmasq --since "1 minute ago" | grep -c "query" || echo "0")
        dns_cache_hits=$(journalctl -u dnsmasq --since "1 minute ago" | grep -c "cache" || echo "0")

        cat > /tmp/app-metrics/dnsmasq.json << EOF
        {
          "timestamp": "$(date +%s)",
          "queries_per_minute": $dns_queries,
          "cache_hits_per_minute": $dns_cache_hits
        }
        EOF
        ;;

      "kresd")
        # Knot Resolver metrics
        kresd_queries=$(journalctl -u kresd@1 --since "1 minute ago" | grep -c "answer" || echo "0")

        cat > /tmp/app-metrics/kresd.json << EOF
        {
          "timestamp": "$(date +%s)",
          "queries_per_minute": $kresd_queries
        }
        EOF
        ;;

      "kea-dhcp4")
        # Kea DHCP metrics
        dhcp_leases=$(journalctl -u kea-dhcp4-server --since "1 minute ago" | grep -c "lease" || echo "0")

        cat > /tmp/app-metrics/kea-dhcp4.json << EOF
        {
          "timestamp": "$(date +%s)",
          "leases_per_minute": $dhcp_leases
        }
        EOF
        ;;

      "prometheus")
        # Prometheus metrics
        prometheus_targets=$(curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets | length' 2>/dev/null || echo "0")

        cat > /tmp/app-metrics/prometheus.json << EOF
        {
          "timestamp": "$(date +%s)",
          "active_targets": $prometheus_targets
        }
        EOF
        ;;
    esac
  '') apps;

in {
  # Monitoring configurations
  monitoring = {
    # System monitoring setup
    systemMonitoring = {
      enable = true;
      interval = 10;  # seconds
      metrics = [
        "cpu"
        "memory"
        "disk"
        "network"
      ];
      retention = 3600;  # 1 hour
    };

    # Service monitoring setup
    serviceMonitoring = services: {
      enable = true;
      services = services;
      healthChecks = true;
      logMonitoring = true;
    };

    # Application monitoring setup
    applicationMonitoring = apps: {
      enable = true;
      applications = apps;
      customMetrics = true;
    };

    # Network monitoring setup
    networkMonitoring = {
      enable = true;
      interfaces = ["eth0" "vlan1"];
      protocols = ["tcp" "udp" "icmp"];
      trafficAnalysis = true;
    };

    # Log monitoring setup
    logMonitoring = {
      enable = true;
      journals = ["system" "gateway"];
      errorTracking = true;
      performanceTracking = true;
    };
  };

  # Metrics collection functions
  collectors = {
    # Start comprehensive monitoring
    startMonitoring = config: ''
      # Create monitoring directories
      mkdir -p /tmp/system-metrics /tmp/service-health /tmp/app-metrics /tmp/network-metrics /tmp/logs

      # Start system metrics collection
      if [ "${config.monitoring.systemMonitoring.enable}" = "true" ]; then
        while true; do
          ${collectSystemMetrics config.monitoring.systemMonitoring.interval}
          sleep ${toString config.monitoring.systemMonitoring.interval}
        done &
        echo $! > /tmp/monitoring-pids
      fi

      # Start service health monitoring
      if [ "${config.monitoring.serviceMonitoring.enable}" = "true" ]; then
        while true; do
          ${monitorServiceHealth config.monitoring.serviceMonitoring.services}
          sleep 30
        done &
        echo $! >> /tmp/monitoring-pids
      fi

      # Start application metrics collection
      if [ "${config.monitoring.applicationMonitoring.enable}" = "true" ]; then
        while true; do
          ${collectApplicationMetrics config.monitoring.applicationMonitoring.applications}
          sleep 60
        done &
        echo $! >> /tmp/monitoring-pids
      fi

      # Start log monitoring
      if [ "${config.monitoring.logMonitoring.enable}" = "true" ]; then
        journalctl -f -n 0 >> /tmp/logs/combined.log &
        echo $! >> /tmp/monitoring-pids
      fi

      echo "Monitoring started with PIDs: $(cat /tmp/monitoring-pids)"
    '';

    # Stop monitoring and collect final metrics
    stopMonitoring = ''
      # Stop monitoring processes
      if [ -f /tmp/monitoring-pids ]; then
        for pid in $(cat /tmp/monitoring-pids); do
          kill $pid 2>/dev/null || true
        done
        rm -f /tmp/monitoring-pids
      fi

      # Collect final metrics
      ${collectSystemMetrics 1}

      # Compress log files
      if [ -d /tmp/logs ]; then
        gzip /tmp/logs/*.log 2>/dev/null || true
      fi

      echo "Monitoring stopped and final metrics collected"
    '';

    # Export metrics for analysis
    exportMetrics = ''
      # Create metrics archive
      mkdir -p /tmp/metrics-export
      cp -r /tmp/system-metrics/* /tmp/metrics-export/ 2>/dev/null || true
      cp -r /tmp/service-health/* /tmp/metrics-export/ 2>/dev/null || true
      cp -r /tmp/app-metrics/* /tmp/metrics-export/ 2>/dev/null || true
      cp -r /tmp/network-metrics/* /tmp/metrics-export/ 2>/dev/null || true
      cp -r /tmp/logs/* /tmp/metrics-export/ 2>/dev/null || true

      # Create summary
      cat > /tmp/metrics-export/summary.json << EOF
      {
        "export_timestamp": "$(date +%s)",
        "system_metrics_count": $(find /tmp/system-metrics -name "*.json" | wc -l),
        "service_health_count": $(find /tmp/service-health -name "*.json" | wc -l),
        "app_metrics_count": $(find /tmp/app-metrics -name "*.json" | wc -l),
        "network_metrics_count": $(find /tmp/network-metrics -name "*.json" | wc -l),
        "log_files_count": $(find /tmp/logs -name "*.gz" | wc -l)
      }
      EOF

      echo "Metrics exported to /tmp/metrics-export"
    '';
  };
}
```

## Monitoring Integration Test

```bash
#!/usr/bin/env bash
# scripts/test-monitoring-integration.sh

COMBINATION="$1"

echo "Testing monitoring integration for $COMBINATION"

# Generate monitoring integration test
cat > "tests/${COMBINATION}-monitoring-integration.nix" << EOF
{ pkgs, lib, ... }:

let
  monitoringFramework = import ../lib/monitoring-framework.nix { inherit lib; };

in

pkgs.testers.nixosTest {
  name = "${COMBINATION}-monitoring-integration";

  nodes = {
    gateway = { config, pkgs, ... }: {
      imports = [ ../modules ];
      services.gateway = import "test-configs/${COMBINATION}.nix";

      # Enable comprehensive monitoring
      services.prometheus.enable = true;
      services.prometheus.exporters.node.enable = true;
      services.prometheus.exporters.node.port = 9100;

      # Install monitoring tools
      environment.systemPackages = with pkgs; [
        prometheus
        curl
        jq
        sysstat
        htop
      ];

      # Setup monitoring framework
      systemd.services.monitoring-setup = {
        description = "Setup comprehensive monitoring";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          \${monitoringFramework.collectors.startMonitoring {
            monitoring = monitoringFramework.monitoring // {
              systemMonitoring = monitoringFramework.monitoring.systemMonitoring // {
                enable = true;
                interval = 5;
              };
              serviceMonitoring = monitoringFramework.monitoring.serviceMonitoring [
                "kresd@1"
                "kea-dhcp4-server"
                "nftables"
              ];
              applicationMonitoring = monitoringFramework.monitoring.applicationMonitoring [
                "kresd"
                "kea-dhcp4"
              ];
              logMonitoring = monitoringFramework.monitoring.logMonitoring // {
                enable = true;
              };
            };
          }}
        '';
      };

      systemd.services.monitoring-teardown = {
        description = "Stop monitoring and export metrics";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          \${monitoringFramework.collectors.stopMonitoring}
          \${monitoringFramework.collectors.exportMetrics}
        '';
      };
    };

    client1 = { config, pkgs, ... }: {
      virtualisation.vlans = [ 1 ];
      networking.useDHCP = true;

      environment.systemPackages = with pkgs; [
        curl
        dnsutils
      ];
    };
  };

  testScript = ''
    start_all()

    # Test monitoring setup
    with subtest("Monitoring infrastructure is properly configured"):
        # Check Prometheus is running
        gateway.succeed("systemctl is-active prometheus.service")

        # Check node exporter is running
        gateway.succeed("systemctl is-active prometheus-node-exporter.service")

        # Check monitoring directories exist
        gateway.succeed("test -d /tmp/system-metrics")
        gateway.succeed("test -d /tmp/service-health")
        gateway.succeed("test -d /tmp/app-metrics")

    # Generate some system activity to monitor
    with subtest("System activity generates monitoring data"):
        # Generate DNS queries
        client1.succeed("for i in {1..5}; do dig @gateway example.com > /dev/null; done")

        # Generate some CPU load
        gateway.succeed("stress-ng --cpu 1 --timeout 10s")

        # Wait for metrics collection
        sleep 15

        # Check metrics were collected
        gateway.succeed("find /tmp/system-metrics -name '*.json' | wc -l | grep -q '[1-9]'")
        gateway.succeed("find /tmp/service-health -name '*.json' | wc -l | grep -q '[1-9]'")

    # Test metrics quality
    with subtest("Metrics data is valid and comprehensive"):
        # Check system metrics structure
        gateway.succeed("jq -r '.cpu.usage_percent' /tmp/system-metrics/cpu.json | grep -q '[0-9]'")
        gateway.succeed("jq -r '.memory.usage_percent' /tmp/system-metrics/memory.json | grep -q '[0-9]'")

        # Check service health data
        gateway.succeed("jq -r '.status' /tmp/service-health.json | grep -q 'active\\|inactive'")

        # Check application metrics
        gateway.succeed("test -f /tmp/app-metrics/kresd.json && jq -r '.queries_per_minute' /tmp/app-metrics/kresd.json | grep -q '[0-9]'")

    # Test Prometheus integration
    with subtest("Prometheus collects metrics correctly"):
        # Query Prometheus for node metrics
        metrics_result = gateway.succeed("curl -s 'http://localhost:9090/api/v1/query?query=up'")
        gateway.succeed("echo '$metrics_result' | jq -r '.status' | grep -q 'success'")

        # Check specific metrics
        cpu_metrics = gateway.succeed("curl -s 'http://localhost:9090/api/v1/query?query=node_cpu_seconds_total'")
        gateway.succeed("echo '$cpu_metrics' | jq -r '.data.result | length' | grep -q '[1-9]'")

    # Test monitoring during failure scenarios
    with subtest("Monitoring captures failure events"):
        # Stop a service to generate failure event
        gateway.succeed("systemctl stop kresd@1.service")

        # Wait for monitoring to detect
        sleep 10

        # Check that failure was logged
        gateway.succeed("grep -q 'inactive' /tmp/service-health.json")

        # Restart service
        gateway.succeed("systemctl start kresd@1.service")

    # Export final metrics
    with subtest("Metrics export works correctly"):
        gateway.succeed("systemctl start monitoring-teardown.service")

        # Check export directory
        gateway.succeed("test -d /tmp/metrics-export")
        gateway.succeed("test -f /tmp/metrics-export/summary.json")

        # Validate export summary
        gateway.succeed("jq -r '.system_metrics_count' /tmp/metrics-export/summary.json | grep -q '[0-9]'")

    # Collect monitoring test results
    mkdir -p /tmp/monitoring-test-results
    cp -r /tmp/metrics-export/* /tmp/monitoring-test-results/ 2>/dev/null || true
    cp -r /tmp/system-metrics/* /tmp/monitoring-test-results/ 2>/dev/null || true
    cp -r /tmp/service-health/* /tmp/monitoring-test-results/ 2>/dev/null || true
    cp -r /tmp/app-metrics/* /tmp/monitoring-test-results/ 2>/dev/null || true

    cat > /tmp/monitoring-test-results/test-summary.json << EOF
    {
      "combination": "$COMBINATION",
      "monitoring_test": "passed",
      "prometheus_integration": "passed",
      "metrics_collection": "passed",
      "failure_detection": "passed",
      "export_functionality": "passed",
      "timestamp": "$(date -Iseconds)"
    }
    EOF
  '';
}
EOF

# Run monitoring integration test
echo "Executing monitoring integration test..."
if nix build ".#checks.x86_64-linux.${COMBINATION}-monitoring-integration"; then
  echo "✅ Monitoring integration test passed"

  # Extract results
  mkdir -p "results/$COMBINATION/monitoring-integration"
  cp result/monitoring-test-results/* "results/$COMBINATION/monitoring-integration/" 2>/dev/null || true

else
  echo "❌ Monitoring integration test failed"
  exit 1
fi
```

## Metrics Analysis and Reporting

```bash
#!/usr/bin/env bash
# scripts/analyze-monitoring-metrics.sh

COMBINATION="$1"
RESULTS_DIR="results/$COMBINATION/monitoring-integration"

echo "Analyzing monitoring metrics for $COMBINATION"

# Analyze system metrics
echo "=== System Metrics Analysis ==="
if [ -f "$RESULTS_DIR/cpu.json" ]; then
  cpu_avg=$(jq -r '.cpu.usage_percent' "$RESULTS_DIR/cpu.json" | awk '{sum+=$1} END {print sum/NR}')
  echo "Average CPU usage: ${cpu_avg}%"
fi

if [ -f "$RESULTS_DIR/memory.json" ]; then
  mem_max=$(jq -r '.memory.usage_percent' "$RESULTS_DIR/memory.json" | sort -n | tail -1)
  echo "Peak memory usage: ${mem_max}%"
fi

# Analyze service health
echo "=== Service Health Analysis ==="
if [ -f "$RESULTS_DIR/service-health.json" ]; then
  active_services=$(jq -r 'select(.status == "active") | .service' "$RESULTS_DIR/service-health.json" | wc -l)
  total_services=$(jq -r '.service' "$RESULTS_DIR/service-health.json" | wc -l)
  echo "Services active: $active_services/$total_services"
fi

# Analyze application metrics
echo "=== Application Metrics Analysis ==="
if [ -f "$RESULTS_DIR/kresd.json" ]; then
  dns_queries=$(jq -r '.queries_per_minute' "$RESULTS_DIR/kresd.json")
  echo "DNS queries per minute: $dns_queries"
fi

# Generate comprehensive monitoring report
cat > "$RESULTS_DIR/monitoring-analysis-report.json" << EOF
{
  "combination": "$COMBINATION",
  "analysis_timestamp": "$(date -Iseconds)",
  "system_metrics": {
    "cpu_average_percent": $(jq -r '.cpu.usage_percent' "$RESULTS_DIR/cpu.json" 2>/dev/null | awk '{sum+=$1} END {print sum/NR}' || echo "0"),
    "memory_peak_percent": $(jq -r '.memory.usage_percent' "$RESULTS_DIR/memory.json" 2>/dev/null | sort -n | tail -1 || echo "0"),
    "disk_usage_percent": $(jq -r '.disk.root_usage_percent' "$RESULTS_DIR/disk.json" 2>/dev/null | tail -1 || echo "0")
  },
  "service_health": {
    "total_services": $(jq -r '.service' "$RESULTS_DIR/service-health.json" 2>/dev/null | wc -l || echo "0"),
    "active_services": $(jq -r 'select(.status == "active") | .service' "$RESULTS_DIR/service-health.json" 2>/dev/null | wc -l || echo "0")
  },
  "application_metrics": {
    "dns_queries_per_minute": $(jq -r '.queries_per_minute' "$RESULTS_DIR/kresd.json" 2>/dev/null || echo "0"),
    "dhcp_leases_per_minute": $(jq -r '.leases_per_minute' "$RESULTS_DIR/kea-dhcp4.json" 2>/dev/null || echo "0")
  },
  "monitoring_quality": {
    "metrics_collection": $([ -d "$RESULTS_DIR" ] && find "$RESULTS_DIR" -name "*.json" | wc -l || echo "0"),
    "prometheus_integration": $(curl -s http://localhost:9090/api/v1/query?query=up > /dev/null 2>&1 && echo "true" || echo "false"),
    "log_monitoring": $([ -f "$RESULTS_DIR/combined.log.gz" ] && echo "true" || echo "false")
  },
  "recommendations": $([ $(jq -r '.cpu_average_percent' "$RESULTS_DIR/cpu.json" 2>/dev/null | awk '{sum+=$1} END {print sum/NR}' || echo "0") -gt 70 ] && echo '"High CPU usage detected - consider resource optimization"' || echo '"Monitoring data collection successful"')
}
EOF

echo "Monitoring metrics analysis completed"
echo "Report saved to: $RESULTS_DIR/monitoring-analysis-report.json"
```

This monitoring and metrics collection framework provides comprehensive observability during testing, enabling detailed analysis of system behavior, performance characteristics, and failure patterns for feature combination validation.
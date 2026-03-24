# NAT Gateway Monitoring Library
{ lib, pkgs, ... }:

with lib;

let
  # Generate Prometheus metrics collection script
  mkMonitoringScript = instances:
    pkgs.writeShellScriptBin "nat-monitor" ''
      #!/bin/bash
      set -euo pipefail

      METRICS_FILE="/tmp/nat_metrics.prom"
      NAT_METRICS_PORT="9092"

      # Function to collect NAT connection statistics
      collect_nat_stats() {
        local instance_name="$1"
        local interface="$2"
        
        # Get connection tracking statistics
        local conntrack_stats=$(${pkgs.conntrack-tools}/bin/conntrack -L 2>/dev/null | wc -l || echo "0")
        
        # Get interface statistics
        local interface_stats=$(${pkgs.iproute2}/bin/ip -s link show dev "$interface" 2>/dev/null || echo "")
        local tx_bytes=$(echo "$interface_stats" | awk '/RX:/ {getline; print $2}')
        local rx_bytes=$(echo "$interface_stats" | awk '/RX:/ {print $2}')
        
        # Get NAT table statistics
        local nat_stats=$(${pkgs.iptables}/bin/iptables -t nat -L -v -n 2>/dev/null || echo "")
        
        # Prometheus metrics
        cat << EOF > "$METRICS_FILE"
# HELP nat_connections_total Number of active NAT connections
# TYPE nat_connections_total gauge
nat_connections_total{instance="$instance_name"} $conntrack_stats

# HELP nat_interface_bytes_transmitted Total bytes transmitted on NAT interface
# TYPE nat_interface_bytes_transmitted counter
nat_interface_bytes_transmitted{instance="$instance_name",interface="$interface"} $tx_bytes

# HELP nat_interface_bytes_received Total bytes received on NAT interface
# TYPE nat_interface_bytes_received counter
nat_interface_bytes_received{instance="$instance_name",interface="$interface"} $rx_bytes

# HELP nat_instance_up NAT instance status
# TYPE nat_instance_up gauge
nat_instance_up{instance="$instance_name"} 1
EOF
      }

      # Function to collect memory and CPU usage
      collect_system_stats() {
        local memory_usage=$(free -m | awk 'NR==2{printf "%.2f", $3*100/$2}')
        local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
        
        cat << EOF >> "$METRICS_FILE"
# HELP nat_memory_usage_percentage Memory usage percentage
# TYPE nat_memory_usage_percentage gauge
nat_memory_usage_percentage $memory_usage

# HELP nat_cpu_usage_percentage CPU usage percentage
# TYPE nat_cpu_usage_percentage gauge
nat_cpu_usage_percentage ${cpu_usage:-0}
EOF
      }

      # Function to serve metrics via HTTP
      serve_metrics() {
        while true; do
          # Collect metrics for all instances
          > "$METRICS_FILE"
          
          ${concatStringsSep "\n" (map (instance: ''
            collect_nat_stats "${instance.name}" "${instance.publicInterface}"
          '') instances)}
          
          collect_system_stats
          
          # Serve metrics (simple HTTP server)
          echo -e "HTTP/1.1 200 OK\nContent-Type: text/plain\n\n$(cat "$METRICS_FILE")" | ${pkgs.nmap}/bin/nc -l -p "$NAT_METRICS_PORT" -q 1 || true
          sleep 5
        done
      }

      # Start metrics collection
      echo "Starting NAT Gateway monitoring on port $NAT_METRICS_PORT"
      serve_metrics
    '';

  # Generate alerting rules
  mkAlertRules = instances:
    let
      alertNames = map (instance: "nat_gateway_${instance.name}_down") instances;
    in
    concatStringsSep "\n" (map (name: ''
      - alert: ${toUpper name}
        expr: nat_instance_up == 0
        for: 30s
        labels:
          severity: critical
        annotations:
          summary: "NAT Gateway instance is down"
          description: "NAT Gateway instance has been down for more than 30 seconds"
    '') alertNames);

  # Generate Grafana dashboard configuration
  mkGrafanaDashboard = instances:
    pkgs.writeText "nat-gateway-dashboard.json" (builtins.toJSON {
      dashboard = {
        title = "NAT Gateway Dashboard";
        panels = [
          {
            title = "NAT Connections";
            type = "graph";
            targets = [
              {
                expr = "nat_connections_total";
                legendFormat = "{{instance}}";
              }
            ];
          }
          {
            title = "Interface Throughput";
            type = "graph";
            targets = [
              {
                expr = "rate(nat_interface_bytes_transmitted[5m])";
                legendFormat = "{{instance}} TX";
              }
              {
                expr = "rate(nat_interface_bytes_received[5m])";
                legendFormat = "{{instance}} RX";
              }
            ];
          }
          {
            title = "System Resources";
            type = "graph";
            targets = [
              {
                expr = "nat_memory_usage_percentage";
                legendFormat = "Memory %";
              }
              {
                expr = "nat_cpu_usage_percentage";
                legendFormat = "CPU %";
              }
            ];
          }
        ];
      };
    });

  # Generate log collection configuration
  mkLogConfig = ''
    # NAT Gateway Logging Configuration
    # Collect iptables logs for NAT operations

    # Log NAT rule hits
    logrotate.d/nat-gateway {
      weekly
      rotate 4
      compress
      missingok
      notifempty
      create 644 syslog adm
      postrotate
        /usr/bin/killall -HUP syslogd 2>/dev/null || true
      endscript
      /var/log/nat.log {
        daily
        rotate 7
        compress
        delaycompress
        missingok
        notifempty
        create 644 syslog adm
      }
    }

    # Rsyslog configuration for NAT logs
    $ModLoad imfile
    $InputFileName /var/log/nat.log
    $InputFileTag nat-gateway:
    $InputFileStateFile stat-nat-gateway
    $InputRunFileMonitor

    # Filter NAT-related iptables logs
    :msg, contains, "NAT-" /var/log/nat.log
    & stop
  '';

in {
  inherit
    mkMonitoringScript
    mkAlertRules
    mkGrafanaDashboard
    mkLogConfig;
}

{ config, lib, ... }:

with lib;

let
  cfg = config.simulator.verification;
in

{
  options.simulator.verification = {
    scenarios = mkOption {
      type = types.attrsOf (types.attrsOf types.attrs);
      default = {};
      description = "Verification scenarios for different feature categories";
    };
  };

  config.simulator.verification.scenarios = {
    networking = {
      dhcp = {
        title = "DHCP Server Functionality";
        description = "Verify DHCP server assigns IP addresses correctly";
        steps = [
          "Check DHCP service is running"
          "Verify DHCP configuration is loaded"
          "Test IP address assignment to clients"
          "Validate lease database updates"
          "Check DNS updates from DHCP"
        ];
        automatedTests = [
          "systemctl is-active kea-dhcp4-server"
          "kea-dhcp4 -t /etc/kea/dhcp4.conf"
          "dhcpd -t /etc/dhcpd.conf"
        ];
        evidence = [
          "DHCP lease database"
          "DHCP server logs"
          "Client IP assignments"
        ];
      };

      dns = {
        title = "DNS Resolution";
        description = "Verify DNS server resolves queries correctly";
        steps = [
          "Check DNS service is running"
          "Test forward DNS resolution"
          "Test reverse DNS resolution"
          "Verify DNS caching works"
          "Check DNSSEC validation"
        ];
        automatedTests = [
          "systemctl is-active unbound"
          "dig @127.0.0.1 google.com"
          "dig @127.0.0.1 -x 8.8.8.8"
        ];
        evidence = [
          "DNS query logs"
          "DNS cache statistics"
          "DNSSEC validation results"
        ];
      };

      routing = {
        title = "Network Routing";
        description = "Verify routing table and forwarding functionality";
        steps = [
          "Check routing table entries"
          "Test static route configuration"
          "Verify IP forwarding is enabled"
          "Test inter-network connectivity"
          "Check routing protocol convergence"
        ];
        automatedTests = [
          "ip route show"
          "sysctl net.ipv4.ip_forward"
          "ping -c 3 192.168.2.1"
        ];
        evidence = [
          "Routing table dumps"
          "Forwarding statistics"
          "Connectivity test results"
        ];
      };
    };

    security = {
      firewall = {
        title = "Firewall Rules";
        description = "Verify firewall policies are correctly enforced";
        steps = [
          "Check firewall service is running"
          "Verify rule loading"
          "Test allowed traffic passes"
          "Test blocked traffic is dropped"
          "Check logging of blocked attempts"
        ];
        automatedTests = [
          "systemctl is-active nftables"
          "nft list ruleset"
          "iptables -L -n"
        ];
        evidence = [
          "Firewall rule dumps"
          "Connection tracking table"
          "Firewall logs"
        ];
      };

      vpn = {
        title = "VPN Connectivity";
        description = "Verify VPN tunnel establishment and security";
        steps = [
          "Check VPN service configuration"
          "Test tunnel establishment"
          "Verify encrypted traffic flow"
          "Check certificate validation"
          "Test VPN client connectivity"
        ];
        automatedTests = [
          "systemctl is-active wireguard"
          "wg show"
          "ip link show wg0"
        ];
        evidence = [
          "VPN interface status"
          "WireGuard configuration"
          "VPN connection logs"
        ];
      };

      ids = {
        title = "Intrusion Detection";
        description = "Verify intrusion detection and alerting";
        steps = [
          "Check IDS service is running"
          "Verify signature database"
          "Test alert generation"
          "Check log aggregation"
          "Validate false positive handling"
        ];
        automatedTests = [
          "systemctl is-active suricata"
          "suricata --list-app-layer-protos"
        ];
        evidence = [
          "IDS alert logs"
          "Signature update status"
          "Performance statistics"
        ];
      };
    };

    monitoring = {
      health = {
        title = "Health Monitoring";
        description = "Verify system health monitoring and alerting";
        steps = [
          "Check monitoring service status"
          "Verify metric collection"
          "Test alert thresholds"
          "Check dashboard accessibility"
          "Validate data retention"
        ];
        automatedTests = [
          "systemctl is-active prometheus"
          "curl -s http://localhost:9090/-/healthy"
          "systemctl is-active grafana"
        ];
        evidence = [
          "Prometheus metrics"
          "Grafana dashboard screenshots"
          "Alert manager status"
        ];
      };

      logging = {
        title = "Log Aggregation";
        description = "Verify log collection and analysis";
        steps = [
          "Check logging service status"
          "Verify log sources"
          "Test log parsing and filtering"
          "Check log retention policies"
          "Validate log search functionality"
        ];
        automatedTests = [
          "systemctl is-active rsyslog"
          "systemctl is-active loki"
          "curl -s http://localhost:3100/ready"
        ];
        evidence = [
          "Log aggregation statistics"
          "Log parsing results"
          "Storage utilization"
        ];
      };

      tracing = {
        title = "Distributed Tracing";
        description = "Verify request tracing and analysis";
        steps = [
          "Check tracing service status"
          "Verify trace collection"
          "Test trace correlation"
          "Check trace visualization"
          "Validate performance impact"
        ];
        automatedTests = [
          "systemctl is-active jaeger"
          "curl -s http://localhost:16686/api/services"
        ];
        evidence = [
          "Trace collection statistics"
          "Trace visualization screenshots"
          "Performance metrics"
        ];
      };
    };

    performance = {
      qos = {
        title = "Quality of Service";
        description = "Verify traffic shaping and prioritization";
        steps = [
          "Check QoS configuration"
          "Test bandwidth limits"
          "Verify traffic classification"
          "Check queue statistics"
          "Validate priority handling"
        ];
        automatedTests = [
          "tc qdisc show"
          "tc class show dev eth0"
          "systemctl is-active qos-setup"
        ];
        evidence = [
          "QoS configuration dump"
          "Traffic shaping statistics"
          "Queue utilization graphs"
        ];
      };

      loadBalancing = {
        title = "Load Balancing";
        description = "Verify load distribution and failover";
        steps = [
          "Check load balancer configuration"
          "Test traffic distribution"
          "Verify health checks"
          "Test failover scenarios"
          "Check session persistence"
        ];
        automatedTests = [
          "systemctl is-active haproxy"
          "curl -s http://localhost:1936/stats"
        ];
        evidence = [
          "Load balancer statistics"
          "Health check results"
          "Failover test logs"
        ];
      };

      acceleration = {
        title = "XDP/eBPF Acceleration";
        description = "Verify high-performance packet processing";
        steps = [
          "Check XDP program loading"
          "Verify eBPF maps"
          "Test packet processing"
          "Check performance metrics"
          "Validate bypass functionality"
        ];
        automatedTests = [
          "ip link show eth0 | grep xdp"
          "bpftool prog show"
          "bpftool map show"
        ];
        evidence = [
          "XDP program statistics"
          "eBPF map contents"
          "Performance benchmarks"
        ];
      };
    };
  };
}
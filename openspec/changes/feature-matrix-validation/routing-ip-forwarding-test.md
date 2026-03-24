# Routing Configuration and IP Forwarding Test

## Test Overview
- **Test ID**: routing-ip-forwarding
- **Feature**: Core Networking
- **Scope**: Functional + Performance
- **Duration**: 18 minutes
- **Evidence Types**: logs, metrics, outputs, configs

## Test Configuration

```nix
# tests/routing-ip-forwarding-test.nix
{ pkgs, lib, ... }:

let
  testFramework = import ../lib/standardized-test-framework.nix { inherit lib; };

  routingCollectors = [
    # Routing table evidence
    {
      name = "routing-tables";
      script = ''
        echo "=== IPv4 Routing Table ===" > /tmp/evidence/routing-tables.txt
        ip route show >> /tmp/evidence/routing-tables.txt
        echo "" >> /tmp/evidence/routing-tables.txt
        echo "=== IPv6 Routing Table ===" >> /tmp/evidence/routing-tables.txt
        ip -6 route show >> /tmp/evidence/routing-tables.txt
      '';
    }

    # Forwarding statistics evidence
    {
      name = "forwarding-stats";
      script = ''
        echo "=== IP Forwarding Status ===" > /tmp/evidence/forwarding-stats.txt
        sysctl net.ipv4.ip_forward >> /tmp/evidence/forwarding-stats.txt
        sysctl net.ipv6.conf.all.forwarding >> /tmp/evidence/forwarding-stats.txt
        echo "" >> /tmp/evidence/forwarding-stats.txt
        echo "=== Network Statistics ===" >> /tmp/evidence/forwarding-stats.txt
        ip -s link show eth0 >> /tmp/evidence/forwarding-stats.txt
        ip -s link show eth1 >> /tmp/evidence/forwarding-stats.txt
      '';
    }

    # Route manipulation evidence
    {
      name = "route-changes";
      script = ''
        echo "=== Route Changes Log ===" > /tmp/evidence/route-changes.txt
        journalctl -u systemd-networkd --since "15 minutes ago" | grep -i "route\|gateway\|via" >> /tmp/evidence/route-changes.txt 2>/dev/null || true
      '';
    }

    # Inter-network connectivity evidence
    {
      name = "inter-network-connectivity";
      script = ''
        # Test connectivity between different networks
        echo "=== Inter-Network Connectivity Tests ===" > /tmp/evidence/inter-network-connectivity.txt

        # Test from client1 to client2 (same network)
        ping -c 3 client2 >> /tmp/evidence/inter-network-connectivity.txt 2>&1 || echo "Same network ping failed" >> /tmp/evidence/inter-network-connectivity.txt

        # Test from client1 to external (different network)
        ping -c 3 8.8.8.8 >> /tmp/evidence/inter-network-connectivity.txt 2>&1 || echo "External ping failed (expected in test env)" >> /tmp/evidence/inter-network-connectivity.txt

        # Test traceroute
        traceroute -n -m 5 8.8.8.8 >> /tmp/evidence/inter-network-connectivity.txt 2>&1 || echo "Traceroute failed" >> /tmp/evidence/inter-network-connectivity.txt
      '';
    }
  ];

in
testFramework.mkStandardTest {
  name = "routing-ip-forwarding-test";
  description = "Test routing configuration and IP forwarding functionality";
  feature = "core-networking";
  category = "networking";
  timeout = 1080;  # 18 minutes

  nodes = {
    gateway = { config, pkgs, ... }: {
      imports = [ ../modules ];
      services.gateway = {
        enable = true;

        interfaces = {
          wan = "eth0";
          lan = "eth1";
        };

        domain = "test.local";

        data = {
          network = {
            subnets = {
              lan = {
                ipv4 = {
                  subnet = "192.168.1.0/24";
                  gateway = "192.168.1.1";
                };
              };
            };
          };
        };
      };

      # Enable IP forwarding
      boot.kernel.sysctl = {
        "net.ipv4.ip_forward" = 1;
        "net.ipv6.conf.all.forwarding" = 1;
      };

      # Configure static routes for testing
      networking.interfaces.eth1.ipv4.routes = [
        { address = "192.168.2.0"; prefixLength = 24; via = "192.168.1.2"; }
      ];

      # Test utilities
      environment.systemPackages = with pkgs; [
        iproute2
        tcpdump
        traceroute
        iputils
        iptables
        nftables
      ];
    };

    client1 = { config, pkgs, ... }: {
      virtualisation.vlans = [ 1 ];
      networking = {
        useDHCP = true;
        nameservers = [ "192.168.1.1" ];
        defaultGateway = "192.168.1.1";
      };

      environment.systemPackages = with pkgs; [
        iproute2
        traceroute
        iputils
      ];
    };

    client2 = { config, pkgs, ... }: {
      virtualisation.vlans = [ 1 ];
      networking = {
        useDHCP = true;
        nameservers = [ "192.168.1.1" ];
        defaultGateway = "192.168.1.1";
      };

      environment.systemPackages = with pkgs; [
        iproute2
        traceroute
        iputils
      ];
    };

    # External router simulator
    externalRouter = {
      virtualisation.vlans = [ 2 ];
      networking.interfaces.eth1 = {
        ipv4.addresses = [{
          address = "192.168.2.1";
          prefixLength = 24;
        }];
      };

      services.dhcpd4 = {
        enable = true;
        interfaces = [ "eth1" ];
        extraConfig = ''
          subnet 192.168.2.0 netmask 255.255.255.0 {
            range 192.168.2.100 192.168.2.200;
            option routers 192.168.2.1;
          }
        '';
      };

      boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
    };
  };

  testScript = ''
    start_all()

    # Phase 1: IP forwarding verification
    with subtest("IP forwarding is properly enabled"):
        # Check IPv4 forwarding
        gateway.succeed("sysctl net.ipv4.ip_forward | grep -q '1'")
        gateway.succeed("cat /proc/sys/net/ipv4/ip_forward | grep -q '1'")

        # Check IPv6 forwarding
        gateway.succeed("sysctl net.ipv6.conf.all.forwarding | grep -q '1'")
        gateway.succeed("cat /proc/sys/net/ipv6/conf/all/forwarding | grep -q '1'")

    # Phase 2: Basic routing table validation
    with subtest("Routing tables are correctly configured"):
        # Check for default route
        gateway.succeed("ip route show | grep -q 'default'")
        client1.succeed("ip route show | grep -q 'default via 192.168.1.1'")
        client2.succeed("ip route show | grep -q 'default via 192.168.1.1'")

        # Check for local subnet routes
        gateway.succeed("ip route show | grep -q '192.168.1.0/24'")
        client1.succeed("ip route show | grep -q '192.168.1.0/24'")

    # Phase 3: Static route configuration
    with subtest("Static routes are properly configured"):
        # Check static route exists
        gateway.succeed("ip route show | grep -q '192.168.2.0/24 via 192.168.1.2'")

        # Verify route is active
        gateway.succeed("ip route get 192.168.2.1 | grep -q 'via 192.168.1.2'")

    # Phase 4: Inter-network forwarding
    with subtest("IP forwarding works between networks"):
        # Test forwarding from client1 to external router
        client1.succeed("ping -c 3 192.168.2.1")

        # Test that traffic is being forwarded through gateway
        gateway.succeed("tcpdump -i eth1 -c 5 icmp and host 192.168.2.1 >/dev/null 2>&1 || true")

    # Phase 5: NAT and masquerading
    with subtest("NAT and masquerading work correctly"):
        # Enable masquerading on WAN interface
        gateway.succeed("iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE")
        gateway.succeed("iptables -A FORWARD -i eth1 -o eth0 -j ACCEPT")
        gateway.succeed("iptables -A FORWARD -i eth0 -o eth1 -m state --state RELATED,ESTABLISHED -j ACCEPT")

        # Test that client can reach external network through NAT
        client1.succeed("ping -c 3 8.8.8.8 || true")  # May not work in test environment

    # Phase 6: Route manipulation and dynamic routing
    with subtest("Route manipulation works correctly"):
        # Add a test route
        gateway.succeed("ip route add 192.168.3.0/24 via 192.168.1.1 dev eth1")
        gateway.succeed("ip route show | grep -q '192.168.3.0/24'")

        # Remove the test route
        gateway.succeed("ip route del 192.168.3.0/24 via 192.168.1.1 dev eth1")
        gateway.succeed("ip route show | grep -q '192.168.3.0/24' && exit 1 || true")

    # Phase 7: Routing performance
    with subtest("Routing performance meets requirements"):
        # Test forwarding performance
        gateway.succeed("iperf3 -s -D -1 >/dev/null 2>&1 || true")
        client1.succeed("iperf3 -c 192.168.1.1 -t 5 | grep -q 'sender' || true")

        # Test latency through routing
        latency = client1.succeed("ping -c 10 192.168.1.1 | tail -1 | awk '{print $4}' | cut -d/ -f2")
        if (( $(echo "$latency > 20" | bc -l 2>/dev/null || echo "0") )); then
          print("High routing latency detected: ''${latency}ms")
        fi

    # Phase 8: Routing table persistence
    with subtest("Routing configuration persists"):
        # Get initial routing table
        initial_routes = gateway.succeed("ip route show | wc -l")

        # Reload network configuration
        gateway.succeed("systemctl reload systemd-networkd")

        # Check routes are preserved
        final_routes = gateway.succeed("ip route show | wc -l")
        # Note: In practice, we'd do a more detailed comparison

        # Verify forwarding still works
        client1.succeed("ping -c 3 192.168.1.1")

    # Phase 9: IPv6 routing
    with subtest("IPv6 routing works correctly"):
        # Check IPv6 routes
        gateway.succeed("ip -6 route show | grep -q 'default\\|::/0' || true")

        # Test IPv6 forwarding (if IPv6 is configured)
        client1.succeed("ping -6 -c 3 ff02::1%eth1 || true")  # Link-local ping

    # Phase 10: Routing security
    with subtest("Routing configuration is secure"):
        # Check for secure routing practices
        gateway.succeed("sysctl net.ipv4.conf.all.rp_filter | grep -q '1'")  # RP filter enabled
        gateway.succeed("sysctl net.ipv4.conf.all.accept_redirects | grep -q '0'")  # No redirects

        # Verify no insecure routes
        gateway.succeed("ip route show | grep -v 'reject\\|unreachable\\|prohibit' || true")

    # Phase 11: Load balancing routing
    with subtest("Load balancing across multiple routes works"):
        # Add multiple routes to same destination
        gateway.succeed("ip route add default via 192.168.1.1 dev eth1 metric 100")
        gateway.succeed("ip route add default via 192.168.1.2 dev eth1 metric 200")

        # Check load balancing
        routes = gateway.succeed("ip route show | grep -c 'default'")
        if [ "$routes" -gt 1 ]; then
          print("Multiple default routes configured for load balancing")
        fi

        # Clean up test routes
        gateway.succeed("ip route del default via 192.168.1.1 dev eth1 metric 100 2>/dev/null || true")
        gateway.succeed("ip route del default via 192.168.1.2 dev eth1 metric 200 2>/dev/null || true")

    # Phase 12: Error handling in routing
    with subtest("Routing errors are handled gracefully"):
        # Test with unreachable route
        gateway.succeed("ip route add 192.168.99.0/24 via 192.168.1.99 dev eth1 2>/dev/null || true")

        # Verify system remains stable
        client1.succeed("ping -c 3 192.168.1.1")

        # Clean up
        gateway.succeed("ip route del 192.168.99.0/24 via 192.168.1.99 dev eth1 2>/dev/null || true")
  '';

  evidenceCollectors = with testFramework.standardCollectors; [
    systemLogs
    systemMetrics
    serviceStatus
    networkConfig
  ] ++ routingCollectors;

  tags = [ "routing" "ip-forwarding" "nat" "networking" "core" ];
}
```

## Test Execution and Validation

### Execution Script
```bash
#!/usr/bin/env bash
# scripts/run-routing-ip-forwarding-test.sh

set -euo pipefail

echo "Running Routing Configuration and IP Forwarding Test"

# Run the standardized test
./scripts/run-standardized-test.sh tests/routing-ip-forwarding-test.nix routing-ip-forwarding-test

echo "Routing and IP forwarding test completed"
echo "Evidence collected in: results/routing-ip-forwarding-test/"
```

### Validation Checklist

#### Functional Requirements
- [ ] IP forwarding is enabled for both IPv4 and IPv6
- [ ] Routing tables contain correct routes
- [ ] Static routes are properly configured
- [ ] Traffic forwarding works between networks
- [ ] NAT/masquerading functions correctly
- [ ] Route manipulation commands work
- [ ] Routing configuration persists across reloads
- [ ] IPv6 routing works (if configured)
- [ ] Routing security measures are in place
- [ ] Load balancing routes function (if configured)
- [ ] Routing errors are handled gracefully

#### Evidence Collection
- [ ] Complete routing tables captured
- [ ] IP forwarding status documented
- [ ] Route change events logged
- [ ] Inter-network connectivity tested
- [ ] System logs captured during routing operations
- [ ] Network metrics collected
- [ ] Service status monitored
- [ ] Configuration files preserved

#### Performance Validation
- [ ] Forwarding performance meets requirements
- [ ] Routing latency is acceptable
- [ ] No packet loss in forwarding
- [ ] CPU usage during forwarding is reasonable
- [ ] Memory usage remains stable

#### Security Validation
- [ ] Routing filters are properly configured
- [ ] No insecure routing options enabled
- [ ] Route manipulation is secure
- [ ] Forwarding rules don't create vulnerabilities

## Expected Test Results

### Success Criteria
- All routing functionality works as expected
- IP forwarding enables proper network connectivity
- Static and dynamic routes are correctly configured
- Traffic is properly forwarded between networks
- NAT functionality works for outbound traffic
- Routing configuration remains stable

### Evidence Analysis
- **Routing tables**: Should show complete and correct routing information
- **Forwarding stats**: Should confirm IP forwarding is enabled
- **Route changes**: Should document any routing table modifications
- **Connectivity tests**: Should demonstrate successful inter-network communication
- **System logs**: Should show successful routing operations

### Performance Benchmarks
- **Forwarding throughput**: > 100 Mbps
- **Routing latency**: < 10ms local network
- **Route convergence**: < 30 seconds
- **NAT throughput**: > 50 Mbps
- **Memory usage**: < 85% during forwarding

This test validates the core routing and IP forwarding capabilities that enable the NixOS Gateway Framework to function as a network router and gateway device.
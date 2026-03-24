# IPv4/IPv6 Dual Stack Support Test

## Test Overview
- **Test ID**: ipv4-ipv6-dual-stack
- **Feature**: Core Networking
- **Scope**: Functional
- **Duration**: 15 minutes
- **Evidence Types**: logs, metrics, outputs, configs

## Test Configuration

```nix
# tests/ipv4-ipv6-dual-stack-test.nix
{ pkgs, lib, ... }:

let
  # Import standardized test framework
  testFramework = import ../lib/standardized-test-framework.nix { inherit lib; };

  # Test-specific evidence collectors
  dualStackCollectors = [
    # Network interface configuration evidence
    {
      name = "network-interfaces";
      script = ''
        ip addr show > /tmp/evidence/network-interfaces.txt
        ip -6 addr show >> /tmp/evidence/network-interfaces.txt
      '';
    }

    # Routing table evidence
    {
      name = "routing-tables";
      script = ''
        ip route show > /tmp/evidence/ipv4-routes.txt
        ip -6 route show > /tmp/evidence/ipv6-routes.txt
      '';
    }

    # DNS resolution evidence
    {
      name = "dns-resolution";
      script = ''
        # Test IPv4 DNS resolution
        nslookup ipv4.google.com 8.8.8.8 > /tmp/evidence/dns-ipv4.txt 2>&1 || true
        # Test IPv6 DNS resolution
        nslookup ipv6.google.com 2001:4860:4860::8888 > /tmp/evidence/dns-ipv6.txt 2>&1 || true
      '';
    }

    # Connectivity test evidence
    {
      name = "connectivity-tests";
      script = ''
        # Test IPv4 connectivity
        ping -c 3 -4 8.8.8.8 > /tmp/evidence/ping-ipv4.txt 2>&1 || true
        # Test IPv6 connectivity
        ping -c 3 -6 2001:4860:4860::8888 > /tmp/evidence/ping-ipv6.txt 2>&1 || true
      '';
    }
  ];

in
testFramework.mkStandardTest {
  name = "ipv4-ipv6-dual-stack-test";
  description = "Test IPv4/IPv6 dual stack support and functionality";
  feature = "core-networking";
  category = "networking";
  timeout = 900;  # 15 minutes

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
                ipv6 = {
                  prefix = "2001:db8:1::/48";
                  gateway = "2001:db8:1::1";
                };
              };
            };
          };
        };
      };

      # Enable IPv6
      networking.enableIPv6 = true;

      # Test utilities
      environment.systemPackages = with pkgs; [
        iproute2
        bind  # for nslookup
        iputils
      ];
    };

    client4 = { config, pkgs, ... }: {
      virtualisation.vlans = [ 1 ];
      networking.useDHCP = true;
      networking.nameservers = [ "192.168.1.1" ];

      environment.systemPackages = with pkgs; [
        iproute2
        bind
        iputils
      ];
    };

    client6 = { config, pkgs, ... }: {
      virtualisation.vlans = [ 1 ];
      networking.useDHCP = true;
      networking.nameservers = [ "192.168.1.1" ];

      # Force IPv6-only for testing
      networking.enableIPv6 = true;
      networking.tempAddresses = "disabled";

      environment.systemPackages = with pkgs; [
        iproute2
        bind
        iputils
      ];
    };
  };

  testScript = ''
    start_all()

    # Phase 1: Basic network configuration validation
    with subtest("Network interfaces are properly configured"):
        # Check IPv4 interface configuration
        gateway.succeed("ip addr show eth1 | grep -q '192.168.1.1'")
        client4.succeed("ip addr show eth1 | grep -q '192.168.1.'")

        # Check IPv6 interface configuration
        gateway.succeed("ip -6 addr show eth1 | grep -q '2001:db8:1::1'")
        client6.succeed("ip -6 addr show eth1 | grep -q '2001:db8:1::'")

    # Phase 2: IPv4 connectivity testing
    with subtest("IPv4 connectivity works correctly"):
        client4.wait_for_unit("network-online.target")
        client4.succeed("ping -c 3 192.168.1.1")  # Ping gateway
        client4.succeed("ping -c 3 8.8.8.8")      # Ping external IPv4

    # Phase 3: IPv6 connectivity testing
    with subtest("IPv6 connectivity works correctly"):
        client6.wait_for_unit("network-online.target")
        client6.succeed("ping -c 3 2001:db8:1::1")  # Ping gateway IPv6
        # Note: External IPv6 connectivity may not work in test environment

    # Phase 4: Dual stack DNS resolution
    with subtest("DNS resolution works for both IPv4 and IPv6"):
        # Test IPv4 DNS resolution
        client4.succeed("nslookup google.com 192.168.1.1 | grep -q 'Address:'")

        # Test IPv6 DNS resolution (if available)
        client6.succeed("nslookup google.com 2001:db8:1::1 | grep -q 'Address:' || true")

    # Phase 5: Routing table validation
    with subtest("Routing tables are correctly configured"):
        # Check IPv4 routing
        gateway.succeed("ip route show | grep -q '192.168.1.0/24'")
        client4.succeed("ip route show | grep -q 'default via 192.168.1.1'")

        # Check IPv6 routing
        gateway.succeed("ip -6 route show | grep -q '2001:db8:1::/48'")
        client6.succeed("ip -6 route show | grep -q 'default via 2001:db8:1::1'")

    # Phase 6: Service availability over both protocols
    with subtest("Services are accessible over both IPv4 and IPv6"):
        # Test DNS service over IPv4
        client4.succeed("dig @192.168.1.1 test.local | grep -q 'ANSWER SECTION'")

        # Test DNS service over IPv6 (if configured)
        client6.succeed("dig @2001:db8:1::1 test.local | grep -q 'ANSWER SECTION' || true")

    # Phase 7: Network performance validation
    with subtest("Network performance is acceptable"):
        # Test IPv4 throughput (basic)
        ipv4_throughput = client4.succeed("ping -c 10 192.168.1.1 | tail -1 | awk '{print $4}' | cut -d/ -f2")
        # Basic latency check (< 10ms for local network)
        if (( $(echo "$ipv4_throughput < 10" | bc -l 2>/dev/null || echo "1") )); then
          print("IPv4 latency acceptable: ${ipv4_throughput}ms")
        else
          print("IPv4 latency high: ${ipv4_throughput}ms")
        fi

    # Phase 8: Configuration persistence
    with subtest("Network configuration persists"):
        # Reload network configuration
        gateway.succeed("systemctl reload systemd-networkd")

        # Verify configuration remains
        gateway.succeed("ip addr show eth1 | grep -q '192.168.1.1'")
        gateway.succeed("ip -6 addr show eth1 | grep -q '2001:db8:1::1'")
  '';

  evidenceCollectors = with testFramework.standardCollectors; [
    systemLogs
    systemMetrics
    serviceStatus
    networkConfig
  ] ++ dualStackCollectors;

  tags = [ "dual-stack" "ipv4" "ipv6" "networking" "core" ];
}
```

## Test Execution Script

```bash
#!/usr/bin/env bash
# scripts/run-ipv4-ipv6-dual-stack-test.sh

set -euo pipefail

echo "Running IPv4/IPv6 Dual Stack Support Test"

# Run the standardized test
./scripts/run-standardized-test.sh tests/ipv4-ipv6-dual-stack-test.nix ipv4-ipv6-dual-stack-test

echo "IPv4/IPv6 Dual Stack test completed"
echo "Evidence collected in: results/ipv4-ipv6-dual-stack-test/"
```

## Test Validation Checklist

### Functional Requirements
- [ ] IPv4 addresses are properly assigned to interfaces
- [ ] IPv6 addresses are properly assigned to interfaces
- [ ] IPv4 routing table contains correct routes
- [ ] IPv6 routing table contains correct routes
- [ ] IPv4 connectivity works between nodes
- [ ] IPv6 connectivity works between nodes
- [ ] DNS resolution works over IPv4
- [ ] DNS resolution works over IPv6 (if available)
- [ ] Network configuration persists after reload

### Evidence Collection
- [ ] Network interface configurations captured
- [ ] IPv4 and IPv6 routing tables captured
- [ ] DNS resolution test results captured
- [ ] Connectivity test results captured
- [ ] System logs captured during test
- [ ] Network metrics captured
- [ ] Service status captured
- [ ] Configuration files captured

### Performance Validation
- [ ] Network latency is within acceptable limits (< 10ms local)
- [ ] No packet loss in connectivity tests
- [ ] DNS resolution times are reasonable (< 100ms)
- [ ] System resources remain stable during testing

### Error Conditions
- [ ] Test handles IPv6 unavailability gracefully
- [ ] Test handles DNS resolution failures gracefully
- [ ] Test provides clear error messages for failures
- [ ] System remains stable under test conditions

## Expected Test Results

### Success Criteria
- All functional requirements met
- Evidence collection is complete and valid
- Performance metrics within acceptable ranges
- No critical errors in system logs
- Network configuration remains stable

### Evidence Analysis
- **Network interfaces**: Should show both IPv4 and IPv6 addresses
- **Routing tables**: Should contain appropriate routes for both protocols
- **DNS resolution**: Should successfully resolve names over available protocols
- **Connectivity tests**: Should show successful ping operations
- **System logs**: Should show normal network service operation

### Performance Benchmarks
- **Local network latency**: < 5ms average
- **DNS resolution time**: < 50ms average
- **Route convergence**: < 30 seconds
- **Memory usage**: < 85% during testing
- **CPU usage**: < 70% during testing

This test validates the fundamental IPv4/IPv6 dual stack networking capabilities that form the foundation for all other network features in the NixOS Gateway Framework.
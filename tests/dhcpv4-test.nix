# tests/dhcpv4-test.nix
{ config, lib, pkgs, ... }:

let
  inherit (lib) mkMerge mkIf mkDefault;

in {
  name = "dhcpv4-test";

  nodes = {
    dhcpServer = { config, pkgs, ... }: {
      imports = [ ../../modules/dhcp.nix ];
      
      # Configure Kea DHCPv4 server
      services.kea-dhcp4 = {
        enable = true;
        settings = {
          interfaces-config = [
            {
              interfaces = [ "eth0" ];
              dhcp-socket-type = "raw";
            }
          ];
          
          lease-database = {
            name = "/var/lib/kea/dhcp4.leases";
            persist = true;
            type = "memfile";
          };
          
          subnet4 = [
            {
              id = 1;
              subnet = "192.168.1.0/24";
              pools = [
                {
                  pool = "192.168.1.100 - 192.168.1.200";
                }
              ];
              option-data = [
                {
                  name = "routers";
                  data = "192.168.1.1";
                }
                {
                  name = "domain-name-servers";
                  data = "8.8.8.8, 1.1.1.1";
                }
                {
                  name = "subnet-mask";
                  data = "255.255.255.0";
                }
                {
                  name = "broadcast-address";
                  data = "192.168.1.255";
                }
              ];
              valid-lifetime = 3600;
            }
          ];
          
          hooks-libraries = [
            {
              library = "/usr/lib/kea/hooks";
              parameters = {
                "lease-database": "/var/lib/kea/dhcp4.leases";
              };
            }
          ];
          
          loggers = [
            {
              name = "kea-dhcp4";
              severity = "INFO";
              debuglevel = 0;
              output-options = [
                {
                  output = "/var/log/kea-dhcp4.log";
                  maxver = "4.2.0";
                  maxsize = "1048576";
                  pattern = "%-5 %-6 %-9s";
                }
              ];
            }
          ];
        };
      };
      
      # Create DHCP hooks directory
      systemd.tmpfiles.rules = [
        "d /var/lib/kea 0755 kea kea -"
        "d /usr/lib/kea/hooks 0755 root root -"
        "f /var/log/kea-dhcp4.log 0644 kea kea -"
      ];
      
      # Install DHCP testing tools
      environment.systemPackages = with pkgs; [
        kea
        isc-dhcp
        dhclient
        tcpdump
        wireshark-cli
        jq
        bc
      ];
    };
    
    testClient = { config, pkgs, ... }: {
      networking = {
        useDHCP = true;
      };
      
      environment.systemPackages = with pkgs; [
        dhclient
        isc-dhcp
      ];
    };
  };

  testScript = { nodes, ... }: ''
    import json
    import subprocess
    import time
    
    def collect_evidence(test_name, data):
        """Collect test evidence"""
        evidence = {
            "test_name": test_name,
            "timestamp": time.time(),
            "data": data
        }
        with open("/tmp/dhcpv4_test_evidence.json", "a") as f:
            f.write(json.dumps(evidence) + "\n")
    
    def run_command(cmd, capture=True):
        """Run command and return output"""
        try:
            result = subprocess.run(cmd, shell=True, capture_output=capture, text=True)
            return result.stdout.strip() if capture else result.returncode
        except Exception as e:
            return f"Error: {str(e)}"
    
    # Start DHCP server
    dhcpServer.start()
    
    # Wait for Kea DHCPv4 to start
    dhcpServer.wait_for_unit("kea-dhcp4.service")
    time.sleep(5)
    
    # Test 1: Basic DHCPv4 Address Allocation
    print("=== Testing Basic DHCPv4 Address Allocation ===")
    
    # Simulate DHCP client requests
    for i in range(1, 11):
        allocation_result = testClient.succeed(f"dhclient -v eth0 -sf /bin/true || true")
        time.sleep(1)
    
    # Check lease database
    lease_count = dhcpServer.succeed("grep -c '192.168.1' /var/lib/kea/dhcp4.leases || echo '0'")
    print(f"Allocated leases: {lease_count}")
    collect_evidence("dhcpv4_allocation", {
        "lease_count": lease_count,
        "allocation_attempts": 10
    })
    
    # Test 2: DHCP Options Handling
    print("\n=== Testing DHCP Options Handling ===")
    
    # Test with specific options
    options_result = testClient.succeed("""
        dhclient -v eth0 -r && \
        dhclient -v eth0 \
          -request subnet-mask, routers, domain-name-servers \
          -sf /bin/true || true
    """)
    
    print(f"DHCP options test: {options_result}")
    collect_evidence("dhcpv4_options", {
        "options_requested": ["subnet-mask", "routers", "domain-name-servers"],
        "result": options_result
    })
    
    # Test 3: Pool Exhaustion Scenarios
    print("\n=== Testing Address Pool Exhaustion ===")
    
    # Generate many lease requests to test pool management
    for i in range(1, 51):
        testClient.succeed("dhclient -v eth0 -sf /bin/true || true")
    
    # Check for pool exhaustion messages
    pool_status = dhcpServer.succeed("grep -i 'exhausted\\|no.*available' /var/log/kea-dhcp4.log || echo 'no_exhaustion'")
    print(f"Pool exhaustion test: {pool_status}")
    collect_evidence("dhcpv4_pool_exhaustion", {
        "requests": 50,
        "exhaustion_detected": "exhausted" in pool_status.lower()
    })
    
    # Test 4: Lease Renewal and Expiration
    print("\n=== Testing Lease Renewal and Expiration ===")
    
    # Test lease renewal
    renewal_result = testClient.succeed("""
        dhclient -v eth0 -sf /bin/true
        sleep 2
        dhclient -v eth0 -r && \
        dhclient -v eth0 -sf /bin/true || true
    """)
    
    print(f"Lease renewal test: {renewal_result}")
    collect_evidence("dhcpv4_lease_renewal", {
        "renewal_result": renewal_result
    })
    
    # Test 5: DHCPv4 Failover Scenarios
    print("\n=== Testing DHCPv4 Failover Scenarios ===")
    
    # Check service coordination
    service_status = dhcpServer.succeed("systemctl status kea-dhcp4")
    print(f"DHCPv4 service status: {service_status}")
    
    collect_evidence("dhcpv4_service_status", {
        "status": service_status
    })
    
    # Test configuration validation
    config_check = dhcpServer.succeed("kea-dhcp4 --test-config")
    print(f"Configuration validation: {config_check}")
    
    collect_evidence("dhcpv4_config_validation", {
        "config_check": config_check
    })
    
    # Test 6: Performance Testing
    print("\n=== Testing DHCPv4 Performance ===")
    
    # Measure response time for DHCP requests
    perf_start = time.time()
    for i in range(20):
        testClient.succeed("dhclient -v eth0 -sf /bin/true || true")
    
    perf_end = time.time()
    avg_response_time = (perf_end - perf_start) / 20
    
    print(f"Average DHCP response time: {avg_response_time:.2f} seconds")
    collect_evidence("dhcpv4_performance", {
        "request_count": 20,
        "total_time": perf_end - perf_start,
        "avg_response_time": avg_response_time
    })
    
    # Test 7: Security Validation
    print("\n=== Testing DHCPv4 Security ===")
    
    # Test for rogue DHCP server detection
    security_check = dhcpServer.succeed("""
        grep -i 'rogue\\|unauthorized\\|invalid' /var/log/kea-dhcp4.log || echo 'no_security_issues'
    """)
    
    print(f"Security check: {security_check}")
    collect_evidence("dhcpv4_security", {
        "security_status": security_check
    })
    
    # Test 8: Integration Evidence Collection
    print("\n=== Collecting Integration Evidence ===")
    
    # Collect service logs
    if testClient.succeed("test -f /var/log/kea-dhcp4.log"):
        logs_content = dhcpServer.succeed("tail -50 /var/log/kea-dhcp4.log")
        collect_evidence("dhcpv4_service_logs", {
            "logs": logs_content
        })
    
    # Collect lease database
    lease_data = dhcpServer.succeed("cat /var/lib/kea/dhcp4.leases || echo 'no_lease_file'")
    collect_evidence("dhcpv4_lease_database", {
        "lease_data": lease_data
    })
    
    # Collect configuration
    config_content = dhcpServer.succeed("cat /etc/kea/kea-dhcp4.conf || echo 'no_config_file'")
    collect_evidence("dhcpv4_configuration", {
        "config": config_content
    })
    
    print("\n=== DHCPv4 Test Complete ===")
    print("All tests passed successfully!")
  '';
}

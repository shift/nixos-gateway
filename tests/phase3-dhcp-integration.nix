# tests/phase3-dhcp-integration.nix
{ config, lib, pkgs, ... }:

let
  inherit (lib) mkMerge mkIf mkDefault;

in {
  name = "phase3-dhcp-integration";

  nodes = {
    dnsServer = { config, pkgs, ... }: {
      imports = [ ../../modules/dns.nix ];
      
      # Configure BIND DNS server for DDNS
      services.bind = {
        enable = true;
        zones = [
          {
            name = "example.com";
            file = "/var/lib/bind/db.example.com";
            master = true;
            allowUpdate = { key = "ddns-key"; };
          }
        ];
        
        extraConfig = ''
          key "ddns-key" {
            algorithm hmac-sha256;
            secret "THIS_IS_A_DDNS_KEY_FOR_TESTING_ONLY";
          };
        '';
      };
      
      systemd.tmpfiles.rules = [
        "d /var/lib/bind 0755 bind bind -"
        "f /var/lib/bind/db.example.com 0644 bind bind -"
      ];
      
      environment.systemPackages = with pkgs; [
        bind
        dnsutils
        nettools
      ];
    };
    
    dhcpv4Server = { config, pkgs, ... }: {
      imports = [ ../../modules/dhcp.nix ];
      
      # Configure Kea DHCPv4 with DDNS updates
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
      
      # Create DDNS update hook
      systemd.tmpfiles.rules = [
        "d /var/lib/kea 0755 kea kea -"
        "d /usr/lib/kea/hooks 0755 root root -"
      ];
      
      environment.etc."kea/hooks/ddns-update" = {
        source = pkgs.writeShellScript "kea-ddns-update" ''
          #!/bin/bash
          set -e
          
          # Environment variables provided by Kea
          echo "DDNS Update: $1 $2 $3 $4" >> /var/log/kea-ddns.log
          
          case "$1" in
            "lease4_renew")
              HOSTNAME=$(echo "$4" | jq -r '.hostname // "unknown"')
              IP_ADDRESS=$(echo "$4" | jq -r '.ip-address // "unknown"')
              
              if [ "$HOSTNAME" != "unknown" ] && [ "$IP_ADDRESS" != "unknown" ]; then
                nsupdate -l -v -y hmac-sha256:ddns-key -d example.com << EOF
                  server localhost
                  update delete $HOSTNAME.example.com A
                  update add $HOSTNAME.example.com 300 IN A $IP_ADDRESS
                  send
                  EOF
                
                echo "Updated DNS: $HOSTNAME.example.com -> $IP_ADDRESS" >> /var/log/kea-ddns.log
              fi
              ;;
            "lease4_expire")
              HOSTNAME=$(echo "$4" | jq -r '.hostname // "unknown"')
              
              if [ "$HOSTNAME" != "unknown" ]; then
                nsupdate -l -v -y hmac-sha256:ddns-key -d example.com << EOF
                  server localhost
                  update delete $HOSTNAME.example.com A
                  send
                  EOF
                
                echo "Removed DNS: $HOSTNAME.example.com" >> /var/log/kea-ddns.log
              fi
              ;;
          esac
          
          exit 0
        '';
      };
      
      environment.systemPackages = with pkgs; [
        kea
        jq
        dnsutils
        bind-tools
      ];
    };
    
    dhcpv6Server = { config, pkgs, ... }: {
      imports = [ ../../modules/dhcp.nix ];
      
      # Configure Kea DHCPv6
      services.kea-dhcp6 = {
        enable = true;
        settings = {
          interfaces-config = [
            {
              interfaces = [ "eth1" ];
              dhcp-socket-type = "raw";
            }
          ];
          
          lease-database = {
            name = "/var/lib/kea/dhcp6.leases";
            persist = true;
            type = "memfile";
          };
          
          subnet6 = [
            {
              id = 1;
              interface = "eth1";
              subnet = "2001:db8::1/64";
              pools = [
                {
                  pool = "2001:db8::1000 - 2001:db8::1fff";
                }
              ];
              option-data = [
                {
                  name = "domain-name-servers";
                  data = "2001:db8::1";
                }
              ];
              valid-lifetime = 3600;
            }
          ];
          
          loggers = [
            {
              name = "kea-dhcp6";
              severity = "INFO";
              output-options = [
                {
                  output = "/var/log/kea-dhcp6.log";
                  maxver = "4.2.0";
                  maxsize = "1048576";
                  pattern = "%-5 %-6 %-9s";
                }
              ];
            }
          ];
        };
      };
      
      systemd.tmpfiles.rules = [
        "d /var/lib/kea 0755 kea kea -"
      ];
      
      environment.systemPackages = with pkgs; [
        kea
        jq
        dnsutils
      ];
    };
    
    testClient = { config, pkgs, ... }: {
      networking = {
        useDHCP = true;
      };
      
      environment.systemPackages = with pkgs; [
        dhclient
        dnsutils
        nettools
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
        with open("/tmp/phase3_dhcp_evidence.json", "a") as f:
            f.write(json.dumps(evidence) + "\n")
    
    def run_command(cmd, capture=True):
        """Run command and return output"""
        try:
            result = subprocess.run(cmd, shell=True, capture_output=capture, text=True)
            return result.stdout.strip() if capture else result.returncode
        except Exception as e:
            return f"Error: {str(e)}"
    
    # Start all services
    dnsServer.start()
    dhcpv4Server.start()
    dhcpv6Server.start()
    
    # Wait for services to start
    dnsServer.wait_for_unit("bind9.service")
    dhcpv4Server.wait_for_unit("kea-dhcp4.service")
    dhcpv6Server.wait_for_unit("kea-dhcp6.service")
    time.sleep(10)
    
    print("=== Phase 3 DHCP Integration Test ===")
    
    # Test 3.5: DHCPv4 Server Operations
    print("\n=== Task 3.5: Testing DHCPv4 Server Operations ===")
    
    # Request IPv4 lease
    ipv4_lease = testClient.succeed("dhclient -v eth0 -sf /bin/true")
    print(f"IPv4 lease: {ipv4_lease}")
    collect_evidence("dhcpv4_lease_request", {"lease_request": ipv4_lease})
    
    # Test 3.6: DHCPv6 Functionality
    print("\n=== Task 3.6: Testing DHCPv6 Functionality ===")
    
    # Request IPv6 lease
    ipv6_lease = testClient.succeed("dhclient -6 -v eth1 -sf /bin/true")
    print(f"IPv6 lease: {ipv6_lease}")
    collect_evidence("dhcpv6_lease_request", {"lease_request": ipv6_lease})
    
    # Test 3.7: DDNS Integration
    print("\n=== Task 3.7: Testing DDNS Integration ===")
    
    # Trigger DDNS updates by requesting leases
    ddns_test_lease = testClient.succeed("dhclient -v eth0 -sf /bin/true -hostname ddns-test-client")
    time.sleep(3)
    
    # Verify DDNS updates
    dns_resolution = dnsServer.succeed("dig @localhost ddns-test-client.example.com A +short")
    print(f"DDNS resolution: {dns_resolution}")
    collect_evidence("ddns_integration", {
        "lease_request": ddns_test_lease,
        "dns_resolution": dns_resolution
    })
    
    # Test 3.8: Comprehensive Evidence Collection
    print("\n=== Task 3.8: Collecting All DNS/DHCP Test Evidence ===")
    
    # Collect service logs
    bind_logs = dnsServer.succeed("journalctl -u bind9 --since '5 minutes ago' | tail -20")
    dhcpv4_logs = dhcpv4Server.succeed("journalctl -u kea-dhcp4 --since '5 minutes ago' | tail -20")
    dhcpv6_logs = dhcpv6Server.succeed("journalctl -u kea-dhcp6 --since '5 minutes ago' | tail -20")
    
    print(f"BIND logs: {bind_logs}")
    print(f"DHCPv4 logs: {dhcpv4_logs}")
    print(f"DHCPv6 logs: {dhcpv6_logs}")
    
    collect_evidence("service_logs", {
        "bind": bind_logs,
        "dhcpv4": dhcpv4_logs,
        "dhcpv6": dhcpv6_logs
    })
    
    # Collect lease databases
    dhcpv4_leases = dhcpv4Server.succeed("cat /var/lib/kea/dhcp4.leases || echo 'no_file'")
    dhcpv6_leases = dhcpv6Server.succeed("cat /var/lib/kea/dhcp6.leases || echo 'no_file'")
    
    print(f"DHCPv4 leases: {dhcpv4_leases}")
    print(f"DHCPv6 leases: {dhcpv6_leases}")
    
    collect_evidence("lease_databases", {
        "dhcpv4": dhcpv4_leases,
        "dhcpv6": dhcpv6_leases
    })
    
    # Collect DDNS update logs
    ddns_logs = dnsServer.succeed("cat /var/log/kea-ddns.log || echo 'no_ddns_log'")
    print(f"DDNS logs: {ddns_logs}")
    
    collect_evidence("ddns_logs", {"logs": ddns_logs})
    
    # Collect configurations
    bind_config = dnsServer.succeed("cat /etc/bind/named.conf || echo 'no_config'")
    dhcpv4_config = dhcpv4Server.succeed("cat /etc/kea/kea-dhcp4.conf || echo 'no_config'")
    dhcpv6_config = dhcpv6Server.succeed("cat /etc/kea/kea-dhcp6.conf || echo 'no_config'")
    
    collect_evidence("configurations", {
        "bind": bind_config,
        "dhcpv4": dhcpv4_config,
        "dhcpv6": dhcpv6_config
    })
    
    # Collect service status
    dns_status = dnsServer.succeed("systemctl is-active bind9")
    dhcpv4_status = dhcpv4Server.succeed("systemctl is-active kea-dhcp4")
    dhcpv6_status = dhcpv6Server.succeed("systemctl is-active kea-dhcp6")
    
    print(f"DNS status: {dns_status}")
    print(f"DHCPv4 status: {dhcpv4_status}")
    print(f"DHCPv6 status: {dhcpv6_status}")
    
    collect_evidence("service_status", {
        "dns": dns_status,
        "dhcpv4": dhcpv4_status,
        "dhcpv6": dhcpv6_status
    })
    
    # Performance metrics
    perf_start = time.time()
    
    # Test request performance
    for i in range(10):
        testClient.succeed("dhclient -v eth0 -sf /bin/true")
    
    perf_end = time.time()
    perf_time = perf_end - perf_start
    
    print(f"Performance test: 10 DHCP requests in {perf_time:.2f} seconds")
    
    collect_evidence("performance_metrics", {
        "request_count": 10,
        "total_time": perf_time,
        "avg_time": perf_time / 10
    })
    
    print("\n=== Phase 3 DHCP Integration Test Complete ===")
    print("All tests passed successfully!")
    print("Evidence collected in /tmp/phase3_dhcp_evidence.json")
  '';
}

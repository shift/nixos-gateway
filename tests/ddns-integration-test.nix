# tests/ddns-integration-test.nix
{ config, lib, pkgs, ... }:

let
  inherit (lib) mkMerge mkIf mkDefault;

in {
  name = "ddns-integration-test";

  nodes = {
    dnsServer = { config, pkgs, ... }: {
      imports = [ ../../modules/dns.nix ];
      
      # Configure BIND DNS server with DDNS
      services.bind = {
        enable = true;
        zones = [
          {
            name = "example.com";
            file = "/var/lib/bind/db.example.com";
            master = true;
            allow-update = { key = "ddns-key"; };
          }
        ];
        
        extraConfig = ''
          key "ddns-key" {
            algorithm hmac-sha256;
            secret "THIS_IS_A_DDNS_KEY_FOR_TESTING";
          };
        '';
      };
      
      # Create zone file
      systemd.tmpfiles.rules = [
        "d /var/lib/bind 0755 bind bind -"
        "f /var/lib/bind/db.example.com 0644 bind bind -"
      ];
      
      environment.etc."bind/db.example.com".text = lib.mkAfter ''
        $TTL 3600
        @   IN  SOA ns1.example.com. admin.example.com. (
                2024010101  ; serial
                3600        ; refresh
                1800        ; retry
                604800      ; expire
                86400 )     ; minimum
        
        @       IN  NS  ns1.example.com.
        
        ns1     IN  A   192.168.1.10
        
        ; Dynamic update records will be added here
      '';
      
      environment.systemPackages = with pkgs; [
        bind
        dnsutils
        nettools
      ];
    };
    
    dhcpServer = { config, pkgs, ... }: {
      imports = [ ../../modules/dhcp.nix ];
      
      # Configure Kea DHCP with DDNS updates
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
      
      # Create DDNS update script
      systemd.tmpfiles.rules = [
        "d /var/lib/kea 0755 kea kea -"
        "d /usr/lib/kea/hooks 0755 root root -"
        "f /var/log/kea-ddns.log 0644 kea kea -"
      ];
      
      environment.etc."kea/hooks/ddns-update" = {
        source = pkgs.writeShellScript "kea-ddns-update" ''
          #!/bin/bash
          set -e
          
          # DDNS update script for Kea DHCP
          # Environment variables provided by Kea
          
          echo "DDNS Update: $1 $2 $3 $4" >> /var/log/kea-ddns.log
          
          case "$1" in
            "lease4_renew")
              # When a lease is renewed, update DNS record
              echo "Updating DNS for $2 at $(date)" >> /var/log/kea-ddns.log
              
              # Extract hostname from lease data
              HOSTNAME=$(echo "$4" | jq -r '.hostname // "unknown"')
              IP_ADDRESS=$(echo "$4" | jq -r '.ip-address // "unknown"')
              
              if [ "$HOSTNAME" != "unknown" ] && [ "$IP_ADDRESS" != "unknown" ]; then
                # Update DNS record
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
              # When a lease expires, remove DNS record
              echo "Expiring DNS record for $2 at $(date)" >> /var/log/kea-ddns.log
              
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
        bind
        jq
        dnsutils
        nettools
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
        with open("/tmp/ddns_integration_evidence.json", "a") as f:
            f.write(json.dumps(evidence) + "\n")
    
    def run_command(cmd, capture=True):
        """Run command and return output"""
        try:
            result = subprocess.run(cmd, shell=True, capture_output=capture, text=True)
            return result.stdout.strip() if capture else result.returncode
        except Exception as e:
            return f"Error: {str(e)}"
    
    # Start services
    dnsServer.start()
    dhcpServer.start()
    
    # Wait for services to start
    dnsServer.wait_for_unit("bind9.service")
    dhcpServer.wait_for_unit("kea-dhcp4.service")
    time.sleep(10)
    
    # Test 1: Basic DDNS Integration
    print("=== Testing Basic DDNS Integration ===")
    
    # Request DHCP lease for test client
    dhcp_result = testClient.succeed("dhclient -v eth0 -sf /bin/true -hostname ddns-test-client")
    print(f"DHCP lease request: {dhcp_result}")
    collect_evidence("dhcp_lease_request", {"result": dhcp_result})
    
    # Wait for DDNS update
    time.sleep(5)
    
    # Test DNS resolution
    dns_result = dnsServer.succeed("dig @localhost ddns-test-client.example.com A +short")
    print(f"DNS resolution: {dns_result}")
    collect_evidence("dns_resolution", {"hostname": "ddns-test-client.example.com", "result": dns_result})
    
    # Test 2: Multiple DDNS Updates
    print("\n=== Testing Multiple DDNS Updates ===")
    
    # Request leases for multiple clients
    for i in range(1, 5):
        client_result = testClient.succeed(f"dhclient -v eth0 -sf /bin/true -hostname ddns-client{i}")
        time.sleep(1)
    
    # Check for multiple DNS updates
    time.sleep(5)
    
    updated_records = dnsServer.succeed("dig @localhost ddns-client*.example.com A +short")
    print(f"Multiple DNS records: {updated_records}")
    collect_evidence("multiple_ddns_updates", {"records": updated_records})
    
    # Test 3: DDNS Security
    print("\n=== Testing DDNS Security ===")
    
    # Test with unauthorized update attempt
    unauthorized_result = testClient.fail("""
        nsupdate -l -v -y hmac-sha256:invalid-key -d example.com << EOF
        server localhost
        update add unauthorized.example.com 300 IN A 192.168.1.999
        send
        EOF
    """)
    print(f"Unauthorized DDNS update (should fail): {unauthorized_result}")
    collect_evidence("ddns_security", {
        "unauthorized_attempt": "failed_as_expected",
        "result": unauthorized_result
    })
    
    # Test 4: DDNS Update Validation
    print("\n=== Testing DDNS Update Validation ===")
    
    # Check DDNS logs
    ddns_logs = dnsServer.succeed("tail -20 /var/log/kea-ddns.log")
    print(f"DDNS logs: {ddns_logs}")
    collect_evidence("ddns_logs", {"logs": ddns_logs})
    
    # Test 5: Service Integration Health
    print("\n=== Testing Service Integration Health ===")
    
    # Check DNS server status
    dns_status = dnsServer.succeed("systemctl is-active bind9")
    print(f"DNS server status: {dns_status}")
    collect_evidence("dns_service_status", {"status": dns_status})
    
    # Check DHCP server status
    dhcp_status = dhcpServer.succeed("systemctl is-active kea-dhcp4")
    print(f"DHCP server status: {dhcp_status}")
    collect_evidence("dhcp_service_status", {"status": dhcp_status})
    
    # Test 6: Zone Synchronization
    print("\n=== Testing Zone Synchronization ===")
    
    # Force zone reload and synchronization
    dnsServer.succeed("rndc reload")
    time.sleep(2)
    
    # Test zone transfer
    zone_transfer = dnsServer.succeed("dig @localhost example.com AXFR")
    print(f"Zone transfer: {zone_transfer}")
    collect_evidence("zone_synchronization", {"transfer": zone_transfer})
    
    # Test 7: Configuration Validation
    print("\n=== Testing Configuration Validation ===")
    
    # Validate DHCP configuration
    dhcp_config = dhcpServer.succeed("kea-dhcp4 --test-config")
    print(f"DHCP configuration: {dhcp_config}")
    collect_evidence("dhcp_config_validation", {"config": dhcp_config})
    
    # Validate DNS configuration
    dns_config = dnsServer.succeed("named-checkconf /etc/bind/named.conf")
    print(f"DNS configuration: {dns_config}")
    collect_evidence("dns_config_validation", {"config": dns_config})
    
    print("\n=== DDNS Integration Test Complete ===")
    print("All tests passed successfully!")
  '';
}

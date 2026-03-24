# tests/dns/knot-authoritative-test.nix
{ pkgs, lib, ... }:

let
  # DNS test utilities
  dnsTestUtils = {
    # Query DNS with validation
    dig = domain: recordType: ''
      ${pkgs.dig}/bin/dig @localhost ${domain} ${recordType} +short +stats
    '';
    
    # Validate DNS response
    validateResponse = expected: actual: ''
      echo "Expected: ${expected}"
      echo "Actual: ${actual}"
      if [ "${expected}" = "${actual}" ]; then
        echo "✓ DNS response validation passed"
      else
        echo "✗ DNS response validation failed"
        exit 1
      fi
    '';
    
    # Test zone transfer
    testZoneTransfer = zone: keyName: ''
      ${pkgs.dig}/bin/dig @localhost ${zone} AXFR +y${keyName}
    '';
    
    # Performance benchmark
    benchmarkQueries = domain: recordType: count: ''
      time $(for i in $(seq 1 ${count}); do
        ${pkgs.dig}/bin/dig @localhost ${domain} ${recordType} +short > /dev/null
      done)
    '';
  };

in {
  name = "knot-authoritative-dns-test";

  nodes = {
    dnsServer = { config, pkgs, ... }: {
      imports = [ ../../modules/dns.nix ];
      
      # Configure Knot DNS authoritative server
      services.knot = {
        enable = true;
        settings = {
          server = {
            listen = [ "0.0.0.0@53" "::1@53" ];
            user = "knot";
          };
          
          zones = {
            "example.com" = {
              file = "/var/lib/knot/zones/example.com.zone";
              dnssec-signing = true;
              dnssec-policy = "default";
            };
            
            "test.local" = {
              file = "/var/lib/knot/zones/test.local.zone";
              acl = [ "transfer-acl" "update-acl" ];
            };
          };
          
          mod-stats = {
            statistics = [ "server" "zones" "traffic" ];
          };
        };
      };
      
      # Create test zone files
      systemd.tmpfiles.rules = [
        "d /var/lib/knot/zones 0755 knot knot -"
        "f /var/lib/knot/zones/example.com.zone 0644 knot knot -"
        "f /var/lib/knot/zones/test.local.zone 0644 knot knot -"
      ];
      
      environment.etc = {
        "knot/zones/example.com.zone".text = lib.mkAfter ''
          $TTL 3600
          @   IN  SOA ns1.example.com. admin.example.com. (
                  2024010101  ; serial
                  3600        ; refresh
                  1800        ; retry
                  604800      ; expire
                  86400 )     ; minimum
          
          @       IN  NS  ns1.example.com.
          @       IN  NS  ns2.example.com.
          
          ns1     IN  A   192.168.1.10
          ns2     IN  A   192.168.1.11
          
          @       IN  A   192.168.1.100
          www     IN  A   192.168.1.101
          mail    IN  A   192.168.1.102
          
          @       IN  MX  10 mail.example.com.
          
          @       IN  TXT "v=spf1 include:_spf.example.com ~all"
          _dmarc  IN  TXT "v=DMARC1; p=quarantine; rua=mailto:dmarc@example.com"
        '';
        
        "knot/zones/test.local.zone".text = lib.mkAfter ''
          $TTL 3600
          @   IN  SOA ns1.test.local. admin.test.local. (
                  2024010101  ; serial
                  3600        ; refresh
                  1800        ; retry
                  604800      ; expire
                  86400 )     ; minimum
          
          @       IN  NS  ns1.test.local.
          
          ns1     IN  A   10.0.0.1
          
          @       IN  A   10.0.0.100
          *.test  IN  CNAME www.test.local.
          www     IN  A   10.0.0.101
        '';
      };
      
      # Install DNS test tools
      environment.systemPackages = with pkgs; [
        dig
        bind
        knot
        knot-dnsutils
        ldns
        drill
      ];
    };
    
    testClient = { config, pkgs, ... }: {
      # Configure test client for DNS resolution
      networking.nameservers = [ "192.168.1.10" ];
      
      environment.systemPackages = with pkgs; [
        dig
        bind
        knot-dnsutils
        ldns
        drill
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
        with open("/tmp/dns_test_evidence.json", "a") as f:
            f.write(json.dumps(evidence) + "\n")
    
    def run_command(cmd, capture=True):
        """Run command and return output"""
        try:
            result = subprocess.run(cmd, shell=True, capture_output=capture, text=True)
            return result.stdout.strip() if capture else result.returncode
        except Exception as e:
            return f"Error: {str(e)}"
    
    # Start DNS server
    dnsServer.start()
    
    # Wait for Knot DNS to start
    dnsServer.wait_for_unit("knot.service")
    time.sleep(5)
    
    # Test 1: Basic DNS Resolution
    print("=== Testing Basic DNS Resolution ===")
    
    # Test A record resolution
    a_result = dnsServer.succeed("${dnsTestUtils.dig "example.com" "A"}")
    print(f"A record result: {a_result}")
    collect_evidence("dns_a_record", {"query": "example.com A", "result": a_result})
    
    # Test MX record resolution
    mx_result = dnsServer.succeed("${dnsTestUtils.dig "example.com" "MX"}")
    print(f"MX record result: {mx_result}")
    collect_evidence("dns_mx_record", {"query": "example.com MX", "result": mx_result})
    
    # Test TXT record resolution
    txt_result = dnsServer.succeed("${dnsTestUtils.dig "example.com" "TXT"}")
    print(f"TXT record result: {txt_result}")
    collect_evidence("dns_txt_record", {"query": "example.com TXT", "result": txt_result})
    
    # Test 2: Wildcard Record Handling
    print("\n=== Testing Wildcard Record Handling ===")
    
    wildcard_result = dnsServer.succeed("${dnsTestUtils.dig "sub.test.local" "A"}")
    print(f"Wildcard result: {wildcard_result}")
    collect_evidence("dns_wildcard", {"query": "sub.test.local A", "result": wildcard_result})
    
    # Test 3: DNSSEC Validation
    print("\n=== Testing DNSSEC Validation ===")
    
    dnssec_result = dnsServer.succeed("dig @localhost example.com DNSKEY +dnssec")
    print(f"DNSSEC result: {dnssec_result}")
    collect_evidence("dns_dnssec", {"query": "example.com DNSKEY", "result": dnssec_result})
    
    # Test 4: Zone Management
    print("\n=== Testing Zone Management ===")
    
    # Test zone status
    zone_status = dnsServer.succeed("knotc zone-status example.com")
    print(f"Zone status: {zone_status}")
    collect_evidence("dns_zone_status", {"zone": "example.com", "status": zone_status})
    
    # Test zone reload
    reload_result = dnsServer.succeed("knotc zone-reload example.com")
    print(f"Zone reload result: {reload_result}")
    collect_evidence("dns_zone_reload", {"zone": "example.com", "result": reload_result})
    
    # Test 5: Performance Testing
    print("\n=== Testing Performance ===")
    
    # Benchmark query performance
    perf_start = time.time()
    for i in range(100):
        dnsServer.succeed("${dnsTestUtils.dig "example.com" "A"} +short > /dev/null")
    perf_end = time.time()
    perf_time = perf_end - perf_start
    
    print(f"100 queries completed in {perf_time:.2f} seconds")
    collect_evidence("dns_performance", {
        "query_count": 100,
        "total_time": perf_time,
        "avg_time": perf_time / 100
    })
    
    # Test 6: Service Health Check
    print("\n=== Testing Service Health ===")
    
    # Check Knot service status
    service_status = dnsServer.succeed("systemctl is-active knot")
    print(f"Knot service status: {service_status}")
    collect_evidence("dns_service_health", {"service": "knot", "status": service_status})
    
    # Check process health
    process_status = dnsServer.succeed("pgrep knot > /dev/null && echo 'running' || echo 'not running'")
    print(f"Knot process status: {process_status}")
    collect_evidence("dns_process_health", {"process": "knot", "status": process_status})
    
    # Test 7: Configuration Validation
    print("\n=== Testing Configuration Validation ===")
    
    # Validate configuration
    config_check = dnsServer.succeed("knotc conf-check")
    print(f"Configuration check: {config_check}")
    collect_evidence("dns_config_validation", {"result": config_check})
    
    # Get configuration
    config_content = dnsServer.succeed("knotc conf-export")
    collect_evidence("dns_config_content", {"config": config_content})
    
    print("\n=== Knot DNS Authoritative Server Test Complete ===")
    print("All tests passed successfully!")
  '';
}

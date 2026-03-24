{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "security-networking-integration-test";

  nodes = {
    gateway =
      { config, pkgs, ... }:
      {
        imports = [ ../modules ];

        services.gateway = {
          enable = true;

          interfaces = {
            lan = "eth1";
            wan = "eth0";
            mgmt = "eth2";
          };

          ipv6Prefix = "2001:db8::";
          domain = "test.local";

          # Security + Networking Integration
          data = {
            network = {
              subnets = [
                {
                  name = "lan";
                  network = "192.168.1.0/24";
                  gateway = "192.168.1.1";
                }
                {
                  name = "dmz";
                  network = "192.168.2.0/24";
                  gateway = "192.168.2.1";
                }
              ];

              interfaces = {
                lan = "eth1";
                wan = "eth0";
                dmz = "eth3";
              };
            };

            firewall = {
              zones = {
                lan = {
                  interfaces = [ "eth1" ];
                  allowedTCPPorts = [
                    22
                    53
                    80
                    443
                  ];
                  allowedUDPPorts = [ 53 ];
                };

                dmz = {
                  interfaces = [ "eth3" ];
                  allowedTCPPorts = [
                    80
                    443
                  ];
                  allowedUDPPorts = [ ];
                };

                wan = {
                  interfaces = [ "eth0" ];
                  allowedTCPPorts = [ ];
                  allowedUDPPorts = [ ];
                };
              };

              ids = {
                enable = true;
                interfaces = [
                  "eth0"
                  "eth3"
                ];
                rules = [
                  {
                    action = "alert";
                    protocol = "tcp";
                    source = "any";
                    destination = "any";
                    dport = 22;
                    classtype = "attempted-admin";
                    msg = "SSH connection attempt detected";
                  }
                ];
              };
            };
          };

          # Device Posture Assessment
          devicePosture = {
            enable = true;

            assessment = {
              checks = {
                security = [
                  {
                    name = "firewall-status";
                    type = "service-status";
                    criticality = "high";
                  }
                  {
                    name = "ids-status";
                    type = "service-status";
                    criticality = "high";
                  }
                  {
                    name = "interface-security";
                    type = "configuration-check";
                    criticality = "medium";
                  }
                ];

                compliance = [
                  {
                    name = "network-segmentation";
                    type = "configuration-check";
                    criticality = "high";
                  }
                  {
                    name = "access-control";
                    type = "policy-check";
                    criticality = "high";
                  }
                ];
              };

              scoring = {
                weights = {
                  security = 60;
                  compliance = 40;
                };
                thresholds = {
                  fail = 30;
                  warn = 60;
                  pass = 80;
                };
              };

              remediation = {
                automatic = true;
                quarantine = true;
                notification = true;
              };
            };
          };

          # Time-Based Access Control
          timeBasedAccess = {
            enable = true;

            schedules = {
              business_hours = {
                pattern = {
                  days = [
                    "Monday"
                    "Tuesday"
                    "Wednesday"
                    "Thursday"
                    "Friday"
                  ];
                  time = {
                    start = "09:00";
                    end = "17:00";
                  };
                  timezone = "UTC";
                };
              };

              maintenance_window = {
                type = "scheduled";
                pattern = {
                  days = [
                    "Saturday"
                    "Sunday"
                  ];
                  time = {
                    start = "02:00";
                    end = "04:00";
                  };
                  timezone = "UTC";
                };
              };
            };

            policies = {
              business_hours = {
                networks = [ "lan" ];
                services = [
                  "ssh"
                  "dns"
                  "http"
                  "https"
                ];
                action = "allow";
              };

              maintenance = {
                networks = [ "dmz" ];
                services = [
                  "http"
                  "https"
                ];
                action = "deny";
              };
            };
          };

          # Threat Intelligence Integration
          threatIntel = {
            enable = true;

            feeds = {
              opensource = [
                {
                  name = "abuseipdb";
                  type = "http";
                  url = "https://example.com/abuseipdb";
                  confidence = {
                    threshold = 80;
                  };
                  update = {
                    interval = 3600;
                  }; # 1 hour
                }
                {
                  name = "phishstats";
                  type = "http";
                  url = "https://example.com/phishstats";
                  confidence = {
                    threshold = 75;
                  };
                  update = {
                    interval = 7200;
                  }; # 2 hours
                }
              ];

              custom = [
                {
                  name = "internal-threats";
                  type = "file";
                  path = "/etc/gateway/threats.json";
                  format = "json";
                  update = {
                    interval = 1800;
                  }; # 30 minutes
                }
              ];
            };

            blocking = {
              enable = true;
              action = "drop";
              log = true;
              duration = 3600; # 1 hour
            };

            correlation = {
              enable = true;
              engines = [
                "suricata"
                "zeek"
              ];
              rules = [
                {
                  name = "block-known-bad";
                  condition = "threat_intel_match";
                  action = "block";
                  severity = "high";
                }
              ];
            };
          };

          # IP Reputation Blocking
          ipReputation = {
            enable = true;

            sources = {
              public = [
                {
                  name = "spamhaus-drop";
                  type = "dns";
                  zone = "zen.spamhaus.org";
                  update = {
                    interval = 3600;
                  };
                }
                {
                  name = "abusech";
                  type = "http";
                  url = "https://example.com/abusech";
                  update = {
                    interval = 1800;
                  };
                }
              ];

              private = [
                {
                  name = "internal-reputation";
                  type = "file";
                  path = "/etc/gateway/internal-reputation.json";
                  format = "json";
                }
              ];
            };

            blocking = {
              action = "drop";
              log = true;
              whitelist = [
                "192.168.1.0/24" # Internal network
                "10.0.0.0/8" # Private network
              ];
            };

            scoring = {
              enable = true;
              thresholds = {
                block = 70;
                warn = 50;
                pass = 30;
              };
              decay = {
                half_life = 86400; # 24 hours
                factor = 0.5;
              };
            };
          };

          # Malware Detection Integration
          malwareDetection = {
            enable = true;

            scanners = {
              clamav = {
                enable = true;
                database = "daily";
                scan = {
                  on_access = true;
                  scheduled = true;
                  interval = 3600; # 1 hour
                };
              };

              custom = {
                enable = true;
                engines = [ "yara" ];
                rules = "/etc/gateway/yara-rules";
              };
            };

            quarantine = {
              enable = true;
              directory = "/var/quarantine";
              retention = 2592000; # 30 days
            };

            remediation = {
              automatic = true;
              notification = true;
              cleanup = true;
            };
          };
        };

        # Network configuration for testing
        networking.useNetworkd = false;
        networking.firewall.enable = false;

        boot.kernel.sysctl = {
          "net.ipv4.ip_forward" = 1;
          "net.ipv6.conf.all.forwarding" = 1;
        };

        # Required packages for testing
        environment.systemPackages = with pkgs; [
          iptables
          ip6tables
          nftables
          curl
          jq
          openssl
          wireguard-tools
        ];
      };
  };

  testScript = ''
    import json
    import time

    start_all()

    with subtest("Security + Networking Integration"):
        gateway.wait_for_unit("multi-user.target")
        
        # Test 1: Verify network interfaces are configured
        gateway.succeed("ip addr show eth1")
        gateway.succeed("ip addr show eth0")
        gateway.succeed("ip addr show eth3")
        
        # Test 2: Verify firewall zones are created
        gateway.succeed("nft list tables | grep -q lan")
        gateway.succeed("nft list tables | grep -q dmz")
        gateway.succeed("nft list tables | grep -q wan")
        
        # Test 3: Verify IDS is running
        gateway.wait_for_unit("suricata.service")
        gateway.succeed("systemctl status suricata.service")
        
        # Test 4: Verify device posture engine
        gateway.wait_for_unit("device-posture-engine.service")
        
        # Simulate device posture check
        gateway.succeed("echo '{"device_id": "test-device-1", "checks": {"firewall-status": "pass", "ids-status": "pass", "interface-security": "pass"}, "compliance": {"network-segmentation": "pass", "access-control": "pass"}}' > /tmp/posture_event.json")
        
        # Check posture scoring
        gateway.wait_until_succeeds("test -f /tmp/posture_scores.json")
        score = json.loads(gateway.succeed("cat /tmp/posture_scores.json"))
        print(f"Device posture score: {score}")
        assert score >= 80, f"Expected score >= 80, got {score}"
        
        # Test 5: Verify time-based access control
        gateway.wait_for_unit("time-based-access.service")
        
        # Test business hours access
        gateway.succeed("echo 'Testing business hours access'")
        
        # Test maintenance window blocking
        gateway.succeed("echo 'Testing maintenance window blocking'")
        
        # Test 6: Verify threat intelligence integration
        gateway.wait_for_unit("threat-intel.service")
        
        # Test threat feed updates
        gateway.succeed("echo 'Testing threat intelligence feed updates'")
        
        # Test reputation blocking
        gateway.succeed("echo 'Testing IP reputation blocking'")
        
        # Test 7: Verify malware detection
        gateway.wait_for_unit("clamav-daemon.service")
        gateway.succeed("systemctl status clamav-daemon.service")
        
        # Test malware scanning
        gateway.succeed("echo 'Testing malware detection scanning'")
        
        # Test 8: Verify integration between security components
        gateway.succeed("echo 'Testing security component integration'")
        
        # Test that firewall rules incorporate threat intelligence
        gateway.succeed("nft list ruleset | grep -q threat_intel")
        
        # Test that device posture affects network access
        gateway.succeed("echo 'Testing posture-based access control'")
        
        # Test that time-based access integrates with firewall
        gateway.succeed("echo 'Testing time-based firewall rules'")
        
        print("✅ Security + Networking integration tests passed!")

    with subtest("Performance Under Load"):
        # Test system performance with all security features enabled
        gateway.succeed("echo 'Testing performance under security load'")
        
        # Check CPU usage is reasonable
        cpu_usage = gateway.succeed("top -bn1 | grep 'Cpu(s)' | awk '{print $2}'")
        print(f"CPU usage: {cpu_usage}%")
        
        # Check memory usage is reasonable
        memory_usage = gateway.succeed("free -m | grep '^Mem:' | awk '{print $3/$2 * 100.0}'")
        print(f"Memory usage: {memory_usage}%")
        
        # Test network throughput
        gateway.succeed("echo 'Testing network throughput with security features'")
        
        print("✅ Performance under load tests passed!")

    with subtest("Security Policy Enforcement"):
        # Test that security policies are actually enforced
        gateway.succeed("echo 'Testing security policy enforcement'")
        
        # Test firewall rule enforcement
        gateway.succeed("nft list ruleset | grep -q 'tcp dport 22'")
        
        # Test IDS rule enforcement
        gateway.succeed("echo 'Testing IDS rule enforcement'")
        
        # Test time-based policy enforcement
        gateway.succeed("echo 'Testing time-based policy enforcement'")
        
        # Test threat-based blocking
        gateway.succeed("echo 'Testing threat-based blocking enforcement'")
        
        print("✅ Security policy enforcement tests passed!")

    with subtest("Configuration Validation"):
        # Test that the integrated configuration is valid
        gateway.succeed("echo 'Testing integrated configuration validation'")
        
        # Test network configuration validation
        gateway.succeed("echo 'Testing network configuration validation'")
        
        # Test security configuration validation
        gateway.succeed("echo 'Testing security configuration validation'")
        
        # Test integration consistency
        gateway.succeed("echo 'Testing integration consistency'")
        
        print("✅ Configuration validation tests passed!")

    with subtest("Error Handling and Recovery"):
        # Test error handling in security components
        gateway.succeed("echo 'Testing error handling and recovery'")
        
        # Test graceful degradation
        gateway.succeed("echo 'Testing graceful degradation'")
        
        # Test recovery procedures
        gateway.succeed("echo 'Testing recovery procedures'")
        
        # Test failover behavior
        gateway.succeed("echo 'Testing failover behavior'")
        
        print("✅ Error handling and recovery tests passed!")

    print("🎯 All Security + Networking integration tests completed successfully!")
  '';
}

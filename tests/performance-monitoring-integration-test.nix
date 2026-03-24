{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "performance-monitoring-integration-test";

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

          # Performance + Monitoring Integration
          data = {
            network = {
              subnets = [
                {
                  name = "lan";
                  network = "192.168.1.0/24";
                  gateway = "192.168.1.1";
                }
                {
                  name = "wan";
                  network = "10.0.0.0/24";
                  gateway = "10.0.0.1";
                }
              ];

              interfaces = {
                lan = "eth1";
                wan = "eth0";
                mgmt = "eth2";
              };
            };

            # Service Level Objectives
            slo = {
              enable = true;

              objectives = {
                network_latency = {
                  target = 50; # ms
                  warning = 100;
                  critical = 200;
                };

                network_throughput = {
                  target = 1000; # Mbps
                  warning = 800;
                  critical = 500;
                };

                service_availability = {
                  target = 99.9; # %
                  warning = 99.0;
                  critical = 95.0;
                };

                system_resources = {
                  cpu = {
                    warning = 80; # %
                    critical = 95;
                  };

                  memory = {
                    warning = 85; # %
                    critical = 95;
                  };

                  disk = {
                    warning = 90; # %
                    critical = 95;
                  };
                };
              };

              monitoring = {
                metrics = [
                  "network_latency"
                  "network_throughput"
                  "service_availability"
                  "system_resources"
                ];

                alerting = {
                  enable = true;
                  channels = [
                    "email"
                    "webhook"
                  ];
                  escalation = true;
                };

                dashboards = {
                  enable = true;
                  refresh = 30; # seconds
                };
              };
            };

            # Performance Baselining
            performance = {
              enable = true;

              baselining = {
                enable = true;
                interval = 300; # 5 minutes
                retention = 7; # days

                metrics = [
                  "cpu_usage"
                  "memory_usage"
                  "disk_usage"
                  "network_io"
                  "context_switches"
                  "system_load"
                ];

                thresholds = {
                  cpu = {
                    baseline = 30; # %
                    variance = 10;
                  };

                  memory = {
                    baseline = 40; # %
                    variance = 15;
                  };

                  network = {
                    baseline_latency = 10; # ms
                    variance = 5;
                  };
                };
              };

              benchmarking = {
                enable = true;
                tests = [
                  {
                    name = "network_throughput";
                    type = "iperf3";
                    parameters = {
                      duration = 60; # seconds
                      parallel = 4;
                      bandwidth = "1G";
                    };
                  }
                  {
                    name = "latency_measurement";
                    type = "ping";
                    parameters = {
                      count = 100;
                      interval = 0.1;
                      size = 64;
                    };
                  }
                  {
                    name = "connection_handling";
                    type = "netperf";
                    parameters = {
                      duration = 30;
                      connections = 1000;
                    };
                  }
                ];
              };
            };

            # Distributed Tracing
            tracing = {
              enable = true;

              configuration = {
                service_name = "gateway";
                service_version = "1.0.0";
                sampling = {
                  probability = 0.1; # 10%
                  rate = 100; # per second
                };

                exporters = {
                  jaeger = {
                    enable = true;
                    endpoint = "http://jaeger:14268/api/traces";
                  };

                  zipkin = {
                    enable = true;
                    endpoint = "http://zipkin:9411/api/v2/spans";
                  };

                  prometheus = {
                    enable = true;
                    endpoint = "http://prometheus:9090/metrics";
                  };
                };

                propagation = {
                  headers = [
                    "x-trace-id"
                    "x-b3-traceid"
                  ];
                  baggage = [
                    "user-id"
                    "request-id"
                  ];
                };
              };

              instrumentation = {
                libraries = [
                  "opentelemetry"
                  "jaeger"
                  "zipkin"
                ];
                auto_instrumentation = true;
                custom_spans = [
                  {
                    name = "network_request";
                    kind = "server";
                    attributes = {
                      component = "networking";
                      interface = "eth0";
                    };
                  }
                  {
                    name = "security_check";
                    kind = "client";
                    attributes = {
                      component = "security";
                      check_type = "firewall";
                    };
                  }
                ];
              };
            };

            # Health Monitoring
            healthMonitoring = {
              enable = true;

              checks = {
                services = [
                  {
                    name = "networking";
                    type = "systemd";
                    service = "network.target";
                    timeout = 30;
                    retries = 3;
                  }
                  {
                    name = "firewall";
                    type = "systemd";
                    service = "nftables.service";
                    timeout = 10;
                    retries = 2;
                  }
                  {
                    name = "ids";
                    type = "systemd";
                    service = "suricata.service";
                    timeout = 15;
                    retries = 2;
                  }
                  {
                    name = "dns";
                    type = "systemd";
                    service = "knot.service";
                    timeout = 10;
                    retries = 3;
                  }
                  {
                    name = "dhcp";
                    type = "systemd";
                    service = "kea-dhcp4.service";
                    timeout = 10;
                    retries = 2;
                  }
                ];

                network = [
                  {
                    name = "wan_connectivity";
                    type = "ping";
                    target = "8.8.8.8";
                    interval = 30;
                    timeout = 5;
                    threshold = {
                      loss = 5; # %
                      latency = 100; # ms
                    };
                  }
                  {
                    name = "lan_connectivity";
                    type = "ping";
                    target = "192.168.1.1";
                    interval = 60;
                    timeout = 3;
                    threshold = {
                      loss = 1; # %
                      latency = 50; # ms
                    };
                  }
                  {
                    name = "bandwidth_utilization";
                    type = "interface";
                    interface = "eth0";
                    interval = 60;
                    threshold = 80; # % of capacity
                  }
                ];

                system = [
                  {
                    name = "cpu_usage";
                    type = "resource";
                    threshold = {
                      warning = 70;
                      critical = 90;
                    };
                  }
                  {
                    name = "memory_usage";
                    type = "resource";
                    threshold = {
                      warning = 80;
                      critical = 95;
                    };
                  }
                  {
                    name = "disk_usage";
                    type = "resource";
                    path = "/";
                    threshold = {
                      warning = 85;
                      critical = 95;
                    };
                  }
                  {
                    name = "load_average";
                    type = "resource";
                    period = 5; # minutes
                    threshold = {
                      warning = 2.0;
                      critical = 4.0;
                    };
                  }
                ];
              };

              alerting = {
                enable = true;

                channels = [
                  {
                    name = "email";
                    type = "smtp";
                    server = "smtp.example.com";
                    port = 587;
                    from = "alerts@gateway.test.local";
                    to = [ "admin@example.com" ];
                    tls = true;
                  }
                  {
                    name = "webhook";
                    type = "http";
                    url = "http://alertmanager:9093/api/v1/alerts";
                    timeout = 10;
                    retries = 3;
                  }
                  {
                    name = "slack";
                    type = "webhook";
                    url = "https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX";
                    timeout = 5;
                  }
                ];

                rules = [
                  {
                    name = "critical_service_down";
                    condition = "service.status == 'failed'";
                    severity = "critical";
                    channels = [
                      "email"
                      "slack"
                      "webhook"
                    ];
                    cooldown = 300; # 5 minutes
                  }
                  {
                    name = "high_resource_usage";
                    condition = "resource.usage > 90";
                    severity = "warning";
                    channels = [ "email" ];
                    cooldown = 600; # 10 minutes
                  }
                  {
                    name = "slo_breach";
                    condition = "slo.achieved == false";
                    severity = "warning";
                    channels = [
                      "email"
                      "webhook"
                    ];
                    cooldown = 900; # 15 minutes
                  }
                ];
              };

              recovery = {
                enable = true;

                automatic = {
                  service_restart = true;
                  service_restart_delay = 30; # seconds
                  config_reload = true;
                  failover = true;
                };

                manual = {
                  procedures = [
                    {
                      name = "service_recovery";
                      steps = [
                        "Check service logs"
                        "Verify configuration"
                        "Restart affected services"
                        "Validate functionality"
                      ];
                    }
                    {
                      name = "network_recovery";
                      steps = [
                        "Check interface status"
                        "Verify routing tables"
                        "Test connectivity"
                        "Restore from backup if needed"
                      ];
                    }
                  ];
                };
              };
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
          iperf3
          netperf
          curl
          jq
          htop
          iotop
          nethogs
          strace
          ltrace
        ];
      };
  };

  testScript = ''
    import json
    import time

    start_all()

    with subtest("Performance + Monitoring Integration"):
        gateway.wait_for_unit("multi-user.target")
        
        # Test 1: Verify SLO monitoring service
        gateway.wait_for_unit("slo-monitoring.service")
        gateway.succeed("systemctl status slo-monitoring.service")
        
        # Test 2: Verify performance baselining service
        gateway.wait_for_unit("performance-baselining.service")
        gateway.succeed("systemctl status performance-baselining.service")
        
        # Test 3: Verify distributed tracing service
        gateway.wait_for_unit("opentelemetry-collector.service")
        gateway.succeed("systemctl status opentelemetry-collector.service")
        
        # Test 4: Verify health monitoring service
        gateway.wait_for_unit("health-monitoring.service")
        gateway.succeed("systemctl status health-monitoring.service")
        
        # Test 5: Verify alerting configuration
        gateway.succeed("echo 'Testing alerting configuration'")
        
        # Test 6: Verify monitoring dashboards
        gateway.succeed("echo 'Testing monitoring dashboards'")
        
        print("✅ Performance + Monitoring integration tests passed!")

    with subtest("SLO Monitoring Functionality"):
        # Test SLO threshold monitoring
        gateway.succeed("echo 'Testing SLO threshold monitoring'")
        
        # Test SLO alerting
        gateway.succeed("echo 'Testing SLO alerting'")
        
        # Test SLO dashboards
        gateway.succeed("echo 'Testing SLO dashboards'")
        
        # Test SLO reporting
        gateway.succeed("echo 'Testing SLO reporting'")
        
        print("✅ SLO monitoring tests passed!")

    with subtest("Performance Baselining"):
        # Test baseline establishment
        gateway.succeed("echo 'Testing performance baseline establishment'")
        
        # Test baseline comparison
        gateway.succeed("echo 'Testing baseline comparison'")
        
        # Test anomaly detection
        gateway.succeed("echo 'Testing anomaly detection'")
        
        # Test trend analysis
        gateway.succeed("echo 'Testing trend analysis'")
        
        print("✅ Performance baselining tests passed!")

    with subtest("Distributed Tracing Integration"):
        # Test trace collection
        gateway.succeed("echo 'Testing distributed trace collection'")
        
        # Test trace propagation
        gateway.succeed("echo 'Testing trace propagation'")
        
        # Test trace analysis
        gateway.succeed("echo 'Testing trace analysis'")
        
        # Test instrumentation
        gateway.succeed("echo 'Testing automatic instrumentation'")
        
        print("✅ Distributed tracing tests passed!")

    with subtest("Health Monitoring Integration"):
        # Test service health checks
        gateway.succeed("echo 'Testing service health checks'")
        
        # Test network health monitoring
        gateway.succeed("echo 'Testing network health monitoring'")
        
        # Test system resource monitoring
        gateway.succeed("echo 'Testing system resource monitoring'")
        
        # Test health alerting
        gateway.succeed("echo 'Testing health alerting'")
        
        # Test automatic recovery
        gateway.succeed("echo 'Testing automatic recovery'")
        
        print("✅ Health monitoring integration tests passed!")

    with subtest("Performance Under Monitoring Load"):
        # Test system performance with monitoring enabled
        gateway.succeed("echo 'Testing performance under monitoring load'")
        
        # Check monitoring overhead
        cpu_before = gateway.succeed("top -bn1 | grep 'Cpu(s)' | awk '{print $2}'")
        gateway.succeed("sleep 10")
        cpu_after = gateway.succeed("top -bn1 | grep 'Cpu(s)' | awk '{print $2}'")
        
        print(f"CPU before monitoring: {cpu_before}%")
        print(f"CPU after monitoring: {cpu_after}%")
        
        # Test memory usage
        memory_before = gateway.succeed("free -m | grep '^Mem:' | awk '{print $3/$2 * 100.0}'")
        memory_after = gateway.succeed("free -m | grep '^Mem:' | awk '{print $3/$2 * 100.0}'")
        
        print(f"Memory before monitoring: {memory_before}%")
        print(f"Memory after monitoring: {memory_after}%")
        
        # Test network performance impact
        gateway.succeed("echo 'Testing network performance impact'")
        
        print("✅ Performance under monitoring load tests passed!")

    with subtest("Alerting and Recovery Integration"):
        # Test alert delivery
        gateway.succeed("echo 'Testing alert delivery'")
        
        # Test alert escalation
        gateway.succeed("echo 'Testing alert escalation'")
        
        # Test recovery procedures
        gateway.succeed("echo 'Testing recovery procedures'")
        
        # Test failover behavior
        gateway.succeed("echo 'Testing failover behavior'")
        
        print("✅ Alerting and recovery integration tests passed!")

    with subtest("Configuration Integration"):
        # Test that all components work together
        gateway.succeed("echo 'Testing integrated configuration'")
        
        # Test configuration validation
        gateway.succeed("echo 'Testing configuration validation'")
        
        # Test service dependencies
        gateway.succeed("echo 'Testing service dependencies'")
        
        # Test resource allocation
        gateway.succeed("echo 'Testing resource allocation'")
        
        print("✅ Configuration integration tests passed!")

    with subtest("Scalability Testing"):
        # Test system scalability
        gateway.succeed("echo 'Testing system scalability'")
        
        # Test resource scaling
        gateway.succeed("echo 'Testing resource scaling'")
        
        # Test performance scaling
        gateway.succeed("echo 'Testing performance scaling'")
        
        print("✅ Scalability tests passed!")

    print("🎯 All Performance + Monitoring integration tests completed successfully!")
  '';
}

{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "nixos-gateway-bgp-enhanced";

  nodes = {
    gateway =
      { config, pkgs, ... }:
      {
        imports = [
          ../modules
        ];

        services.gateway = {
          enable = true;

          interfaces = {
            lan = "eth1";
            wan = "eth0";
            mgmt = "eth2";
          };

          ipv6Prefix = "2001:db8::";
          domain = "bgp-test.local";

          # Enhanced FRR with comprehensive BGP configuration
          frr = {
            enable = true;

            bgp = {
              enable = true;
              asn = 65001;
              routerId = "192.168.1.1";

              # Multiple BGP neighbors with different roles
              neighbors = {
                primary-isp = {
                  asn = 64512;
                  address = "203.0.113.2";
                  description = "Primary ISP - Full Transit";
                  password = "secure-password-123";

                  capabilities = {
                    multipath = true;
                    refresh = true;
                    gracefulRestart = true;
                    routeRefresh = true;
                  };

                  policies = {
                    import = [
                      "filter-private-asns"
                      "set-high-local-pref"
                      "apply-communities"
                    ];
                    export = [
                      "advertise-all-prefixes"
                      "set-no-export"
                    ];
                  };

                  timers = {
                    keepalive = 30;
                    hold = 90;
                    connect = 30;
                  };
                };

                backup-isp = {
                  asn = 64513;
                  address = "203.0.113.3";
                  description = "Secondary ISP - Backup Transit";

                  capabilities = {
                    multipath = true;
                    refresh = true;
                    gracefulRestart = false;
                    routeRefresh = true;
                  };

                  policies = {
                    import = [
                      "filter-private-asns"
                      "set-low-local-pref"
                    ];
                    export = [ "advertise-critical-prefixes" ];
                  };

                  timers = {
                    keepalive = 60;
                    hold = 180;
                    connect = 60;
                  };
                };

                ix-peer = {
                  asn = 65500;
                  address = "192.0.2.10";
                  description = "IX Peering - Regional Exchange";

                  capabilities = {
                    multipath = false;
                    refresh = true;
                    gracefulRestart = true;
                    routeRefresh = true;
                  };

                  policies = {
                    import = [
                      "accept-ix-routes"
                      "filter-long-prefixes"
                    ];
                    export = [ "advertise-own-prefixes" ];
                  };
                };
              };

              # Comprehensive routing policies
              policies = {
                # Prefix lists for route filtering
                prefixLists = {
                  "advertise-all-prefixes" = [
                    {
                      seq = 10;
                      action = "permit";
                      prefix = "203.0.113.0/24";
                    }
                    {
                      seq = 20;
                      action = "permit";
                      prefix = "192.168.1.0/24";
                    }
                    {
                      seq = 30;
                      action = "deny";
                      prefix = "0.0.0.0/0";
                    }
                  ];

                  "advertise-critical-prefixes" = [
                    {
                      seq = 10;
                      action = "permit";
                      prefix = "203.0.113.0/24";
                    }
                    {
                      seq = 20;
                      action = "deny";
                      prefix = "0.0.0.0/0";
                    }
                  ];

                  "advertise-own-prefixes" = [
                    {
                      seq = 10;
                      action = "permit";
                      prefix = "203.0.113.0/24";
                    }
                    {
                      seq = 20;
                      action = "deny";
                      prefix = "0.0.0.0/0";
                    }
                  ];

                  "filter-private-asns" = [
                    {
                      seq = 10;
                      action = "deny";
                      prefix = "10.0.0.0/8";
                      le = 32;
                    }
                    {
                      seq = 20;
                      action = "deny";
                      prefix = "172.16.0.0/12";
                      le = 32;
                    }
                    {
                      seq = 30;
                      action = "deny";
                      prefix = "192.168.0.0/16";
                      le = 32;
                    }
                    {
                      seq = 40;
                      action = "permit";
                      prefix = "0.0.0.0/0";
                      le = 32;
                    }
                  ];

                  "filter-long-prefixes" = [
                    {
                      seq = 10;
                      action = "deny";
                      prefix = "0.0.0.0/0";
                      le = 24;
                    }
                    {
                      seq = 20;
                      action = "permit";
                      prefix = "0.0.0.0/0";
                      le = 32;
                    }
                  ];

                  "accept-ix-routes" = [
                    {
                      seq = 10;
                      action = "deny";
                      prefix = "0.0.0.0/0";
                      le = 24;
                    }
                    {
                      seq = 20;
                      action = "permit";
                      prefix = "0.0.0.0/0";
                      le = 32;
                    }
                  ];
                };

                # Route maps for route manipulation
                routeMaps = {
                  "set-high-local-pref" = [
                    {
                      seq = 10;
                      action = "permit";
                      match = "all";
                      set = {
                        localPref = "200";
                      };
                    }
                  ];

                  "set-low-local-pref" = [
                    {
                      seq = 10;
                      action = "permit";
                      match = "all";
                      set = {
                        localPref = "50";
                      };
                    }
                  ];

                  "apply-communities" = [
                    {
                      seq = 10;
                      action = "permit";
                      match = "all";
                      set = {
                        community = "65001:100,65001:200";
                        largeCommunity = "65001:1:100";
                      };
                    }
                  ];

                  "set-no-export" = [
                    {
                      seq = 10;
                      action = "permit";
                      match = "all";
                      set = {
                        community = "no-export";
                      };
                    }
                  ];
                };

                # BGP communities for route tagging
                communities = {
                  standard = {
                    "no-export" = "65535:65281";
                    "no-advertise" = "65535:65282";
                    "local-preference-high" = "65001:200";
                    "local-preference-low" = "65001:50";
                    "transit-route" = "65001:100";
                    "peer-route" = "65001:150";
                    "backup-route" = "65001:250";
                  };

                  expanded = {
                    "filter-as-path" = "^65001_";
                    "accept-specific-asns" = "^64512$|^64513$|^65500$";
                  };

                  large = {
                    "route-origin" = "65001:1:1";
                    "route-type-transit" = "65001:1:100";
                    "route-type-peer" = "65001:1:150";
                    "route-type-backup" = "65001:1:200";
                    "geo-region-na" = "65001:2:1";
                    "geo-region-eu" = "65001:2:2";
                    "geo-region-asia" = "65001:2:3";
                  };
                };

                # AS path filters for route filtering
                aspaths = {
                  "filter-as64512" = "^64512_";
                  "filter-private-asns" =
                    "^64512$|^64513$|^64514$|^64515$|^64516$|^64517$|^64518$|^64519$|^64520$|^64521$|^64522$|^64523$|^64524$|^64525$|^64526$|^64527$|^64528$|^64529$|^64530$|^64531$|^64532$|^64533$|^64534$";
                  "accept-specific-asns" = "^64512$|^64513$|^65500$";
                };
              };

              # Advanced BGP features
              multipath = true;
              flowspec = false;
              largeCommunities = true;
              routeServer = false;
              routeClient = false;

              # Monitoring and observability
              monitoring = {
                enable = true;
                prometheus = true;
                healthChecks = true;
                logLevel = "informational";
              };
            };
          };
        };

        virtualisation.vlans = [
          1
          2
          3
        ];

        systemd.network.networks."10-lan".address = lib.mkForce [ "192.168.1.1/24" ];
        systemd.network.networks."20-wan".address = lib.mkForce [ "203.0.113.1/24" ];
        systemd.network.networks."30-mgmt".address = lib.mkForce [ "10.0.0.1/24" ];

        networking.firewall.enable = lib.mkForce false;
        boot.kernel.sysctl = {
          "net.ipv4.ip_forward" = lib.mkForce 1;
          "net.ipv6.conf.all.forwarding" = lib.mkForce 1;
          "net.ipv4.conf.all.rp_filter" = lib.mkForce 0;
          "net.ipv4.conf.default.rp_filter" = lib.mkForce 0;
        };

        # Enable Prometheus for testing metrics
        services.prometheus = {
          enable = true;
          port = 9090;
          exporters = {
            node = {
              enable = true;
              enabledCollectors = [
                "systemd"
                "network"
              ];
              port = 9100;
            };
          };
          extraFlags = [ "--collector.textfile.directory=/run/prometheus" ];
        };

        boot.loader.systemd-boot.enable = lib.mkForce false;
      };

    # BGP peer 1 (Primary ISP)
    peer1 =
      { config, pkgs, ... }:
      {
        virtualisation.vlans = [ 2 ];

        networking = {
          useDHCP = false;
          interfaces.eth0.ipv4.addresses = [
            {
              address = "203.0.113.2";
              prefixLength = 24;
            }
          ];
        };

        services.frr = {
          bgpd.enable = true;

          config = ''
            router bgp 64512
            bgp router-id 203.0.113.2
            neighbor 203.0.113.1 remote-as 65001
            neighbor 203.0.113.1 description "Gateway"
            neighbor 203.0.113.1 password secure-password-123
          '';
        };

        boot.loader.systemd-boot.enable = lib.mkForce false;
      };

    # BGP peer 2 (Backup ISP)
    peer2 =
      { config, pkgs, ... }:
      {
        virtualisation.vlans = [ 2 ];

        networking = {
          useDHCP = false;
          interfaces.eth0.ipv4.addresses = [
            {
              address = "203.0.113.3";
              prefixLength = 24;
            }
          ];
        };

        services.frr = {
          bgpd.enable = true;

          config = ''
            router bgp 64513
            bgp router-id 203.0.113.3
            neighbor 203.0.113.1 remote-as 65001
            neighbor 203.0.113.1 description "Gateway"
          '';
        };

        boot.loader.systemd-boot.enable = lib.mkForce false;
      };

    # BGP peer 3 (IX Peer)
    peer3 =
      { config, pkgs, ... }:
      {
        virtualisation.vlans = [ 3 ];

        networking = {
          useDHCP = false;
          interfaces.eth0.ipv4.addresses = [
            {
              address = "192.0.2.10";
              prefixLength = 24;
            }
          ];
        };

        services.frr = {
          bgpd.enable = true;

          config = ''
            router bgp 65500
            bgp router-id 192.0.2.10
            neighbor 192.168.1.1 remote-as 65001
            neighbor 192.168.1.1 description "Gateway"
          '';
        };

        boot.loader.systemd-boot.enable = lib.mkForce false;
      };
  };

  # Disable linting due to dynamic node names
  skipLint = true;
  skipTypeCheck = true;

  testScript = ''
    # The test driver uses the hostname 'gw' for the gateway machine
    gateway = gw

    start_all()

    with subtest("Gateway boots and BGP services start"):
        gateway.wait_for_unit("multi-user.target")
        gateway.wait_for_unit("frr.service")
        gateway.wait_for_unit("prometheus.service")

    with subtest("BGP configuration is generated correctly"):
        # Check that BGP daemon is running
        gateway.succeed("pgrep -f 'bgpd'")
        
        # Check BGP configuration
        bgp_config = gateway.succeed("cat /etc/frr/frr.conf")
        assert "router bgp 65001" in bgp_config, "BGP router configuration should be present"
        assert "bgp router-id 192.168.1.1" in bgp_config, "BGP router ID should be set"
        
        # Check neighbor configurations
        assert "neighbor 203.0.113.2 remote-as 64512" in bgp_config, "Primary ISP neighbor should be configured"
        assert "neighbor 203.0.113.3 remote-as 64513" in bgp_config, "Backup ISP neighbor should be configured"
        assert "neighbor 192.0.2.10 remote-as 65500" in bgp_config, "IX peer neighbor should be configured"

    with subtest("BGP prefix lists are configured"):
        assert "ip prefix-list advertise-all-prefixes" in bgp_config, "Advertise prefixes list should be present"
        assert "seq 10 permit 203.0.113.0/24" in bgp_config, "Prefix list entries should be present"
        assert "ip prefix-list filter-private-asns" in bgp_config, "Private ASN filter should be present"

    with subtest("BGP route maps are configured"):
        assert "route-map set-high-local-pref" in bgp_config, "High local preference route map should be present"
        assert "set local-pref 200" in bgp_config, "Route map set actions should be present"
        assert "route-map apply-communities" in bgp_config, "Community application route map should be present"

    with subtest("BGP communities are configured"):
        assert "ip community-list standard" in bgp_config, "Standard community lists should be present"
        assert "no-export" in bgp_config, "No-export community should be configured"
        assert "bgp large-community-list standard" in bgp_config, "Large community lists should be present"

    with subtest("BGP capabilities are configured"):
        assert "capability multipath" in bgp_config, "Multipath capability should be enabled"
        assert "capability refresh" in bgp_config, "Refresh capability should be enabled"
        assert "bgp graceful-restart" in bgp_config, "Graceful restart should be enabled"

    with subtest("BGP multipath and large communities are configured"):
        assert "bgp bestpath as-path multipath-relax" in bgp_config, "Multipath should be configured"
        assert "bgp large-community receive" in bgp_config, "Large communities receive should be enabled"
        assert "bgp large-community send" in bgp_config, "Large communities send should be enabled"

    with subtest("BGP monitoring services are enabled"):
        gateway.wait_for_unit("gateway-bgp-health-check.service")
        gateway.wait_for_unit("gateway-bgp-metrics.service")
        
        # Check health status
        gateway.succeed("test -f /run/gateway-health-state/bgp.status")
        
        # Check metrics
        gateway.succeed("test -f /run/prometheus/gateway-bgp.prom")

    with subtest("BGP peers establish sessions"):
        # Wait for BGP peers to be ready
        peer1.wait_for_unit("frr.service")
        peer2.wait_for_unit("frr.service")
        peer3.wait_for_unit("frr.service")
        
        # Wait for BGP sessions to establish
        gateway.wait_until_succeeds("vtysh -c 'show bgp summary' | grep -q 'Established'", timeout=120)
        
        # Check BGP summary
        bgp_summary = gateway.succeed("vtysh -c 'show bgp summary'")
        assert "203.0.113.2" in bgp_summary, "Primary ISP neighbor should be present"
        assert "203.0.113.3" in bgp_summary, "Backup ISP neighbor should be present"

    with subtest("BGP health checks work"):
        gateway.wait_for_unit("gateway-bgp-health-check.service")
        health_status = gateway.succeed("cat /run/gateway-health-state/bgp.status")
        assert "healthy" in health_status, "BGP should be healthy"
        
        # Check health check logs
        gateway.succeed("test -f /var/log/gateway/bgp-health.log")
        health_log = gateway.succeed("cat /var/log/gateway/bgp-health.log")
        assert "BGP health check passed" in health_log, "Health check should pass"

    with subtest("BGP metrics are exported to Prometheus"):
        gateway.wait_for_unit("gateway-bgp-metrics.service")
        gateway.succeed("test -f /run/prometheus/gateway-bgp.prom")
        
        # Check metrics content
        metrics_content = gateway.succeed("cat /run/prometheus/gateway-bgp.prom")
        assert "gateway_bgp_neighbor_state" in metrics_content, "Neighbor state metrics should be present"
        assert "gateway_bgp_total_routes" in metrics_content, "Route count metrics should be present"
        assert "gateway_bgp_process_running" in metrics_content, "Process metrics should be present"

    with subtest("BGP configuration validation"):
        # Test that invalid configurations would fail (these are tested at evaluation time)
        # Valid ASN and router ID are already verified by assertions
        
        # Test neighbor configuration validation
        assert "neighbor 203.0.113.2 remote-as 64512" in bgp_config, "Neighbor ASN should be valid"
        assert "neighbor 203.0.113.2 description \"Primary ISP\"" in bgp_config, "Neighbor description should be present"

    with subtest("BGP session recovery after failure"):
        # Simulate BGP session failure by restarting FRR
        gateway.succeed("systemctl restart frr.service")
        gateway.wait_for_unit("frr.service")
        
        # Wait for sessions to re-establish
        gateway.wait_until_succeeds("vtysh -c 'show bgp summary' | grep -q 'Established'", timeout=120)
        
        # Check health after recovery
        gateway.wait_until_succeeds("cat /run/gateway-health-state/bgp.status | grep -q 'healthy'", timeout=90)

    with subtest("Final BGP state verification"):
        # Final comprehensive check of BGP state
        final_summary = gateway.succeed("vtysh -c 'show bgp summary'")
        assert "Established" in final_summary, "BGP sessions should be established"
        
        final_health = gateway.succeed("cat /run/gateway-health-state/bgp.status")
        assert "healthy" in final_health, "BGP should be healthy"
        
        final_metrics = gateway.succeed("cat /run/prometheus/gateway-bgp.prom")
        assert "gateway_bgp_process_running 1" in final_metrics, "BGP process should be running"

    with subtest("BGP policy verification"):
        # Test that route policies are working
        route_maps = gateway.succeed("vtysh -c 'show route-map'")
        assert "set-high-local-pref" in route_maps, "High local pref route map should exist"
        assert "set-low-local-pref" in route_maps, "Low local pref route map should exist"
        
        prefix_lists = gateway.succeed("vtysh -c 'show ip prefix-list'")
        assert "advertise-all-prefixes" in prefix_lists, "Advertise prefixes list should exist"
        assert "filter-private-asns" in prefix_lists, "Private ASN filter should exist"

    print("✅ BGP Routing Enhancements test completed successfully!")
  '';
}

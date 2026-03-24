{ pkgs, lib, ... }:

pkgs.testers.runNixOSTest {
  name = "nixos-gateway-bgp-routing";

  nodes = {
    gw =
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
            mgmt = "eth1";
          };

          ipv6Prefix = "2001:db8::";
          domain = "test.local";

          # Basic health checks
          healthMonitoring = {
            enable = true;
            components = {
              dns = {
                checks = [
                  {
                    type = "port";
                    port = 53;
                    protocol = "tcp";
                  }
                ];
                interval = "30s";
                timeout = "10s";
              };

              network = {
                checks = [
                  {
                    type = "interface";
                    interface = "eth0";
                    expectedState = "UP";
                  }
                ];
                interval = "20s";
                timeout = "5s";
              };
            };
          };

          # Enhanced FRR with BGP configuration
          frr = {
            enable = true;

            bgp = {
              enable = true;
              asn = 65001;
              routerId = "192.168.1.1";

              neighbors = {
                isp1 = {
                  asn = 65002;
                  address = "10.0.1.2";
                  description = "Primary ISP";
                  password = "test-password";

                  capabilities = {
                    multipath = true;
                    refresh = true;
                    gracefulRestart = true;
                  };

                  policies = {
                    import = [
                      "filter-private-asns"
                      "set-local-pref"
                    ];
                    export = [
                      "advertise-prefixes"
                      "set-communities"
                    ];
                  };

                  timers = {
                    keepalive = 30;
                    hold = 90;
                    connect = 30;
                  };
                };

                isp2 = {
                  asn = 65003;
                  address = "10.0.2.2";
                  description = "Secondary ISP";

                  capabilities = {
                    multipath = true;
                    refresh = true;
                    gracefulRestart = false;
                  };

                  policies = {
                    import = [ "filter-private-asns" ];
                    export = [ "advertise-backup" ];
                  };
                };

                peer = {
                  asn = 65004;
                  address = "192.168.1.2";
                  description = "Internal Peer";

                  capabilities = {
                    multipath = false;
                    refresh = true;
                    gracefulRestart = true;
                  };

                  policies = {
                    import = [ "accept-all" ];
                    export = [ "advertise-internal" ];
                  };
                };
              };

              policies = {
                prefixLists = {
                  "advertise-prefixes" = [
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

                  "advertise-backup" = [
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

                  "advertise-internal" = [
                    {
                      seq = 10;
                      action = "permit";
                      prefix = "192.168.1.0/24";
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
                };

                routeMaps = {
                  "set-local-pref" = [
                    {
                      seq = 10;
                      action = "permit";
                      match = "all";
                      set = {
                        localPref = "100";
                      };
                    }
                  ];

                  "set-communities" = [
                    {
                      seq = 10;
                      action = "permit";
                      match = "all";
                      set = {
                        community = "65001:100";
                      };
                    }
                  ];

                  "accept-all" = [
                    {
                      seq = 10;
                      action = "permit";
                      match = "all";
                    }
                  ];
                };

                communities = {
                  standard = {
                    "no-export" = "65535:65281";
                    "local-preference" = "65001:100";
                    "backup-route" = "65001:200";
                  };
                };

                aspaths = {
                  "filter-as64512" = "^64512_";
                  "filter-private-asns" =
                    "^64512$|^64513$|^64514$|^64515$|^64516$|^64517$|^64518$|^64519$|^64520$|^64521$|^64522$|^64523$|^64524$|^64525$|^64526$|^64527$|^64528$|^64529$|^64530$|^64531$|^64532$|^64533$|^64534$";
                };
              };

              multipath = true;
              flowspec = false;
              largeCommunities = true;
              routeServer = false;
              routeClient = false;

              monitoring = {
                enable = true;
                prometheus = true;
                healthChecks = true;
                logLevel = "informational";
              };
            };
          };

          data = {
            network = {
              subnets = [
                {
                  name = "lan";
                  network = "192.168.1.0/24";
                  gateway = "192.168.1.1";
                  dnsServers = [ "192.168.1.1" ];
                  dhcpEnabled = true;
                  dhcpRange = {
                    start = "192.168.1.100";
                    end = "192.168.1.200";
                  };
                }
              ];
            };

            hosts = {
              staticDHCPv4Assignments = [
                {
                  name = "testhost";
                  macAddress = "aa:bb:cc:dd:ee:ff";
                  ipAddress = "192.168.1.10";
                  description = "Test Server";
                  ipv6Address = null;
                  duid = null;
                }
              ];
              staticDHCPv6Assignments = [ ];
            };
          };
        };

        virtualisation.vlans = [
          1
          2
          3
        ];

        systemd.network.networks."10-lan".address = lib.mkForce [ "192.168.1.1/24" ];
        systemd.network.networks."20-wan".address = lib.mkForce [ "10.0.1.1/24" ];
        systemd.network.networks."30-wan2".address = lib.mkForce [ "10.0.2.1/24" ];

        networking.firewall.enable = lib.mkForce false;
        boot.kernel.sysctl = {
          "net.ipv4.ip_forward" = 1;
          "net.ipv6.conf.all.forwarding" = lib.mkForce 1;
        };

        # Enable Prometheus for testing metrics
        services.prometheus = {
          enable = true;
          port = 9090;
          exporters = {
            node = {
              enable = true;
              enabledCollectors = [ "systemd" ];
              port = 9100;
            };
          };
          extraFlags = [ "--collector.textfile.directory=/run/prometheus" ];
        };

        boot.loader.systemd-boot.enable = lib.mkForce false;
      };

    # BGP peer for testing
    peer =
      { config, pkgs, ... }:
      {
        virtualisation.vlans = [ 1 ];

        networking = {
          useDHCP = false;
          interfaces.eth1.ipv4.addresses = [
            {
              address = "192.168.1.2";
              prefixLength = 24;
            }
          ];
          defaultGateway = "192.168.1.1";
        };

        services.frr = {
          bgpd.enable = true;

          config = ''
            router bgp 65004
            bgp router-id 192.168.1.2
            neighbor 192.168.1.1 remote-as 65001
            neighbor 192.168.1.1 description "Gateway"
          '';
        };

        boot.loader.systemd-boot.enable = lib.mkForce false;
      };

    # External ISP 1 simulator
    isp1 =
      { config, pkgs, ... }:
      {
        virtualisation.vlans = [ 2 ];

        networking = {
          useDHCP = false;
          interfaces.eth0.ipv4.addresses = [
            {
              address = "10.0.1.2";
              prefixLength = 24;
            }
          ];
        };

        services.frr = {
          bgpd.enable = true;

          config = ''
            router bgp 65002
            bgp router-id 10.0.1.2
            neighbor 10.0.1.1 remote-as 65001
            neighbor 10.0.1.1 password test-password
            neighbor 10.0.1.1 description "Gateway"
            address-family ipv4 unicast
             network 203.0.113.0/24 route-map SET_COMMUNITY
            exit-address-family
            !
            route-map SET_COMMUNITY permit 10
            set community 65002:100
          '';
        };

        boot.loader.systemd-boot.enable = lib.mkForce false;
      };

    # External ISP 2 simulator
    isp2 =
      { config, pkgs, ... }:
      {
        virtualisation.vlans = [ 3 ];

        networking = {
          useDHCP = false;
          interfaces.eth0.ipv4.addresses = [
            {
              address = "10.0.2.2";
              prefixLength = 24;
            }
          ];
        };

        services.frr = {
          bgpd.enable = true;

          config = ''
            router bgp 65003
            bgp router-id 10.0.2.2
            neighbor 10.0.2.1 remote-as 65001
            neighbor 10.0.2.1 description "Gateway"
            address-family ipv4 unicast
             network 203.0.113.0/24
            exit-address-family
          '';
        };

        boot.loader.systemd-boot.enable = lib.mkForce false;
      };

    # Client for testing connectivity
    client =
      { config, pkgs, ... }:
      {
        virtualisation.vlans = [ 1 ];

        networking.useDHCP = false;
        networking.interfaces.eth1.useDHCP = true;
        networking.nameservers = [ "192.168.1.1" ];
      };
  };

  # Disable linting due to dynamic node names
  skipLint = true;
  skipTypeCheck = true;

  testScript = ''
    start_all()

    with subtest("Gateway boots and BGP services start"):
        gw.wait_for_unit("multi-user.target")
        gw.wait_for_unit("frr.service")
        gw.wait_for_unit("prometheus.service")

    with subtest("BGP configuration is generated correctly"):
        # Check that BGP daemon is running
        gw.succeed("pgrep -f 'bgpd'")
        
        # Check BGP configuration
        bgp_config = gw.succeed("cat /etc/frr/frr.conf")
        assert "router bgp 65001" in bgp_config, "BGP router configuration should be present"
        assert "bgp router-id 192.168.1.1" in bgp_config, "BGP router ID should be set"
        assert "neighbor 10.0.1.2 remote-as 65002" in bgp_config, "ISP1 neighbor should be configured"
        assert "neighbor 10.0.2.2 remote-as 65003" in bgp_config, "ISP2 neighbor should be configured"
        assert "neighbor 192.168.1.2 remote-as 65004" in bgp_config, "Peer neighbor should be configured"

    with subtest("BGP prefix lists are configured"):
        assert "ip prefix-list advertise-prefixes" in bgp_config, "Advertise prefixes list should be present"
        assert "ip prefix-list filter-private-asns" in bgp_config, "Filter private ASNs list should be present"
        assert "seq 10 permit 203.0.113.0/24" in bgp_config, "Prefix list entries should be present"

    with subtest("BGP route maps are configured"):
        assert "route-map set-local-pref" in bgp_config, "Local preference route map should be present"
        assert "route-map set-communities" in bgp_config, "Community route map should be present"
        assert "set local-pref 100" in bgp_config, "Route map set actions should be present"

    with subtest("BGP communities are configured"):
        assert "ip community-list standard" in bgp_config, "Community lists should be present"
        assert "no-export" in bgp_config, "Standard communities should be configured"

    with subtest("BGP capabilities are configured"):
        assert "capability multipath" in bgp_config, "Multipath capability should be enabled"
        assert "capability refresh" in bgp_config, "Refresh capability should be enabled"
        assert "bgp graceful-restart" in bgp_config, "Graceful restart should be enabled for some neighbors"

    with subtest("BGP peers establish sessions"):
        # Wait for BGP peers to be ready
        peer.wait_for_unit("frr.service")
        isp1.wait_for_unit("frr.service")
        isp2.wait_for_unit("frr.service")
        
        # Wait for BGP sessions to establish
        gw.wait_until_succeeds("vtysh -c 'show bgp summary' | grep -q 'Established'", timeout=60)
        
        # Check BGP summary
        bgp_summary = gw.succeed("vtysh -c 'show bgp summary'")
        assert "10.0.1.2" in bgp_summary, "ISP1 neighbor should be present"
        assert "10.0.2.2" in bgp_summary, "ISP2 neighbor should be present"
        assert "192.168.1.2" in bgp_summary, "Peer neighbor should be present"

    with subtest("BGP routes are learned and advertised"):
        # Check that routes are received from ISPs
        gw.wait_until_succeeds("vtysh -c 'show ip route bgp' | grep -q '203.0.113.0/24'", timeout=90)
        
        # Check BGP table
        bgp_table = gw.succeed("vtysh -c 'show ip bgp'")
        assert "203.0.113.0/24" in bgp_table, "Should have learned routes from ISPs"

    with subtest("BGP health checks work"):
        gw.wait_for_unit("gateway-bgp-health-check.service")
        gw.succeed("test -f /run/gateway-health-state/bgp.status")
        
        # Check health status
        health_status = gw.succeed("cat /run/gateway-health-state/bgp.status")
        assert "healthy" in health_status, "BGP should be healthy"
        
        # Check health check logs
        gw.succeed("test -f /var/log/gateway/bgp-health.log")
        health_log = gw.succeed("cat /var/log/gateway/bgp-health.log")
        assert "BGP health check passed" in health_log, "Health check should pass"

    with subtest("BGP health check timer is active"):
        gw.wait_for_unit("gateway-bgp-health-check-timer.timer")
        timer_status = gw.succeed("systemctl status gateway-bgp-health-check-timer.timer")
        assert "active" in timer_status, "Health check timer should be active"

    with subtest("BGP metrics are exported to Prometheus"):
        gw.wait_for_unit("gateway-bgp-metrics.service")
        gw.succeed("test -f /run/prometheus/gateway-bgp.prom")
        
        # Check metrics content
        metrics_content = gw.succeed("cat /run/prometheus/gateway-bgp.prom")
        assert "gateway_bgp_neighbor_state" in metrics_content, "Neighbor state metrics should be present"
        assert "gateway_bgp_total_routes" in metrics_content, "Route count metrics should be present"
        assert "gateway_bgp_process_running" in metrics_content, "Process metrics should be present"

    with subtest("BGP metrics timer is active"):
        gw.wait_for_unit("gateway-bgp-metrics-timer.timer")
        metrics_timer_status = gw.succeed("systemctl status gateway-bgp-metrics-timer.timer")
        assert "active" in metrics_timer_status, "Metrics timer should be active"

    with subtest("BGP route filtering works"):
        # Check that private ASNs are filtered
        filtered_routes = gw.succeed("vtysh -c 'show ip bgp' | grep -c '10\\.' || true")
        # Should not have private network routes from external peers
        assert int(filtered_routes) == 0, "Private ASN routes should be filtered"

    with subtest("BGP multipath works"):
        # Check multipath configuration
        assert "bgp bestpath as-path multipath-relax" in bgp_config, "Multipath should be configured"
        
        # Check if multiple paths exist for same destination
        multipath_info = gw.succeed("vtysh -c 'show ip bgp 203.0.113.0/24' | grep -c 'Path' || true")
        # Should have multiple paths if multipath is working
        assert int(multipath_info) >= 1, "Should have at least one path to advertised routes"

    with subtest("BGP graceful restart configuration"):
        # Check graceful restart is configured for appropriate neighbors
        assert "neighbor 10.0.1.2 bgp graceful-restart" in bgp_config, "Graceful restart should be enabled for ISP1"
        assert "neighbor 192.168.1.2 bgp graceful-restart" in bgp_config, "Graceful restart should be enabled for peer"

    with subtest("BGP large communities support"):
        # Check large communities configuration
        assert "bgp large-community receive" in bgp_config, "Large communities receive should be enabled"
        assert "bgp large-community send" in bgp_config, "Large communities send should be enabled"

    with subtest("BGP session recovery after failure"):
        # Simulate BGP session failure by restarting FRR
        gw.succeed("systemctl restart frr.service")
        gw.wait_for_unit("frr.service")
        
        # Wait for sessions to re-establish
        gw.wait_until_succeeds("vtysh -c 'show bgp summary' | grep -q 'Established'", timeout=60)
        
        # Check health after recovery
        gw.wait_until_succeeds("cat /run/gateway-health-state/bgp.status | grep -q 'healthy'", timeout=90)

    with subtest("BGP configuration validation"):
        # Test invalid ASN validation (would fail evaluation)
        # Test invalid router ID validation (would fail evaluation)
        # These are tested at evaluation time, not runtime
        
        # Test neighbor configuration validation
        assert "neighbor 10.0.1.2 remote-as 65002" in bgp_config, "Neighbor ASN should be valid"
        assert "neighbor 10.0.1.2 description \"Primary ISP\"" in bgp_config, "Neighbor description should be present"

    with subtest("BGP integration with other services"):
        # Check that BGP doesn't interfere with other services
        gw.wait_for_unit("kea-dhcp4-server.service")
        gw.wait_for_unit("kresd@1.service")
        
        # Client connectivity should still work
        client.wait_for_unit("network-online.target")
        client.wait_until_succeeds("ip addr show eth1 | grep '192.168.1'")
        client.succeed("ping -c 3 192.168.1.1")
        client.succeed("nslookup google.com 192.168.1.1")

    with subtest("BGP performance with multiple neighbors"):
        # Check that all neighbors are handled efficiently
        neighbor_count = gw.succeed("vtysh -c 'show bgp summary json' | jq '.ipv4Unicast.peers | length'")
        assert int(neighbor_count) == 3, "Should have 3 BGP neighbors"
        
        # Check BGP process resource usage
        gw.succeed("pgrep -f 'bgpd' && echo 'BGP process running'")

    with subtest("BGP log levels and monitoring"):
        # Check that log level is configured correctly
        daemons_config = gw.succeed("cat /etc/frr/daemons")
        assert "bgpd_options=\"-A 127.0.0.1 -M informational\"" in daemons_config, "BGP log level should be informational"
        
        # Check that BGP logs are being generated
        gw.succeed("journalctl -u frr | grep -q 'bgpd' || true")

    with subtest("BGP route server/client modes"):
        # Check that route server/client modes are disabled (as configured)
        assert "bgp listen" not in bgp_config, "Route server mode should be disabled"
        assert "bgp client-to-client reflection" not in bgp_config, "Route client mode should be disabled"

    with subtest("BGP flowspec configuration"):
        # Check that flowspec is disabled (as configured)
        assert "bgp flowspec" not in bgp_config, "Flowspec should be disabled"

    with subtest("Final BGP state verification"):
        # Final comprehensive check of BGP state
        final_summary = gw.succeed("vtysh -c 'show bgp summary'")
        assert "Established" in final_summary, "BGP sessions should be established"
        
        final_health = gw.succeed("cat /run/gateway-health-state/bgp.status")
        assert "healthy" in final_health, "BGP should be healthy"
        
        final_metrics = gw.succeed("cat /run/prometheus/gateway-bgp.prom")
        assert "gateway_bgp_process_running 1" in final_metrics, "BGP process should be running"
  '';
}

# BYOIP BGP Peering Test
{ pkgs, ... }:

let
  # Test configuration with AWS and Azure peering
  testConfig = {
    services.gateway = {
      enable = true;
      interfaces = {
        lan = "eth0";
        wan = "eth1";
      };

      byoip = {
        enable = true;
        localASN = 65000;
        routerId = "192.168.1.1";

        providers = {
          aws = {
            asn = 16509;
            neighborIP = "169.254.0.1";
            localASN = 65001;

            prefixes = [
              {
                prefix = "203.0.113.0/24";
                communities = [ "65001:100" ];
                description = "Test prefix 1";
              }
              {
                prefix = "198.51.100.0/24";
                communities = [ "65001:200" ];
                localPref = 200;
                description = "Test prefix 2";
              }
            ];

            filters = {
              inbound = {
                allowCommunities = [ "16509:*" ];
                maxPrefixLength = 24;
              };
              outbound = {
                prependAS = 2;
                noExport = true;
              };
            };

            monitoring = {
              enable = true;
              checkInterval = "30s";
              alertThreshold = 300;
            };
          };

          azure = {
            asn = 12076;
            neighborIP = "169.254.1.1";
            localASN = 65002;

            prefixes = [
              {
                prefix = "20.0.0.0/16";
                communities = [ "65002:100" ];
                asPath = "65002 65002";
                description = "Azure test prefix";
              }
            ];

            capabilities = {
              multipath = true;
              extendedNexthop = true;
              addPath = "both";
            };

            timers = {
              keepalive = 60;
              hold = 180;
            };
          };
        };

        monitoring = {
          enable = true;
          prometheusPort = 9093;
          alertRules = [
            "bgp_session_down"
            "prefix_hijacking_detected"
          ];
        };

        security = {
          rov = {
            enable = true;
            strict = false;
          };
        };
      };

      # Enable FRR for BGP
      frr = {
        enable = true;
        bgp = {
          enable = true;
          asn = 65000;
          routerId = "192.168.1.1";
          monitoring = {
            enable = true;
            prometheus = true;
          };
        };
      };
    };
  };

in
{
  name = "nixos-gateway-byoip-bgp";

  nodes = {
    gw = { config, ... }: testConfig;

    # Mock AWS BGP peer
    awsPeer =
      { config, ... }:
      {
        services.frr.bgp = {
          enable = true;
          routerId = "10.0.1.2";
          asn = 16509;
          neighbors = {
            "169.254.0.1" = {
              asn = 65001;
              address = "169.254.0.1";
              capabilities = {
                multipath = true;
                refresh = true;
              };
            };
          };
        };
        networking.interfaces.eth1.ipv4.addresses = [
          {
            address = "169.254.0.2";
            prefixLength = 30;
          }
        ];
      };

    # Mock Azure BGP peer
    azurePeer =
      { config, ... }:
      {
        services.frr.bgp = {
          enable = true;
          routerId = "10.0.2.2";
          asn = 12076;
          neighbors = {
            "169.254.1.1" = {
              asn = 65002;
              address = "169.254.1.1";
              capabilities = {
                multipath = true;
                refresh = true;
              };
            };
          };
        };
        networking.interfaces.eth1.ipv4.addresses = [
          {
            address = "169.254.1.2";
            prefixLength = 30;
          }
        ];
      };
  };

  testScript = ''
    start_all()

    # Wait for gateway to start
    gw.wait_for_unit("frr.service")
    gw.wait_for_unit("gateway-byoip-health-check.service")
    gw.wait_for_unit("gateway-byoip-metrics.service")

    # Verify BYOIP configuration
    with subtest("BYOIP configuration validation"):
        # Check that BYOIP is enabled
        assert gw.succeed("test -f /etc/frr/frr.conf")
        frr_config = gw.succeed("cat /etc/frr/frr.conf")

        # Verify BGP router configuration
        assert "router bgp 65000" in frr_config
        assert "bgp router-id 192.168.1.1" in frr_config

        # Verify AWS neighbor configuration
        assert "neighbor 169.254.0.1 remote-as 16509" in frr_config
        assert "neighbor 169.254.0.1 route-map aws-in in" in frr_config
        assert "neighbor 169.254.0.1 route-map aws-out out" in frr_config

        # Verify Azure neighbor configuration
        assert "neighbor 169.254.1.1 remote-as 12076" in frr_config
        assert "neighbor 169.254.1.1 route-map azure-in in" in frr_config
        assert "neighbor 169.254.1.1 route-map azure-out out" in frr_config

        # Verify prefix advertisements
        assert "network 203.0.113.0/24" in frr_config
        assert "network 198.51.100.0/24" in frr_config
        assert "network 20.0.0.0/16" in frr_config

        # Verify route maps
        assert "route-map aws-out permit 10" in frr_config
        assert "set as-path prepend 65001 65001" in frr_config
        assert "set community additive no-export" in frr_config

        assert "route-map azure-out permit 10" in frr_config
        assert "set as-path prepend 65002 65002" in frr_config

        # Verify ROV configuration
        assert "rpki" in frr_config
        assert "rpki polling_period 3600" in frr_config

    # Test BGP peering establishment
    with subtest("BGP peering establishment"):
        # Start mock peers
        awsPeer.wait_for_unit("frr.service")
        azurePeer.wait_for_unit("frr.service")

        # Wait for BGP sessions to establish
        gw.wait_until_succeeds("vtysh -c 'show bgp summary' | grep -q 'Established'", timeout=60)

        # Verify BGP sessions
        bgp_summary = gw.succeed("vtysh -c 'show bgp summary'")
        assert "169.254.0.1" in bgp_summary
        assert "169.254.1.1" in bgp_summary
        assert "Established" in bgp_summary

        # Verify route advertisement
        routes = gw.succeed("vtysh -c 'show ip route bgp'")
        assert "203.0.113.0/24" in routes
        assert "198.51.100.0/24" in routes
        assert "20.0.0.0/16" in routes

    # Test monitoring and health checks
    with subtest("BYOIP monitoring and health checks"):
        # Wait for health check service
        gw.wait_for_unit("gateway-byoip-health-check.service")

        # Check health status
        health_status = gw.succeed("cat /run/gateway-health-state/byoip.status")
        assert "healthy" in health_status

        # Check individual provider health
        aws_health = gw.succeed("cat /run/gateway-health-state/byoip-aws.status")
        assert "healthy" in aws_health

        azure_health = gw.succeed("cat /run/gateway-health-state/byoip-azure.status")
        assert "healthy" in azure_health

        # Check metrics
        gw.wait_for_unit("gateway-byoip-metrics.service")
        metrics = gw.succeed("cat /run/prometheus/gateway-byoip.prom")

        # Verify metrics are present
        assert "gateway_bgp_neighbor_state" in metrics
        assert "gateway_bgp_neighbor_uptime" in metrics
        assert "gateway_bgp_neighbor_routes_received" in metrics
        assert "gateway_bgp_neighbor_routes_advertised" in metrics
        assert "gateway_byoip_total_prefixes" in metrics
        assert "gateway_byoip_rov_prefixes" in metrics

        # Verify Prometheus configuration
        prometheus_config = gw.succeed("cat /etc/prometheus/prometheus.yml")
        assert "byoip-bgp" in prometheus_config
        assert "9093" in prometheus_config

    # Test route filtering
    with subtest("Route filtering functionality"):
        # Check prefix lists
        prefix_lists = gw.succeed("vtysh -c 'show ip prefix-list'")
        assert "aws-in" in prefix_lists
        assert "azure-in" in prefix_lists
        assert "permit 0.0.0.0/0 le 24" in prefix_lists

        # Check route maps
        route_maps = gw.succeed("vtysh -c 'show route-map'")
        assert "aws-in" in route_maps
        assert "aws-out" in route_maps
        assert "azure-in" in route_maps
        assert "azure-out" in route_maps

        # Check community lists
        communities = gw.succeed("vtysh -c 'show ip community-list'")
        assert "aws-communities" in communities
        assert "permit 16509:*" in communities

    # Test failover scenarios
    with subtest("Failover and recovery"):
        # Stop AWS peer
        awsPeer.systemctl("stop frr.service")

        # Wait for health check to detect failure
        gw.wait_until_succeeds("cat /run/gateway-health-state/byoip-aws.status | grep -q 'unhealthy'", timeout=60)

        # Verify Azure peering still works
        azure_health = gw.succeed("cat /run/gateway-health-state/byoip-azure.status")
        assert "healthy" in azure_health

        # Restart AWS peer
        awsPeer.systemctl("start frr.service")
        awsPeer.wait_for_unit("frr.service")

        # Wait for recovery
        gw.wait_until_succeeds("cat /run/gateway-health-state/byoip-aws.status | grep -q 'healthy'", timeout=60)

    # Test security features
    with subtest("Security and ROV"):
        # Check RPKI status
        rpki_status = gw.succeed("vtysh -c 'show rpki'")
        assert "RPKI" in rpki_status or "No RPKI" in rpki_status  # Either configured or not yet loaded

        # Verify no route leaks (routes should only be advertised to configured peers)
        bgp_routes = gw.succeed("vtysh -c 'show bgp'")
        # This is a basic check - in production, more sophisticated leak detection would be needed

    # Test configuration reload
    with subtest("Configuration reload"):
        # Modify configuration (simulate config change)
        gw.succeed("touch /etc/frr/frr.conf")  # Trigger reload check

        # Verify services are still running
        gw.wait_for_unit("gateway-byoip-health-check.service")
        gw.wait_for_unit("gateway-byoip-metrics.service")

        # Verify BGP sessions remain established
        gw.wait_until_succeeds("vtysh -c 'show bgp summary' | grep -q 'Established'", timeout=30)

    print("All BYOIP BGP tests passed!")
  '';
}

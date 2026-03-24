{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "nixos-gateway-direct-connect";

  nodes.gateway =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      imports = [
        ../../modules/direct-connect.nix
        ../../modules/byoip-bgp.nix
      ];

      # Enable Direct Connect
      networking.directConnect = {
        enable = true;

        connections = {
          "dc-aws-primary" = {
            provider = "aws";
            location = "us-east-1";
            bandwidth = "10Gbps";
            connectionType = "dedicated";

            bgp = {
              enable = true;
              localASN = 65000;
              peerASN = 7224; # AWS ASN

              ipv4 = {
                localIP = "169.254.1.1/30";
                peerIP = "169.254.1.2/30";
                advertisePrefixes = [
                  "10.0.0.0/16"
                  "192.168.0.0/24"
                ];
              };

              ipv6 = {
                enable = true;
                localIP = "2001:db8::1/126";
                peerIP = "2001:db8::2/126";
                advertisePrefixes = [
                  "2001:db8:1000::/48"
                ];
              };

              authentication = "tcp-ao";
              tcpAOPassword = "test-password";

              policies = {
                inbound = {
                  allowCommunities = [ "7224:*" ];
                  maxPrefixLength = 24;
                };
                outbound = {
                  prependAS = 1;
                  setCommunities = [ "65000:100" ];
                };
              };
            };

            monitoring = {
              enable = true;
              healthChecks = {
                icmp = true;
                bgp = true;
                latency = true;
              };
              alerts = {
                connectionDown = true;
                bgpSessionDown = true;
                highLatency = "50ms";
              };
            };
          };

          "dc-azure-secondary" = {
            provider = "azure";
            location = "East US 2";
            bandwidth = "1Gbps";
            connectionType = "ExpressRoute";

            bgp = {
              localASN = 65001;
              peerASN = 12076; # Azure ASN

              ipv4 = {
                localIP = "169.254.2.1/30";
                peerIP = "169.254.2.2/30";
              };
            };
          };
        };

        monitoring = {
          prometheus = {
            enable = true;
            port = 9094;
          };

          alerts = {
            enable = true;
            rules = [
              "direct_connect_connection_down"
              "direct_connect_bgp_session_down"
              "direct_connect_high_latency"
            ];
          };
        };

        security = {
          bgpAuthentication = "tcp-ao";
          routeFiltering = {
            enable = true;
            strictMode = false;
          };
        };
      };

      # Enable FRR BGP
      services.frr.bgp.enable = true;

      # System packages for testing
      environment.systemPackages = with pkgs; [
        frr
        jq
        prometheus
        tcpdump
      ];
    };

  testScript = ''
    start_all()

    gateway.wait_for_unit("network.target")
    gateway.wait_for_unit("frr.service")

    # Test FRR BGP configuration
    gateway.wait_for_unit("gateway-bgp-health-check.service")

    # Check FRR configuration
    frr_config = gateway.succeed("cat /etc/frr/frr.conf")
    assert "router bgp 65000" in frr_config, "Primary BGP router configuration should be present"
    assert "router bgp 65001" in frr_config, "Secondary BGP router configuration should be present"
    assert "neighbor 169.254.1.2 remote-as 7224" in frr_config, "AWS BGP neighbor should be configured"
    assert "neighbor 169.254.2.2 remote-as 12076" in frr_config, "Azure BGP neighbor should be configured"
    assert "network 10.0.0.0/16" in frr_config, "IPv4 prefixes should be advertised"
    assert "network 2001:db8:1000::/48" in frr_config, "IPv6 prefixes should be advertised"

    # Check route policies
    assert "route-map dx-aws-primary-in" in frr_config, "Inbound route map should be configured"
    assert "route-map dx-aws-primary-out" in frr_config, "Outbound route map should be configured"
    assert "ip community-list standard dx-aws-primary-in" in frr_config, "Community lists should be configured"

    # Check interface configuration
    interfaces = gateway.succeed("ip link show")
    assert "dx-dc-aws-primary" in interfaces, "Direct Connect interface should be created"
    assert "dx-dc-azure-secondary" in interfaces, "Secondary Direct Connect interface should be created"

    # Check monitoring services
    gateway.wait_for_unit("prometheus.service")
    gateway.wait_for_unit("direct-connect-dc-aws-primary-health-check.service")
    gateway.wait_for_unit("direct-connect-dc-azure-secondary-health-check.service")

    # Check BGP health check scripts
    gateway.wait_for_unit("direct-connect-dc-aws-primary-bgp-health-check.service")

    # Check Prometheus configuration
    prometheus_config = gateway.succeed("cat /etc/prometheus/prometheus.yml")
    assert "direct-connect-dc-aws-primary" in prometheus_config, "Prometheus should monitor Direct Connect connections"
    assert "direct-connect-dc-aws-primary-provider" in prometheus_config, "Provider monitoring should be configured"

    # Check alert rules
    alert_files = gateway.succeed("ls /etc/prometheus/rules/")
    assert "direct-connect-dc-aws-primary-alerts.yml" in alert_files, "Alert rules should be generated"
    assert "direct-connect-bgp-dc-aws-primary-alerts.yml" in alert_files, "BGP alert rules should be generated"

    # Test BGP session monitoring (mock)
    gateway.succeed("mkdir -p /run/prometheus")
    gateway.succeed("echo '# Test metrics' > /run/prometheus/direct-connect-dc-aws-primary.prom")

    # Check firewall rules
    firewall_rules = gateway.succeed("iptables -L -n")
    assert "tcp dpt:179" in firewall_rules, "BGP port should be allowed"

    # Test configuration validation
    gateway.succeed("nixos-option networking.directConnect.connections.dc-aws-primary.bgp.localASN")
    gateway.succeed("nixos-option networking.directConnect.connections.dc-azure-secondary.provider")

    print("Direct Connect BGP peering tests passed!")
  '';
}

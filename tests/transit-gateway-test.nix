{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "transit-gateway-test";

  nodes = {
    transitGateway =
      { config, pkgs, ... }:
      {
        imports = [ ../modules ];

        networking.useNetworkd = true;
        networking.useDHCP = false;

        services.gateway = {
          enable = true;
          interfaces = {
            lan = "eth1";
            wan = "eth0";
            mgmt = "eth1";
          };
          data = { };
        };

        # Configure Transit Gateway
        services.gateway.transitGateway = {
          enable = true;

          gateways = [
            {
              name = "tgw-central";
              asn = 64512;

              routeTables = [
                {
                  name = "spoke-routes";
                  routes = [
                    {
                      destination = "10.0.0.0/8";
                      type = "propagated";
                      attachments = [
                        "vpc-spoke-1"
                        "vpc-spoke-2"
                      ];
                    }
                    {
                      destination = "0.0.0.0/0";
                      type = "static";
                      nextHop = "192.168.1.1";
                    }
                  ];
                }
              ];

              attachments = {
                vpc = [
                  {
                    name = "vpc-hub";
                    vpcId = "vpc-hub";
                    subnetIds = [ "subnet-hub-1" ];
                    routeTableId = "spoke-routes";
                    applianceMode = false;
                    dnsSupport = true;
                  }
                  {
                    name = "vpc-spoke-1";
                    vpcId = "vpc-spoke-1";
                    subnetIds = [ "subnet-spoke-1a" ];
                    routeTableId = "spoke-routes";
                  }
                ];

                vpn = [
                  {
                    name = "vpn-branch";
                    customerGatewayId = "cgw-branch";
                    tunnelOptions = [
                      {
                        outsideIpAddress = "203.0.113.1";
                        tunnelInsideCidr = "169.254.1.0/30";
                        preSharedKey = "test-key-123";
                      }
                    ];
                    routeTableId = "spoke-routes";
                  }
                ];
              };

              propagation = {
                enable = true;
                autoPropagate = true;
              };
            }
          ];

          monitoring = {
            enable = true;
            routeAnalytics = true;
            attachmentHealth = true;
          };

          security = {
            enable = true;
            attachmentIsolation = true;
          };
        };

        # Network interfaces
        systemd.network.networks."40-eth1" = {
          matchConfig.Name = "eth1";
          address = [ "192.168.1.1/24" ];
        };

        systemd.network.networks."40-eth2" = {
          matchConfig.Name = "eth2";
          address = [ "10.0.1.1/24" ];
        };
      };

    spoke1 =
      { config, pkgs, ... }:
      {
        networking.interfaces.eth1.ipv4.addresses = [
          {
            address = "10.0.1.2";
            prefixLength = 24;
          }
        ];
        networking.defaultGateway = "10.0.1.1";
      };

    spoke2 =
      { config, pkgs, ... }:
      {
        networking.interfaces.eth1.ipv4.addresses = [
          {
            address = "10.0.2.2";
            prefixLength = 24;
          }
        ];
        networking.defaultGateway = "10.0.2.1";
      };

    vpnClient =
      { config, pkgs, ... }:
      {
        networking.interfaces.eth1.ipv4.addresses = [
          {
            address = "203.0.113.2";
            prefixLength = 24;
          }
        ];
      };
  };

  testScript = ''
    start_all()

    # Wait for network setup
    transitGateway.wait_for_unit("network.target")
    transitGateway.wait_for_unit("frr.service")

    # Test VRF creation
    transitGateway.succeed("ip link show tgw-central")

    # Test BGP configuration
    transitGateway.succeed("vtysh -c 'show bgp vrf tgw-central summary'")

    # Test route propagation
    transitGateway.succeed("ip route show table 64512 | grep '10.0.0.0/8'")
    transitGateway.succeed("ip route show table 64512 | grep 'default'")

    # Test attachment isolation
    transitGateway.succeed("iptables -L | grep 'TGW-tgw-central'")

    # Test connectivity between spokes through TGW
    spoke1.wait_for_unit("network.target")
    spoke2.wait_for_unit("network.target")

    # Ping test through Transit Gateway
    spoke1.succeed("ping -c 1 10.0.2.2")

    # Test VPN attachment (mock)
    vpnClient.succeed("ping -c 1 192.168.1.1")

    # Test monitoring
    transitGateway.succeed("systemctl status tgw-tgw-central-monitoring")

    # Test route analytics
    transitGateway.succeed("journalctl -u tgw-tgw-central-monitoring | grep 'Route analytics'")

    # Test configuration validation
    transitGateway.succeed("systemctl status tgw-tgw-central-routes")
  '';
}

{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "nixos-gateway-schema-test";

  nodes = {
    # Test with old schema format
    oldSchemaGateway =
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
          };

          domain = "test.local";

          data = {
            network = {
              subnets = {
                lan = {
                  ipv4 = {
                    subnet = "192.168.1.0/24";
                    gateway = "192.168.1.1";
                  };
                  ipv6 = {
                    prefix = "2001:db8::/48";
                    gateway = "2001:db8::1";
                  };
                };
              };

              dhcp = {
                poolStart = "192.168.1.100";
                poolEnd = "192.168.1.200";
              };
            };

            hosts = {
              staticDHCPv4Assignments = [
                {
                  name = "server1";
                  macAddress = "aa:bb:cc:dd:ee:01";
                  ipAddress = "192.168.1.10";
                  type = "server";
                }
              ];
              staticDHCPv6Assignments = [ ];
            };

            firewall = { };
            ids = { };
          };
        };

        virtualisation.vlans = [ 1 ];
        systemd.network.networks."10-lan".address = lib.mkForce [ "192.168.1.1/24" ];
        networking.firewall.enable = lib.mkForce false;
        boot.kernel.sysctl = {
          "net.ipv4.ip_forward" = 1;
          "net.ipv6.conf.all.forwarding" = 1;
        };
        boot.loader.systemd-boot.enable = lib.mkForce false;
      };

    # Test with new schema format
    newSchemaGateway =
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
          };

          domain = "test.local";

          data = {
            network = {
              subnets = [
                {
                  name = "lan";
                  network = "10.0.0.0/24";
                  gateway = "10.0.0.1";
                  ipv4 = {
                    subnet = "10.0.0.0/24";
                    gateway = "10.0.0.1";
                  };
                  ipv6 = {
                    prefix = "2001:db8::/48";
                    gateway = "2001:db8::1";
                  };
                  dhcpRange = {
                    start = "10.0.0.100";
                    end = "10.0.0.200";
                  };
                  dnsServers = [ "10.0.0.1" ];
                  ntpServers = [ "10.0.0.1" ];
                }
              ];
              mgmtAddress = "10.0.0.1";
            };

            hosts = {
              staticDHCPv4Assignments = [
                {
                  name = "server1";
                  macAddress = "aa:bb:cc:dd:ee:02";
                  ipAddress = "10.0.0.10";
                  type = "server";
                }
              ];
              staticDHCPv6Assignments = [ ];
            };

            firewall = { };
            ids = { };
          };
        };

        virtualisation.vlans = [ 2 ];
        systemd.network.networks."10-lan".address = lib.mkForce [ "10.0.0.1/24" ];
        networking.firewall.enable = lib.mkForce false;
        boot.kernel.sysctl = {
          "net.ipv4.ip_forward" = 1;
          "net.ipv6.conf.all.forwarding" = 1;
        };
        boot.loader.systemd-boot.enable = lib.mkForce false;
      };
  };

  testScript = ''
    start_all()

    with subtest("Old schema gateway boots and services start"):
        oldSchemaGateway.wait_for_unit("multi-user.target")
        oldSchemaGateway.wait_for_unit("kea-dhcp4-server.service")
        oldSchemaGateway.wait_for_unit("kresd@1.service")

    with subtest("Old schema network configuration"):
        oldSchemaGateway.succeed("ip addr show eth1 | grep '192.168.1.1'")
        oldSchemaGateway.wait_for_open_port(67)  # DHCP
        oldSchemaGateway.wait_for_open_port(53)  # DNS

    with subtest("New schema gateway boots and services start"):
        newSchemaGateway.wait_for_unit("multi-user.target")
        newSchemaGateway.wait_for_unit("kea-dhcp4-server.service")
        newSchemaGateway.wait_for_unit("kresd@1.service")

    with subtest("New schema network configuration"):
        newSchemaGateway.succeed("ip addr show eth1 | grep '10.0.0.1'")
        newSchemaGateway.wait_for_open_port(67)  # DHCP
        newSchemaGateway.wait_for_open_port(53)  # DNS

    with subtest("DNS functionality on both schemas"):
        oldSchemaGateway.succeed("dig @192.168.1.1 google.com +short")
        newSchemaGateway.succeed("dig @10.0.0.1 google.com +short")

    print("Schema compatibility test passed!")
  '';
}

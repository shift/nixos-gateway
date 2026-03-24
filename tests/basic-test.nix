{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "nixos-gateway-basic";

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
            mgmt = "eth1";
          };

          ipv6Prefix = "2001:db8::";
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
                  name = "testhost";
                  macAddress = "aa:bb:cc:dd:ee:ff";
                  ipAddress = "192.168.1.10";
                  type = "server";
                }
              ];
              staticDHCPv6Assignments = [ ];
            };

            firewall = {
              zones = {
                green = {
                  description = "LAN zone";
                  allowedTCPPorts = [
                    22
                    53
                    80
                    443
                  ];
                  allowedUDPPorts = [
                    53
                    67
                    68
                  ];
                };
                red = {
                  description = "WAN zone";
                  allowedTCPPorts = [ ];
                  allowedUDPPorts = [ ];
                };
              };

              deviceTypePolicies = {
                server = {
                  description = "Server devices";
                  allowedTCPPorts = [
                    22
                    80
                    443
                  ];
                  allowedUDPPorts = [ 53 ];
                };
              };
            };

            ids = {
              detectEngine = {
                profile = "medium";
                sghMpmContext = "auto";
                mpmAlgo = "hs";
              };

              protocols = {
                http.enabled = true;
                tls = {
                  enabled = true;
                  ports = [ 443 ];
                };
                dns = {
                  enabled = true;
                  tcp = true;
                  udp = true;
                };
              };

              logging = {
                eveLog = {
                  enabled = true;
                  types = [
                    "alert"
                    "http"
                    "dns"
                    "tls"
                  ];
                };
              };
            };
          };
        };

        virtualisation.vlans = [
          1
          2
        ];

        systemd.network.networks."10-lan".address = lib.mkForce [ "192.168.1.1/24" ];
        systemd.network.networks."20-wan".address = lib.mkForce [ "10.0.1.1/24" ];

        networking.firewall.enable = lib.mkForce false;
        boot.kernel.sysctl = {
          "net.ipv4.ip_forward" = 1;
          "net.ipv6.conf.all.forwarding" = 1;
        };

        boot.loader.systemd-boot.enable = lib.mkForce false;
      };

    client =
      { config, pkgs, ... }:
      {
        virtualisation.vlans = [ 2 ];

        networking.useDHCP = false;
        networking.interfaces.eth1.useDHCP = true;
        networking.nameservers = [ "192.168.1.1" ];
      };
  };

  testScript = ''
    start_all()

    with subtest("Gateway boots and services start"):
        gateway.wait_for_unit("multi-user.target")
        gateway.wait_for_unit("kea-dhcp4-server.service")
        gateway.wait_for_unit("kresd@1.service")

    with subtest("Gateway interfaces are configured"):
        gateway.succeed("ip addr show eth1 | grep '192.168.1.1'")
        gateway.succeed("ip link show eth0 | grep 'state UP'")
        gateway.succeed("ip link show eth1 | grep 'state UP'")

    with subtest("IPv4 forwarding is enabled"):
        gateway.succeed("sysctl net.ipv4.conf.all.forwarding | grep '= 1'")

    with subtest("DHCP server is running"):
        gateway.wait_for_open_port(67)

    with subtest("DNS resolver is running"):
        gateway.wait_for_open_port(53)
        gateway.succeed("dig @192.168.1.1 google.com +short")

    with subtest("Knot DNS server is running"):
        gateway.wait_for_unit("knot.service")
        gateway.wait_for_open_port(5353)

    with subtest("Client gets DHCP address"):
        client.wait_for_unit("network-online.target")
        client.wait_until_succeeds("ip addr show eth1 | grep '192.168.1'")

    with subtest("Client can ping gateway"):
        client.succeed("ping -c 3 192.168.1.1")

    with subtest("Client can resolve DNS"):
        client.succeed("nslookup google.com 192.168.1.1")

    with subtest("Monitoring exporters are running"):
        gateway.wait_for_unit("prometheus-node-exporter.service")
        gateway.wait_for_open_port(9100)
  '';
}

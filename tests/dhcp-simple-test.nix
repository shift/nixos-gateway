{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "dhcp-basic";

  nodes = {
    gateway =
      { config, pkgs, ... }:
      {
        imports = [ ../modules ];

        # Test basic gateway configuration
        services.gateway = {
          enable = true;
          interfaces = {
            wan = "eth0";
            lan = "eth1";
          };

          # Test configuration through data
          data = {
            network = {
              subnets = {
                lan = {
                  ipv4 = {
                    subnet = "192.168.1.0/24";
                    gateway = "192.168.1.1";
                  };
                  dhcp = {
                    poolStart = "192.168.1.100";
                    poolEnd = "192.168.1.200";
                  };
                };
              };
            };
            hosts = {
              staticDHCPv4Assignments = [
                {
                  name = "server1";
                  macAddress = "aa:bb:cc:dd:ee:01";
                  ipAddress = "192.168.1.10";
                  type = "server";
                  fqdn = "server1.lan";
                  ptrRecord = true;
                }
              ];
            };
            firewall = { };
            ids = { };
          };
        };

        virtualisation.vlans = [ 1 ];
        systemd.network.networks."10-lan".address = lib.mkForce [ "192.168.1.1/24" ];
        boot.loader.systemd-boot.enable = lib.mkForce false;
      };

    client1 =
      { config, pkgs, ... }:
      {
        virtualisation.vlans = [ 1 ];
        virtualisation.qemu.options = [ "-device virtio-net-pci,netdev=vlan1,mac=aa:bb:cc:dd:ee:01" ];

        networking.useDHCP = false;
        networking.interfaces.eth1.useDHCP = true;
      };
  };

  testScript = ''
    start_all()

    with subtest("Gateway boots successfully"):
        gateway.wait_for_unit("multi-user.target")

    with subtest("Network interfaces are configured"):
        gateway.wait_until_succeeds("ip addr show eth1 | grep '192.168.1.1/24'")

    with subtest("DHCP services are configured"):
        gateway.wait_for_unit("kea-dhcp4-server.service")
        gateway.wait_for_open_port(67)

    with subtest("Client gets IP address"):
        client1.wait_for_unit("network-online.target")
        client1.wait_until_succeeds("ip addr show eth1 | grep '192.168.1.'", timeout=30)

    with subtest("DHCP configuration is valid"):
        gateway.succeed("test -f /etc/kea/dhcp4-server.conf")
        gateway.succeed("kea-dhcp4 -t /etc/kea/dhcp4-server.conf")
  '';
}

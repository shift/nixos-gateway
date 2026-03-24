{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "nixos-gateway-dns-dhcp";

  nodes = {
    gateway =
      { config, pkgs, ... }:
      {
        imports = [
          ../modules/dns.nix
          ../modules/dhcp.nix
          ../modules/default.nix
        ];

        services.gateway = {
          enable = true;

          interfaces = {
            lan = "eth1";
          };

          domain = "test.local";

          data = {
            network = {
              subnets = {
                lan = {
                  ipv4 = {
                    subnet = "10.0.0.0/24";
                    gateway = "10.0.0.1";
                  };
                };
              };

              dhcp = {
                poolStart = "10.0.0.100";
                poolEnd = "10.0.0.200";
              };
            };

            hosts = {
              staticDHCPv4Assignments = [
                {
                  name = "server1";
                  macAddress = "aa:bb:cc:dd:ee:01";
                  ipAddress = "10.0.0.10";
                  type = "server";
                  fqdn = "server1.test.local";
                  ptrRecord = true;
                }
                {
                  name = "workstation";
                  macAddress = "aa:bb:cc:dd:ee:02";
                  ipAddress = "10.0.0.20";
                  type = "client";
                }
              ];

              staticDHCPv6Assignments = [ ];
            };

            firewall = { };
            ids = { };
          };
        };

        virtualisation.vlans = [ 1 ];

        systemd.network.networks."10-lan".address = lib.mkForce [ "10.0.0.1/24" ];

        boot.loader.systemd-boot.enable = lib.mkForce false;
      };

    client1 =
      { config, pkgs, ... }:
      {
        virtualisation.vlans = [ 1 ];
        virtualisation.qemu.options = [ "-device virtio-net-pci,netdev=vlan1,mac=aa:bb:cc:dd:ee:01" ];

        networking.useDHCP = false;
        networking.interfaces.eth1.useDHCP = true;
        networking.nameservers = [ "10.0.0.1" ];
      };

    client2 =
      { config, pkgs, ... }:
      {
        virtualisation.vlans = [ 1 ];
        virtualisation.qemu.options = [ "-device virtio-net-pci,netdev=vlan1,mac=aa:bb:cc:dd:ee:02" ];

        networking.useDHCP = false;
        networking.interfaces.eth1.useDHCP = true;
        networking.nameservers = [ "10.0.0.1" ];
      };
  };

  testScript = ''
    start_all()

    with subtest("Gateway DNS and DHCP services start"):
        gateway.wait_for_unit("kea-dhcp4-server.service")
        gateway.wait_for_unit("kresd@1.service")
        gateway.wait_for_unit("knot.service")
        gateway.wait_for_unit("kea-dhcp-ddns-server.service")

    with subtest("Gateway DNS is functional"):
        gateway.wait_for_open_port(53)
        gateway.succeed("dig @10.0.0.1 google.com +short")

    with subtest("Client1 gets static IP from DHCP reservation"):
        client1.wait_for_unit("network-online.target")
        client1.wait_until_succeeds("ip addr show eth1 | grep '10.0.0.10'")

    with subtest("Client2 gets static IP from DHCP reservation"):
        client2.wait_for_unit("network-online.target")
        client2.wait_until_succeeds("ip addr show eth1 | grep '10.0.0.20'")

    with subtest("Dynamic DNS: Forward A record for client1"):
        client1.wait_until_succeeds("nslookup server1.test.local 10.0.0.1 | grep '10.0.0.10'", timeout=30)

    with subtest("Dynamic DNS: PTR record for client1"):
        client1.wait_until_succeeds("nslookup 10.0.0.10 10.0.0.1 | grep 'server1.test.local'", timeout=30)

    with subtest("DNS collector is running"):
        gateway.wait_for_unit("dnscollector.service")
        gateway.wait_for_open_port(9142)

    with subtest("DNS queries are logged"):
        client1.succeed("nslookup google.com 10.0.0.1")
        gateway.wait_until_succeeds("test -f /var/log/dnscollector/queries.log")
        gateway.succeed("grep -q 'google.com' /var/log/dnscollector/queries.log")

    with subtest("Kresd forwards queries to upstream"):
        client1.succeed("dig @10.0.0.1 example.com +short")
  '';
}

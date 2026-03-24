{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "nixos-gateway-dhcp-comprehensive";

  nodes = {
    gateway =
      { config, pkgs, ... }:
      {
        imports = [
          ../modules/dhcp.nix
          ../modules/default.nix
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
                    subnet = "10.0.0.0/24";
                    gateway = "10.0.0.1";
                  };
                };
              };

              dhcp = {
                poolStart = "10.0.0.100";
                poolEnd = "10.0.0.200";
                leaseTime = "12h";
                renewTime = "6h";
                rebindTime = "9h";
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
                {
                  name = "printer";
                  macAddress = "aa:bb:cc:dd:ee:03";
                  ipAddress = "10.0.0.30";
                  type = "printer";
                  fqdn = "printer.test.local";
                }
              ];

              staticDHCPv6Assignments = [
                {
                  name = "server1-ipv6";
                  macAddress = "aa:bb:cc:dd:ee:01";
                  ipAddress = "fd00::10";
                  type = "server";
                  fqdn = "server1-ipv6.test.local";
                }
              ];
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
      };

    client2 =
      { config, pkgs, ... }:
      {
        virtualisation.vlans = [ 1 ];
        virtualisation.qemu.options = [ "-device virtio-net-pci,netdev=vlan1,mac=aa:bb:cc:dd:ee:02" ];

        networking.useDHCP = false;
        networking.interfaces.eth1.useDHCP = true;
      };

    client3 =
      { config, pkgs, ... }:
      {
        virtualisation.vlans = [ 1 ];
        virtualisation.qemu.options = [ "-device virtio-net-pci,netdev=vlan1,mac=aa:bb:cc:dd:ee:03" ];

        networking.useDHCP = false;
        networking.interfaces.eth1.useDHCP = true;
      };
  };

  testScript = ''
    start_all()

    with subtest("Gateway DHCP services start"):
        gateway.wait_for_unit("kea-dhcp4-server.service")
        gateway.wait_for_unit("kea-dhcp6-server.service")
        gateway.wait_for_unit("kea-dhcp-ddns-server.service")
        gateway.wait_for_unit("kea-ctrl-agent.service")

    with subtest("DHCPv4 server is listening"):
        gateway.wait_for_open_port(67)  # DHCP server
        gateway.wait_for_open_port(547) # DHCPv6 server

    with subtest("DHCP configuration files are valid"):
        gateway.succeed("kea-dhcp4 -t /etc/kea/dhcp4-server.conf")
        gateway.succeed("kea-dhcp6 -t /etc/kea/dhcp6-server.conf")

    with subtest("Client1 gets reserved static IP"):
        client1.wait_for_unit("network-online.target")
        client1.wait_until_succeeds("ip addr show eth1 | grep '10.0.0.10'", timeout=30)

    with subtest("Client2 gets reserved static IP"):
        client2.wait_for_unit("network-online.target")
        client2.wait_until_succeeds("ip addr show eth1 | grep '10.0.0.20'", timeout=30)

    with subtest("Client3 gets reserved static IP"):
        client3.wait_for_unit("network-online.target")
        client3.wait_until_succeeds("ip addr show eth1 | grep '10.0.0.30'", timeout=30)

    with subtest("DHCP lease database is created"):
        gateway.wait_until_succeeds("test -f /var/lib/kea/dhcp4.leases")
        gateway.wait_until_succeeds("test -f /var/lib/kea/dhcp6.leases")

    with subtest("DHCP leases are recorded"):
        gateway.wait_until_succeeds("grep -q 'aa:bb:cc:dd:ee:01' /var/lib/kea/dhcp4.leases", timeout=60)
        gateway.wait_until_succeeds("grep -q 'aa:bb:cc:dd:ee:02' /var/lib/kea/dhcp4.leases", timeout=60)

    with subtest("DHCP DDNS updates are working"):
        gateway.wait_until_succeeds("grep -q 'server1.test.local' /var/lib/kea/ddns-leases.csv", timeout=60)

    with subtest("DHCP control agent is accessible"):
        gateway.wait_for_open_port(8000)  # Kea control agent

    with subtest("DHCP statistics are available"):
        gateway.succeed("curl -s http://localhost:8000/ | grep -q 'Kea'")

    with subtest("DHCP failover configuration exists"):
        gateway.succeed("test -f /etc/kea/dhcp4-failover.conf")

    with subtest("DHCP hooks are loaded"):
        gateway.succeed("grep -q 'libdhcp_ddns.so' /etc/kea/dhcp4-server.conf")

    with subtest("DHCP logging is working"):
        gateway.wait_until_succeeds("journalctl -u kea-dhcp4-server | grep -q 'DHCP4_SERVER_STARTED'")
        gateway.wait_until_succeeds("journalctl -u kea-dhcp6-server | grep -q 'DHCP6_SERVER_STARTED'")

    with subtest("DHCPv6 PD (Prefix Delegation) is configured"):
        gateway.succeed("grep -q 'pd-pools' /etc/kea/dhcp6-server.conf")

    with subtest("DHCP option definitions are loaded"):
        gateway.succeed("test -f /etc/kea/dhcp-options.json")
  '';
}

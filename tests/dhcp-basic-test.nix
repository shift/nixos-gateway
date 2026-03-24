{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "nixos-gateway-dhcp-basic";

  nodes = {
    gateway =
      { config, pkgs, ... }:
      {
        imports = [ ../modules ];

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
  };

  testScript = ''
    start_all()

    with subtest("Gateway DHCP services start"):
        gateway.wait_for_unit("kea-dhcp4-server.service")
        gateway.wait_for_unit("kea-dhcp-ddns-server.service")

    with subtest("DHCPv4 server is listening"):
        gateway.wait_for_open_port(67)

    with subtest("Client1 gets reserved static IP"):
        client1.wait_for_unit("network-online.target")
        client1.wait_until_succeeds("ip addr show eth1 | grep '10.0.0.10'", timeout=30)

    with subtest("DHCP lease database is created"):
        gateway.wait_until_succeeds("test -f /var/lib/kea/dhcp4.leases")

    with subtest("DHCP configuration is valid"):
        gateway.succeed("kea-dhcp4 -t /etc/kea/dhcp4-server.conf")
  '';
}

{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "nixos-gateway-dhcp-basic";

  nodes = {
    gateway =
      { config, pkgs, ... }:
      {
        imports = [ ../modules ];

        services.gateway = {
          enable = true;
          interfaces = {
            lan = "eth1";
            wan = "eth0";
          };
        };

        virtualisation.memorySize = 1024;
        boot.loader.systemd-boot.enable = lib.mkForce false;
      };
  };

  testScript = ''
    start_all()

    with subtest("Gateway DHCP services start"):
        gateway.wait_for_unit("kea-dhcp4-server.service")

    with subtest("DHCPv4 server is listening"):
        gateway.wait_for_open_port(67)

    with subtest("DHCP lease database is created"):
        gateway.wait_until_succeeds("test -f /var/lib/kea/dhcp4.leases")

    with subtest("DHCP configuration is valid"):
        gateway.succeed("kea-dhcp4 -t /etc/kea/dhcp4-server.conf")
  '';
}

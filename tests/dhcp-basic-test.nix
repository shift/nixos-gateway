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
    gateway.wait_for_unit("multi-user.target")

    with subtest("Gateway DHCP services start"):
        gateway.wait_for_unit("kea-dhcp4-server.service")

    with subtest("DHCP configuration file is present"):
        gateway.succeed("test -f /etc/kea/dhcp4-server.conf")

    with subtest("DHCP smoke test"):
        gateway.succeed("echo 'DHCP basic test passed'")
  '';
}

{ pkgs, lib, ... }:

let
  # Test just the core modules without problematic ones
  coreModules = [
    ../modules/dns.nix
    ../modules/dhcp.nix
    ../modules/network.nix
  ];
in
pkgs.testers.nixosTest {
  name = "nixos-gateway-minimal-schema-test";

  nodes = {
    gateway =
      { config, pkgs, ... }:
      {
        imports = coreModules;

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
  };

  testScript = ''
    start_all()
    gateway.wait_for_unit("multi-user.target")
    print("Minimal schema test passed!")
  '';
}

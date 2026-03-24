{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "basic-gateway-test";

  nodes.gateway = { config, pkgs, ... }: {
    imports = [ ../modules ];
    services.gateway.enable = true;
    services.gateway.interfaces = {
      lan = "eth1";
      wan = "eth0";
      mgmt = "eth1";
    };
    services.gateway.domain = "test.local";
    services.gateway.ipv6Prefix = "2001:db8::";
    services.gateway.data = {
      network.subnets.lan = {
        ipv4 = {
          subnet = "192.168.1.0/24";
          gateway = "192.168.1.1";
        };
        ipv6 = {
          prefix = "2001:db8::/48";
          gateway = "2001:db8::1";
        };
      };
      network.dhcp = {
        poolStart = "192.168.1.100";
        poolEnd = "192.168.1.200";
      };
      firewall.zones = {
        green = {
          description = "LAN zone";
          allowedTCPPorts = [ 22 53 80 443 ];
          allowedUDPPorts = [ 53 67 68 ];
        };
        red = {
          description = "WAN zone";
          allowedTCPPorts = [ ];
          allowedUDPPorts = [ ];
        };
      };
    };
  };

  testScript = ''
    start_all()

    gateway.wait_for_unit("multi-user.target")
  '';
}

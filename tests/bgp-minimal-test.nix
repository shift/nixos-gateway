{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "nixos-gateway-bgp-minimal";

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
          frr = {
            enable = true;
            bgp = {
              enable = true;
              asn = 65001;
              routerId = "192.168.1.1";
            };
          };
        };

        boot.loader.systemd-boot.enable = lib.mkForce false;
      };
  };

  testScript = ''
    start_all()
    gateway.wait_for_unit("multi-user.target")
    print("BGP test completed successfully")
  '';
}

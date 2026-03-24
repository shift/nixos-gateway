{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "nixos-gateway-bgp-direct";

  nodes = {
    machine =
      { config, pkgs, ... }:
      {
        # Direct FRR configuration without gateway module
        services.gateway = {
          enable = true;
          frr = {
            enable = true;
            bgp = {
              enable = true;
              asn = 65001;
              routerId = "192.168.1.1";
              config = ''
                router bgp 65001
                 bgp router-id 192.168.1.1
              '';
            };
          };
        };

        boot.loader.systemd-boot.enable = lib.mkForce false;
      };
  };

  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("frr.service")
    print("Direct BGP test completed successfully")
  '';
}

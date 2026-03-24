{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "nat-gateway-test";

  nodes.machine =
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
    };

  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    print("nat-gateway-test completed")
  '';
}

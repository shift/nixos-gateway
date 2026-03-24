{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "ha-cluster-test";

  nodes.machine =
    { config, pkgs, ... }:
    {
      imports = [ ../modules ];
      services.gateway.enable = true;
      services.gateway.interfaces = { lan = "eth0"; wan = "eth1"; };
    };

  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    print('ha-cluster-test completed')
  '';
}

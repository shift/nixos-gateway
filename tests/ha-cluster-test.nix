{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "ha-cluster-test";

  nodes.machine =
    { config, pkgs, ... }:
    {
      imports = [ ../modules ];
      services.gateway.enable = true;
    };

  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    echo 'ha-cluster-test completed'
  '';
}

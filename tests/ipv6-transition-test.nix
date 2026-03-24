{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "ipv6-transition-test";

  nodes.machine =
    { config, pkgs, ... }:
    {
      imports = [ ../modules ];
      services.gateway.enable = true;
    };

  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    echo 'ipv6-transition-test completed'
  '';
}

{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "interface-management-failover-test";

  nodes.machine = { config, pkgs, ... }: {
    imports = [ ../modules/interface-management-failover.nix ];
  };

  testScript = ''
    start_all()

    echo 'interface-management-failover test completed'
  '';
}

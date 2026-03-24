{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "interface-management-failover-test";

  nodes.machine = { config, pkgs, ... }: {
    imports = [ ../modules/interface-management-failover.nix ];
  };

  testScript = ''
    start_all()

    print('interface-management-failover test completed')
  '';
}

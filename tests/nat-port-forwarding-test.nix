{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "nat-port-forwarding-test";

  nodes.machine = { config, pkgs, ... }: {
    imports = [ ../modules/nat-port-forwarding.nix ];
  };

  testScript = ''
    start_all()
    
    print('nat-port-forwarding-test completed')
  '';
}

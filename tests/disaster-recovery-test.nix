{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "disaster-recovery-test";

  nodes.machine = { config, pkgs, ... }: {
    imports = [ ../modules/disaster-recovery.nix ];
  };

  testScript = ''
    start_all()

    print('disaster-recovery test completed')
  '';
}

{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "backup-recovery-test";

  nodes.machine = { config, pkgs, ... }: {
    imports = [ ../modules/backup-recovery.nix ];
  };

  testScript = ''
    start_all()
    
    print('backup-recovery-test completed')
  '';
}

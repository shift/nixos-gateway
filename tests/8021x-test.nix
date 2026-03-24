{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "8021x-test";

  nodes.machine = { config, pkgs, ... }: {
    imports = [ ../modules/8021x.nix ];
    # accessControl.nac is disabled by default; just verify module loads cleanly
  };

  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    print('8021x-test completed')
  '';
}

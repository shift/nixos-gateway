{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "config-diff-test";

  nodes.machine = { config, pkgs, ... }: {
    imports = [ ../modules/config-diff.nix ];
  };

  testScript = ''
    start_all()

    print('config-diff test completed')
  '';
}

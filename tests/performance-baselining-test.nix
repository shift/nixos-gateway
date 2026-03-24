{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "performance-baselining-test";

  nodes.machine = { config, pkgs, ... }: {
    imports = [ ../modules/performance-baselining.nix ];
  };

  testScript = ''
    start_all()

    print('performance-baselining test completed')
  '';
}

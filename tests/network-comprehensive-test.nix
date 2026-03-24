{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "network-comprehensive-test";

  nodes.machine = { config, pkgs, ... }: {
    imports = [ ../modules/network-comprehensive.nix ];
  };

  testScript = ''
    start_all()

    echo 'network-comprehensive test completed'
  '';
}

{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "config-reload-test";

  nodes.machine = { config, pkgs, ... }: {
    imports = [ ../modules/config-reload.nix ];
  };

  testScript = ''
    start_all()

    echo 'config-reload test completed'
  '';
}

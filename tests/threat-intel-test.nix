{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "threat-intel-test";

  nodes.machine = { config, pkgs, ... }: {
    imports = [ ../modules/threat-intel.nix ];
  };

  testScript = ''
    start_all()

    echo 'threat-intel test completed'
  '';
}

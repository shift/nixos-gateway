{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "service-mesh-test";

  nodes.machine = { config, pkgs, ... }: {
    imports = [ ../modules/service-mesh.nix ];
  };

  testScript = ''
    start_all()

    echo 'service-mesh test completed'
  '';
}

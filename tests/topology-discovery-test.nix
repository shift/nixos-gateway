{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "topology-discovery-test";

  nodes.machine = { config, pkgs, ... }: {
    imports = [ ../modules/topology-discovery.nix ];
  };

  testScript = ''
    start_all()

    echo 'topology-discovery test completed'
  '';
}

{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "topology-discovery-test";

  nodes.machine = { config, pkgs, ... }: {
    imports = [ ../modules/topology-discovery.nix ];
  };

  testScript = ''
    start_all()

    print('topology-discovery test completed')
  '';
}

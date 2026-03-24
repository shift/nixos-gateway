{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "routing-ip-forwarding-test";

  nodes.machine = { config, pkgs, ... }: {
    imports = [ ../modules/routing-ip-forwarding.nix ];
  };

  testScript = ''
    start_all()

    echo 'routing-ip-forwarding test completed'
  '';
}

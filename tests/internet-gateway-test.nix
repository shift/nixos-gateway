{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "internet-gateway-test";

  nodes.machine = { config, pkgs, ... }: {
    imports = [ ../modules/internet-gateway.nix ];
  };

  testScript = ''
    start_all()

    echo 'internet-gateway test completed'
  '';
}

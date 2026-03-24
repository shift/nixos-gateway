{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "api-gateway-test";

  nodes.machine = { config, pkgs, ... }: {
    imports = [ ../modules/api-gateway.nix ];
  };

  testScript = ''
    start_all()
    
    echo 'api-gateway-test test completed'
  '';
}

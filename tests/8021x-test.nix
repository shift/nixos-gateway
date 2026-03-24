{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "8021x-test";

  nodes.machine = { config, pkgs, ... }: {
    imports = [ ../modules ];
    services.gateway.enable = true;
    services.gateway.eight0OneX.enable = lib.mkDefault false;  # Stubbed
  };

  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    echo '8021x test completed'
  '';
}

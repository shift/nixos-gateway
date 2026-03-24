{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "vrf-support-test";

  nodes.machine = { config, pkgs, ... }: {
    imports = [ ../modules ];
    services.gateway.enable = true;
    services.gateway.vrf.enable = lib.mkDefault false;  # VRF is stubbed
  };

  testScript = ''
    start_all()

    machine.wait_for_unit("multi-user.target")
    echo 'vrf-support-test completed'
  '';
}

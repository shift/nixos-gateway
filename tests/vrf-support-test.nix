{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "vrf-support-test";

  nodes.machine = { config, pkgs, ... }: {
    imports = [ ../modules/vrf.nix ];
    # networking.vrfs is disabled by default; just verify module loads cleanly
  };

  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    print('vrf-support-test completed')
  '';
}

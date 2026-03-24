{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "device-posture-test";

  nodes.machine = { config, pkgs, ... }: {
    imports = [ ../modules/device-posture.nix ];
  };

  testScript = ''
    start_all()

    print('device-posture test completed')
  '';
}

{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "device-bandwidth-test";

  nodes.machine = { config, pkgs, ... }: {
    imports = [ ../modules/device-bandwidth.nix ../modules/qos.nix ../modules ];
    services.gateway.enable = true;
    services.gateway.interfaces = {
      lan = "eth0";
      wan = "eth1";
    };
    services.gateway.qos.enable = true;
    services.gateway.qos.trafficClasses = {};
    services.gateway.qos.extraForwardRules = "";
  };

  testScript = ''
    start_all()

    print('device-bandwidth test completed')
  '';
}

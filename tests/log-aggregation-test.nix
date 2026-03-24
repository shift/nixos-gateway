{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "log-aggregation-test";

  nodes.machine = { config, pkgs, ... }: {
    imports = [ ../modules ];
    services.gateway.enable = true;
    services.gateway.interfaces = { lan = "eth0"; wan = "eth1"; };
  };

  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    print('log-aggregation-test completed (stubbed)')
  '';
}

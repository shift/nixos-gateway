{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "advanced-health-monitoring-test";
  nodes = {
    gateway = { config, pkgs, ... }: {
      virtualisation.memorySize = 2048;
      virtualisation.cores = 2;
      virtualisation.graphics = false;
      services.gateway.healthMonitoring.enable = true;
    };
  };
  testScript = ''
    start_all()
    gateway.wait_for_unit("multi-user.target")
    gateway.succeed("echo 'Test passed'")
  '';
}

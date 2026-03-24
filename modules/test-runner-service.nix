{ config, lib, ... }:

with lib;

let
  cfg = config.simulator.testRunner;
in

{
  options.simulator.testRunner = {
    enable = mkEnableOption "Automated test execution within simulator";

    scenarios = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "List of scenarios to run automated tests for";
    };

    outputDir = mkOption {
      type = types.path;
      default = "/var/lib/simulator/test-results";
      description = "Directory to store test results";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.simulator-test-runner = {
      description = "Simulator Automated Test Runner";
      wantedBy = [ "multi-user.target" ];
      after = [ "simulator-api.service" ];

      serviceConfig = {
        ExecStart = "${pkgs.callPackage ./test-runner.nix {
          inherit (cfg) scenarios outputDir;
        }}/bin/test-runner";
        Restart = "on-failure";
        User = "simulator";
        Group = "simulator";
      };
    };

    # Ensure output directory exists
    systemd.tmpfiles.rules = [
      "d ${cfg.outputDir} 0750 simulator simulator -"
    ];
  };
}
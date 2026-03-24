{ config, lib, ... }:

with lib;

let
  cfg = config.simulator.integration;
in

{
  options.simulator.integration = {
    enable = mkEnableOption "Integration with existing test frameworks";

    testSuites = mkOption {
      type = types.listOf types.str;
      default = [ "comprehensive-feature-testing" ];
      description = "Test suites to integrate with";
    };

    autoTrigger = mkOption {
      type = types.bool;
      default = false;
      description = "Automatically trigger simulator tests when main tests run";
    };
  };

  config = mkIf cfg.enable {
    # Integration service that monitors test execution
    systemd.services.simulator-integration = {
      description = "Simulator Test Integration";
      wantedBy = [ "multi-user.target" ];
      after = [ "simulator-api.service" ];

      serviceConfig = {
        ExecStart = "${pkgs.callPackage ./integration-monitor.nix {
          inherit (cfg) testSuites autoTrigger;
        }}/bin/integration-monitor";
        Restart = "on-failure";
        User = "simulator";
        Group = "simulator";
      };
    };

    # Add simulator to the main test flake
    # This would modify the main flake.nix to include simulator tests
  };
}
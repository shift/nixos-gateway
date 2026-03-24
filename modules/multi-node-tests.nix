{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.gateway.multiNodeTests;
  clusterTester = import ../lib/cluster-tester.nix { inherit lib pkgs; };

  testScript = clusterTester.mkClusterTestScript {
    scenarios = cfg.scenarios;
    nodes = cfg.framework.orchestration.cluster.nodes or [ ];
  };

  testRunnerBin = pkgs.writeScriptBin "gateway-multi-node-test" testScript;

in
{
  options.services.gateway.multiNodeTests = {
    enable = mkEnableOption "Multi-Node Integration Testing Framework";

    framework = mkOption {
      type = types.attrs;
      default = { };
      description = "Test framework configuration";
    };

    scenarios = mkOption {
      type = types.listOf types.attrs;
      default = [ ];
      description = "List of test scenarios to execute";
    };

    validation = mkOption {
      type = types.attrs;
      default = { };
      description = "Validation rules";
    };

    reporting = mkOption {
      type = types.attrs;
      default = { };
      description = "Reporting configuration";
    };

    automation = mkOption {
      type = types.attrs;
      default = { };
      description = "Automation triggers";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ testRunnerBin ];

    # Ensure results directory exists
    systemd.tmpfiles.rules = [
      "d /var/lib/gateway/multi-node-tests 0755 root root -"
    ];
  };
}

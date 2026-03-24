{ config, lib, ... }:

with lib;

let
  cfg = config.services.taskVerification.functional;
in

{
  options.services.taskVerification.functional = {
    enable = mkEnableOption "Functional testing framework";

    tests = mkOption {
      type = types.listOf types.attrs;
      default = [];
      description = "Functional tests to run";
      example = [
        {
          name = "basic-gateway-functionality";
          description = "Test basic gateway service functionality";
          script = ''
            systemctl is-active gateway-service
            curl -f http://127.0.0.1:8080/api/health
          '';
          timeout = 30;
        }
      ];
    };

    environment = {
      setupScript = mkOption {
        type = types.lines;
        default = "";
        description = "Setup script to run before functional tests";
      };

      teardownScript = mkOption {
        type = types.lines;
        default = "";
        description = "Teardown script to run after functional tests";
      };
    };

    reporting = {
      detailed = mkOption {
        type = types.bool;
        default = true;
        description = "Generate detailed test reports";
      };

      artifacts = mkOption {
        type = types.listOf types.str;
        default = [ "logs" "config" "metrics" ];
        description = "Test artifacts to collect";
      };
    };
  };

  config = mkIf cfg.enable {
    # Functional test runner service
    systemd.services.functional-test-runner = {
      description = "Functional Test Runner";
      wantedBy = [ "multi-user.target" ];
      after = [ "task-verification-engine.service" ];

      serviceConfig = {
        ExecStart = "${pkgs.callPackage ./functional-test-runner.nix {
          inherit (cfg) tests environment reporting;
        }}/bin/functional-test-runner";
        Restart = "on-failure";
        User = "verification";
        Group = "verification";
        TimeoutSec = 600; # 10 minutes
      };
    };

    # Ensure test directories exist
    systemd.tmpfiles.rules = [
      "d /var/lib/task-verification/functional-tests 0750 verification verification -"
      "d /var/lib/task-verification/test-artifacts 0750 verification verification -"
    ];
  };
}
{ config, lib, ... }:

with lib;

let
  cfg = config.services.taskVerification;
in

{
  options.services.taskVerification = {
    enable = mkEnableOption "Task verification framework";

    engine = {
      type = mkOption {
        type = types.enum [ "basic" "comprehensive" ];
        default = "comprehensive";
        description = "Verification engine type";
      };

      components = mkOption {
        type = types.listOf types.attrs;
        default = [
          {
            name = "functional-verifier";
            description = "Verify functional requirements";
            enable = true;
          }
          {
            name = "integration-verifier";
            description = "Verify integration with existing modules";
            enable = true;
          }
          {
            name = "performance-verifier";
            description = "Verify performance characteristics";
            enable = true;
          }
          {
            name = "security-verifier";
            description = "Verify security requirements";
            enable = true;
          }
          {
            name = "regression-verifier";
            description = "Verify no regressions introduced";
            enable = true;
          }
        ];
        description = "Verification engine components";
      };
    };

    database = {
      path = mkOption {
        type = types.path;
        default = "/var/lib/task-verification/results.db";
        description = "Path to verification results database";
      };

      retention = {
        days = mkOption {
          type = types.int;
          default = 365;
          description = "Number of days to retain verification results";
        };

        maxRecords = mkOption {
          type = types.int;
          default = 50000;
          description = "Maximum number of records to retain";
        };
      };
    };

    automation = {
      enable = mkEnableOption "Automated verification execution";

      triggers = mkOption {
        type = types.listOf types.attrs;
        default = [
          {
            name = "on-task-completion";
            condition = "task.status == completed";
            action = "run-verification";
          }
          {
            name = "daily-verification";
            condition = "cron.daily";
            action = "run-all-verifications";
          }
        ];
        description = "Automation triggers";
      };

      execution = {
        parallel = mkOption {
          type = types.bool;
          default = true;
          description = "Run verifications in parallel";
        };

        maxConcurrent = mkOption {
          type = types.int;
          default = 5;
          description = "Maximum concurrent verifications";
        };

        timeout = mkOption {
          type = types.str;
          default = "30m";
          description = "Timeout per verification task";
        };

        retry = mkOption {
          type = types.int;
          default = 3;
          description = "Number of retries on failure";
        };
      };
    };
  };

  config = mkIf cfg.enable {
    # Verification engine service
    systemd.services.task-verification-engine = {
      description = "Task Verification Engine";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        ExecStart = "${pkgs.callPackage ./verification-engine.nix {
          inherit (cfg) engine database automation;
        }}/bin/verification-engine";
        Restart = "always";
        User = "verification";
        Group = "verification";
      };
    };

    # Create verification user and directories
    users.users.verification = {
      isSystemUser = true;
      group = "verification";
      home = "/var/lib/verification";
      createHome = true;
    };

    users.groups.verification = {};

    systemd.tmpfiles.rules = [
      "d /var/lib/task-verification 0750 verification verification -"
      "d /var/lib/task-verification/results 0750 verification verification -"
      "d /var/lib/task-verification/logs 0750 verification verification -"
    ];
  };
}
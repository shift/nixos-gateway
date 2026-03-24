{ config, lib, ... }:

with lib;

let
  cfg = config.services.taskVerification;
in

{
  imports = [
    ./functional-testing.nix
    ./integration-testing.nix
  ];

  options.services.taskVerification = {
    enable = mkEnableOption "Comprehensive task verification framework";

    categories = mkOption {
      type = types.listOf (types.enum [ "functional" "integration" "performance" "security" "regression" ]);
      default = [ "functional" "integration" "performance" "security" "regression" ];
      description = "Verification categories to enable";
    };

    performance = {
      enable = mkOption {
        type = types.bool;
        default = elem "performance" cfg.categories;
        description = "Enable performance testing";
      };

      benchmarks = mkOption {
        type = types.listOf types.attrs;
        default = [
          {
            name = "api-response-time";
            description = "API response time benchmark";
            command = "curl -w '%{time_total}' -s http://127.0.0.1:8080/api/health";
            threshold = 0.1; # 100ms
            unit = "seconds";
          }
          {
            name = "memory-usage";
            description = "Memory usage benchmark";
            command = "ps aux --no-headers -o pmem -C gateway-service | awk '{sum+=$1} END {print sum}'";
            threshold = 10.0; # 10%
            unit = "percent";
          }
        ];
        description = "Performance benchmarks to run";
      };
    };

    security = {
      enable = mkOption {
        type = types.bool;
        default = elem "security" cfg.categories;
        description = "Enable security testing";
      };

      scans = mkOption {
        type = types.listOf types.attrs;
        default = [
          {
            name = "configuration-security";
            description = "Check for insecure configuration";
            command = "! grep -r 'password.*=' /etc/gateway/ 2>/dev/null";
          }
          {
            name = "service-permissions";
            description = "Check service file permissions";
            command = "test -f /etc/gateway/config.json && stat -c '%a' /etc/gateway/config.json | grep -q '600'";
          }
        ];
        description = "Security scans to perform";
      };
    };

    regression = {
      enable = mkOption {
        type = types.bool;
        default = elem "regression" cfg.categories;
        description = "Enable regression testing";
      };

      baselines = mkOption {
        type = types.path;
        default = "/var/lib/task-verification/baselines";
        description = "Directory containing baseline test results";
      };
    };
  };

  config = mkIf cfg.enable {
    # Enable selected test categories
    services.taskVerification.functional.enable = elem "functional" cfg.categories;
    services.taskVerification.integration.enable = elem "integration" cfg.categories;

    # Performance testing service
    systemd.services.performance-test-runner = mkIf cfg.performance.enable {
      description = "Performance Test Runner";
      wantedBy = [ "multi-user.target" ];
      after = [ "integration-test-runner.service" ];

      serviceConfig = {
        ExecStart = "${pkgs.callPackage ./performance-test-runner.nix {
          benchmarks = cfg.performance.benchmarks;
        }}/bin/performance-test-runner";
        Restart = "on-failure";
        User = "verification";
        Group = "verification";
      };
    };

    # Security testing service
    systemd.services.security-test-runner = mkIf cfg.security.enable {
      description = "Security Test Runner";
      wantedBy = [ "multi-user.target" ];
      after = [ "performance-test-runner.service" ];

      serviceConfig = {
        ExecStart = "${pkgs.callPackage ./security-test-runner.nix {
          scans = cfg.security.scans;
        }}/bin/security-test-runner";
        Restart = "on-failure";
        User = "verification";
        Group = "verification";
      };
    };

    # Regression testing service
    systemd.services.regression-test-runner = mkIf cfg.regression.enable {
      description = "Regression Test Runner";
      wantedBy = [ "multi-user.target" ];
      after = [ "security-test-runner.service" ];

      serviceConfig = {
        ExecStart = "${pkgs.callPackage ./regression-test-runner.nix {
          baselines = cfg.regression.baselines;
        }}/bin/regression-test-runner";
        Restart = "on-failure";
        User = "verification";
        Group = "verification";
      };
    };

    # Ensure baseline directory exists
    systemd.tmpfiles.rules = mkIf cfg.regression.enable [
      "d ${cfg.regression.baselines} 0750 verification verification -"
    ];
  };
}
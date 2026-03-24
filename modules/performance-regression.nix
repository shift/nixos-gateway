{ config, lib, ... }:

with lib;

let
  cfg = config.services.performanceRegression;
in

{
  options.services.performanceRegression = {
    enable = mkEnableOption "Performance regression testing framework";

    framework = {
      engine = {
        type = mkOption {
          type = types.enum [ "benchmark-based" "simulation-based" ];
          default = "benchmark-based";
          description = "Performance testing engine type";
        };

        tools = mkOption {
          type = types.listOf types.attrs;
          default = [
            {
              name = "wrk";
              type = "http-load";
              description = "HTTP load testing tool";
              enable = true;
            }
            {
              name = "iperf3";
              type = "network-throughput";
              description = "Network throughput testing";
              enable = true;
            }
            {
              name = "dnsperf";
              type = "dns-performance";
              description = "DNS performance testing";
              enable = true;
            }
            {
              name = "custom";
              type = "gateway-specific";
              description = "Custom gateway performance tests";
              enable = true;
            }
          ];
          description = "Performance testing tools";
        };
      };

      baseline = {
        creation = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Automatically create performance baselines";
          };

          conditions = mkOption {
            type = types.listOf types.str;
            default = [ "stable-branch" "clean-environment" "minimal-load" ];
            description = "Conditions for baseline creation";
          };
        };

        storage = {
          type = mkOption {
            type = types.enum [ "database" "filesystem" ];
            default = "database";
            description = "Baseline storage type";
          };

          path = mkOption {
            type = types.path;
            default = "/var/lib/performance-baseline";
            description = "Path to baseline storage";
          };

          metrics = mkOption {
            type = types.listOf types.str;
            default = [ "throughput" "latency" "cpu-usage" "memory-usage" "error-rate" ];
            description = "Metrics to baseline";
          };
        };

        versioning = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Enable baseline versioning";
          };

          retention = mkOption {
            type = types.str;
            default = "90d";
            description = "Baseline retention period";
          };

          maxVersions = mkOption {
            type = types.int;
            default = 30;
            description = "Maximum number of baseline versions to keep";
          };
        };
      };

      regression = {
        detection = {
          algorithm = mkOption {
            type = types.enum [ "threshold" "trend" "statistical" ];
            default = "statistical";
            description = "Regression detection algorithm";
          };

          methods = mkOption {
            type = types.listOf types.attrs;
            default = [
              {
                name = "threshold";
                description = "Simple threshold-based detection";
                parameters = {
                  degradation = 10.0; # 10% degradation
                  confidence = 95.0;  # 95% confidence
                };
              }
              {
                name = "trend";
                description = "Trend-based detection";
                parameters = {
                  window = "7d";
                  slope = -0.05; # 5% negative trend
                };
              }
              {
                name = "statistical";
                description = "Statistical significance testing";
                parameters = {
                  test = "t-test";
                  significance = 0.05;
                };
              }
            ];
            description = "Regression detection methods";
          };
        };

        alerting = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Enable regression alerting";
          };

          thresholds = mkOption {
            type = types.listOf types.attrs;
            default = [
              {
                metric = "throughput";
                degradation = 15.0;
                severity = "high";
              }
              {
                metric = "latency";
                degradation = 20.0;
                severity = "medium";
              }
              {
                metric = "error-rate";
                degradation = 50.0;
                severity = "critical";
              }
            ];
            description = "Alerting thresholds";
          };
        };
      };
    };

    scenarios = mkOption {
      type = types.listOf types.attrs;
      default = [
        {
          name = "dns-performance";
          description = "DNS resolution performance test";
          category = "service";
          enable = true;
        }
        {
          name = "dhcp-performance";
          description = "DHCP server performance test";
          category = "service";
          enable = true;
        }
        {
          name = "network-throughput";
          description = "Network throughput performance test";
          category = "network";
          enable = true;
        }
        {
          name = "system-resources";
          description = "System resource utilization test";
          category = "system";
          enable = true;
        }
      ];
      description = "Performance test scenarios";
    };
  };

  config = mkIf cfg.enable {
    # Performance regression testing service
    systemd.services.performance-regression-engine = {
      description = "Performance Regression Testing Engine";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        ExecStart = "${pkgs.callPackage ./performance-regression-engine.nix {
          inherit (cfg) framework scenarios;
        }}/bin/performance-regression-engine";
        Restart = "on-failure";
        User = "performance";
        Group = "performance";
      };
    };

    # Create performance user and directories
    users.users.performance = {
      isSystemUser = true;
      group = "performance";
      home = "/var/lib/performance";
      createHome = true;
    };

    users.groups.performance = {};

    systemd.tmpfiles.rules = [
      "d /var/lib/performance-regression 0750 performance performance -"
      "d /var/lib/performance-baseline 0750 performance performance -"
      "d /var/lib/performance-results 0750 performance performance -"
    ];

    # Install required performance testing tools
    environment.systemPackages = with pkgs; [
      wrk
      iperf3
      dnsperf
      stress
      sysstat
      bc
    ];
  };
}

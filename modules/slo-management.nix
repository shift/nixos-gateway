{ config, lib, ... }:

with lib;

let
  cfg = config.services.sloManagement;
in

{
  options.services.sloManagement = {
    enable = mkEnableOption "Service Level Objectives management framework";

    objectives = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          description = mkOption {
            type = types.str;
            description = "Human-readable description of the SLO";
          };

          service = mkOption {
            type = types.str;
            description = "Service this SLO applies to (dns, dhcp, network, etc.)";
          };

          sli = mkOption {
            type = types.attrsOf (types.submodule {
              options = {
                metric = mkOption {
                  type = types.str;
                  description = "Prometheus metric name for this SLI";
                };

                type = mkOption {
                  type = types.enum [ "success-rate" "latency" "availability" "custom" ];
                  description = "Type of SLI measurement";
                };

                threshold = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = "Threshold value for latency/availability SLIs";
                };

                percentile = mkOption {
                  type = types.nullOr types.int;
                  default = null;
                  description = "Percentile for latency measurements (e.g., 95 for 95th percentile)";
                };

                goodMetric = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = "Metric for successful events (for success-rate SLIs)";
                };

                totalMetric = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = "Metric for total events (for success-rate SLIs)";
                };
              };
            });
            description = "Service Level Indicators for this SLO";
          };

          slo = mkOption {
            type = types.submodule {
              options = {
                target = mkOption {
                  type = types.float;
                  description = "SLO target as percentage (e.g., 99.9 for 99.9%)";
                };

                timeWindow = mkOption {
                  type = types.str;
                  description = "Time window for SLO calculation (e.g., '30d', '7d')";
                };

                alerting = mkOption {
                  type = types.submodule {
                    options = {
                      burnRateFast = mkOption {
                        type = types.float;
                        default = 14.4;
                        description = "Fast burn rate threshold (error budget exhaustion time in hours)";
                      };

                      burnRateSlow = mkOption {
                        type = types.float;
                        default = 6.0;
                        description = "Slow burn rate threshold (error budget exhaustion time in hours)";
                      };
                    };
                  };
                  default = {};
                  description = "Alerting configuration for this SLO";
                };
              };
            };
            description = "Service Level Objective definition";
          };

          enabled = mkOption {
            type = types.bool;
            default = true;
            description = "Whether this SLO is enabled";
          };
        };
      });
      default = {};
      description = "SLO definitions for various services";
    };

    database = {
      path = mkOption {
        type = types.path;
        default = "/var/lib/slo-management/slo-data.db";
        description = "Path to SLO data database";
      };

      retention = {
        days = mkOption {
          type = types.int;
          default = 90;
          description = "Days to retain SLO measurement data";
        };
      };
    };

    alerting = {
      enable = mkEnableOption "SLO alerting";

      channels = mkOption {
        type = types.attrsOf (types.submodule {
          options = {
            type = mkOption {
              type = types.enum [ "email" "slack" "pagerduty" ];
              description = "Alerting channel type";
            };

            enabled = mkOption {
              type = types.bool;
              default = true;
              description = "Whether this channel is enabled";
            };

            config = mkOption {
              type = types.attrs;
              default = {};
              description = "Channel-specific configuration";
            };
          };
        });
        default = {};
        description = "Alerting channels configuration";
      };
    };

    api = {
      enable = mkEnableOption "SLO management API";

      port = mkOption {
        type = types.port;
        default = 8081;
        description = "Port for the SLO management API";
      };
    };
  };

  config = mkIf cfg.enable {
    # SLO management service
    systemd.services.slo-management = {
      description = "SLO Management Service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        ExecStart = "${pkgs.callPackage ./slo-management-service.nix {
          inherit (cfg) objectives database alerting api;
        }}/bin/slo-management-service";
        Restart = "always";
        User = "slo";
        Group = "slo";
      };
    };

    # SLO calculation service
    systemd.services.slo-calculator = {
      description = "SLO Calculator Service";
      wantedBy = [ "multi-user.target" ];
      after = [ "slo-management.service" ];

      serviceConfig = {
        ExecStart = "${pkgs.callPackage ./slo-calculator.nix {
          inherit (cfg) objectives database;
        }}/bin/slo-calculator";
        Restart = "always";
        User = "slo";
        Group = "slo";
      };
    };

    # Create SLO user and directories
    users.users.slo = {
      isSystemUser = true;
      group = "slo";
      home = "/var/lib/slo-management";
      createHome = true;
    };

    users.groups.slo = {};

    systemd.tmpfiles.rules = [
      "d /var/lib/slo-management 0750 slo slo -"
      "d /var/lib/slo-management/data 0750 slo slo -"
      "d /var/lib/slo-management/logs 0750 slo slo -"
    ];

    # Default SLOs for common services
    services.sloManagement.objectives = {
      "dns-resolution" = {
        description = "DNS query resolution success and latency";
        service = "dns";

        sli = {
          successRate = {
            metric = "unbound_queries_total";
            type = "success-rate";
            goodMetric = "unbound_answers_total";
            totalMetric = "unbound_queries_total";
          };

          latency = {
            metric = "unbound_request_duration_seconds";
            type = "latency";
            threshold = "0.1";
            percentile = 95;
          };
        };

        slo = {
          target = 99.9;
          timeWindow = "30d";
        };
      };

      "dhcp-lease" = {
        description = "DHCP lease assignment success";
        service = "dhcp";

        sli = {
          successRate = {
            metric = "kea_dhcp4_lease_total";
            type = "success-rate";
            goodMetric = "kea_dhcp4_lease_success_total";
            totalMetric = "kea_dhcp4_lease_total";
          };

          latency = {
            metric = "kea_dhcp4_packet_processing_time_seconds";
            type = "latency";
            threshold = "1.0";
            percentile = 90;
          };
        };

        slo = {
          target = 99.5;
          timeWindow = "7d";
        };
      };

      "network-availability" = {
        description = "Network interface availability";
        service = "network";

        sli = {
          availability = {
            metric = "node_network_up";
            type = "availability";
            threshold = "1";
          };
        };

        slo = {
          target = 99.99;
          timeWindow = "30d";
        };
      };
    };
  };
}
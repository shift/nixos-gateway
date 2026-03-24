{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.gateway.slo;
  sloCalculator = import ../../lib/slo-calculator.nix { inherit lib; };

  # Helper to sanitize metrics name
  sanitizeMetric = name: lib.replaceStrings [ "-" "." ] [ "_" "_" ] name;

  # Type definitions for SLI/SLO
  sliType = lib.types.submodule {
    options = {
      successRate = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.submodule {
            options = {
              metric = lib.mkOption { type = lib.types.str; };
              total = lib.mkOption { type = lib.types.str; };
              good = lib.mkOption { type = lib.types.str; };
            };
          }
        );
        default = null;
        description = "Success rate based SLI";
      };
      latency = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.submodule {
            options = {
              metric = lib.mkOption { type = lib.types.str; };
              threshold = lib.mkOption { type = lib.types.str; };
              percentile = lib.mkOption { type = lib.types.number; };
            };
          }
        );
        default = null;
        description = "Latency based SLI";
      };
      availability = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.submodule {
            options = {
              metric = lib.mkOption { type = lib.types.str; };
              threshold = lib.mkOption { type = lib.types.number; };
            };
          }
        );
        default = null;
        description = "Availability based SLI";
      };
      packetLoss = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.submodule {
            options = {
              metric = lib.mkOption { type = lib.types.str; };
              threshold = lib.mkOption { type = lib.types.number; };
            };
          }
        );
        default = null;
        description = "Packet loss based SLI";
      };
    };
  };

  alertingConfigType = lib.types.submodule {
    options = {
      burnRateFast = lib.mkOption {
        type = lib.types.float;
        default = 14.4; # ~2h for 30d window
        description = "Fast burn rate threshold";
      };
      burnRateSlow = lib.mkOption {
        type = lib.types.float;
        default = 6.0; # ~6h for 30d window
        description = "Slow burn rate threshold";
      };
    };
  };

  objectiveType = lib.types.submodule {
    options = {
      description = lib.mkOption {
        type = lib.types.str;
        description = "Human readable description of the SLO";
      };
      sli = lib.mkOption {
        type = sliType;
        description = "Service Level Indicator definition";
      };
      slo = lib.mkOption {
        type = lib.types.submodule {
          options = {
            target = lib.mkOption {
              type = lib.types.number; # e.g., 99.9
              description = "SLO Target percentage (0-100)";
            };
            timeWindow = lib.mkOption {
              type = lib.types.str; # e.g. "30d"
              default = "30d";
              description = "Time window for the SLO";
            };
            alerting = lib.mkOption {
              type = alertingConfigType;
              default = { };
              description = "Alerting thresholds for this SLO";
            };
          };
        };
        description = "Service Level Objective targets";
      };
    };
  };

  channelType = lib.types.submodule {
    options = {
      enabled = lib.mkEnableOption "Enable this channel";
      recipients = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
      webhook = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      channel = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      integrationKey = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      severity = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
    };
  };

  policyType = lib.types.submodule {
    options = {
      condition = lib.mkOption { type = lib.types.str; };
      severity = lib.mkOption { type = lib.types.str; };
      channels = lib.mkOption { type = lib.types.listOf lib.types.str; };
    };
  };

  scheduleType = lib.types.submodule {
    options = {
      time = lib.mkOption {
        type = lib.types.str;
        default = "09:00";
      };
      day = lib.mkOption {
        type = lib.types.either lib.types.str lib.types.int;
        default = "Monday";
      };
      recipients = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
      include = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
    };
  };

  dashboardPanelType = lib.types.submodule {
    options = {
      title = lib.mkOption { type = lib.types.str; };
      type = lib.mkOption { type = lib.types.str; };
      objectives = lib.mkOption {
        type = lib.types.str;
        default = "all";
      };
    };
  };

  # Generate Prometheus alerting rules for an SLO
  generateAlertingRules =
    name: sloConfig:
    let
      target = sloConfig.slo.target;
      # Calculate error budget from target (e.g., 99.9% -> 0.001 error budget)
      errorBudget = 1.0 - (target / 100.0);

      # Burn rate thresholds
      burnRateFast = sloConfig.slo.alerting.burnRateFast;
      burnRateSlow = sloConfig.slo.alerting.burnRateSlow;

      # Time windows for burn rate calculation
      windowFast = "1h"; # Standard fast window
      windowSlow = "6h"; # Standard slow window

    in
    [
      {
        alert = "SLOBurnRateFast_${sanitizeMetric name}";
        expr = ''
          (
            rate(slo_errors_total{slo="${name}"}[${windowFast}])
            /
            rate(slo_requests_total{slo="${name}"}[${windowFast}])
          ) > (${toString (errorBudget * burnRateFast)})
        '';
        for = "2m";
        labels = {
          severity = "critical";
          slo = name;
        };
        annotations = {
          summary = "Fast burn rate for SLO ${name}";
          description = "Error budget is burning at rate ${toString burnRateFast}x (budget: ${toString errorBudget})";
        };
      }
      {
        alert = "SLOBurnRateSlow_${sanitizeMetric name}";
        expr = ''
          (
            rate(slo_errors_total{slo="${name}"}[${windowSlow}])
            /
            rate(slo_requests_total{slo="${name}"}[${windowSlow}])
          ) > (${toString (errorBudget * burnRateSlow)})
        '';
        for = "15m";
        labels = {
          severity = "warning";
          slo = name;
        };
        annotations = {
          summary = "Slow burn rate for SLO ${name}";
          description = "Error budget is burning at rate ${toString burnRateSlow}x (budget: ${toString errorBudget})";
        };
      }
    ];

  # Generate recording rules to normalize metrics for SLOs
  # This creates slo_requests_total and slo_errors_total from the configured SLIs
  generateRecordingRules =
    name: sloConfig:
    let
      sli = sloConfig.sli;
      # Handle different SLI types
      # 1. Success Rate
      successRateRules =
        if sli.successRate != null then
          [
            {
              record = "slo_requests_total";
              labels = {
                slo = name;
              };
              expr = sli.successRate.total;
            }
            {
              record = "slo_errors_total";
              labels = {
                slo = name;
              };
              # Errors = Total - Success
              expr = "${sli.successRate.total} - ${sli.successRate.good}";
            }
          ]
        else
          [ ];

      # 2. Latency
      latencyRules =
        if sli.latency != null then
          [
            {
              record = "slo_requests_total";
              labels = {
                slo = name;
                type = "latency";
              };
              # Total requests is usually the count of the histogram
              expr = "${sli.latency.metric}_count";
            }
            {
              record = "slo_errors_total";
              labels = {
                slo = name;
                type = "latency";
              };
              # Errors are requests slower than threshold
              # Assuming histogram format: metric_bucket{le="threshold"}
              # Errors = Total - Count(le<=threshold)
              expr = "${sli.latency.metric}_count - ${sli.latency.metric}_bucket{le=\"${sli.latency.threshold}\"}";
            }
          ]
        else
          [ ];

      # 3. Availability
      availabilityRules =
        if sli.availability != null then
          [
            {
              record = "slo_requests_total";
              labels = {
                slo = name;
                type = "availability";
              };
              # For availability, we treat each scrape as a request (1 per scrape interval)
              # This is a simplification but common for boolean metrics
              expr = "count_over_time(${sli.availability.metric}[1m])";
            }
            {
              record = "slo_errors_total";
              labels = {
                slo = name;
                type = "availability";
              };
              # Errors are when metric != threshold (usually 1 for up)
              expr = "count_over_time(${sli.availability.metric}[1m]) - count_over_time(${sli.availability.metric}{app=\"gateway\"} == ${toString sli.availability.threshold}[1m])";
            }
          ]
        else
          [ ];

    in
    successRateRules ++ latencyRules ++ availabilityRules;

in
{
  options.services.gateway.slo = {
    enable = lib.mkEnableOption "Service Level Objectives Framework";

    objectives = lib.mkOption {
      type = lib.types.attrsOf objectiveType;
      default = { };
      description = "Map of SLO definitions";
    };

    alerting = {
      enable = lib.mkEnableOption "SLO Alerting";
      channels = lib.mkOption {
        type = lib.types.attrsOf channelType;
        default = { };
        description = "Alerting channels configuration";
      };
      policies = lib.mkOption {
        type = lib.types.attrsOf policyType;
        default = { };
        description = "Alerting policies";
      };
    };

    reporting = {
      enable = lib.mkEnableOption "SLO Reporting";
      schedules = lib.mkOption {
        type = lib.types.attrsOf scheduleType;
        default = { };
        description = "Reporting schedules";
      };
    };

    dashboard = {
      enable = lib.mkEnableOption "SLO Dashboard Generation";
      title = lib.mkOption {
        type = lib.types.str;
        default = "Gateway SLO Dashboard";
      };
      panels = lib.mkOption {
        type = lib.types.listOf dashboardPanelType;
        default = [ ];
        description = "Dashboard panels configuration";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Generate Prometheus Rules
    # We use ruleFiles instead of rules to avoid validation issues during build time
    # and to keep configurations clean.
    # Note: Using environment.etc to simulate file generation for testing as services.prometheus may not be enabled/available in all contexts
    environment.etc."gateway/monitoring/prometheus-slo-rules.yml".text = builtins.toJSON {
      groups = lib.concatMap (
        name:
        let
          objective = cfg.objectives.${name};
        in
        [
          {
            name = "slo_${sanitizeMetric name}";
            rules = (generateRecordingRules name objective) ++ (generateAlertingRules name objective);
          }
        ]
      ) (lib.attrNames cfg.objectives);
    };

    # Generate Alertmanager Configuration stub
    environment.etc."gateway/monitoring/alertmanager-slo-config.yml".text = builtins.toJSON {
      route = {
        receiver = "default-receiver";
        routes = lib.mapAttrsToList (name: policy: {
          match = {
            alertname = name;
          };
          receiver = lib.concatStringsSep "," policy.channels;
        }) cfg.alerting.policies;
      };
      receivers = lib.mapAttrsToList (name: channel: {
        name = name;
        email_configs = lib.optional (name == "email" && channel.enabled) {
          to = lib.concatStringsSep "," channel.recipients;
        };
        slack_configs = lib.optional (name == "slack" && channel.enabled) {
          channel = channel.channel;
          api_url = channel.webhook;
        };
        pagerduty_configs = lib.optional (name == "pagerduty" && channel.enabled) {
          routing_key = channel.integrationKey;
          severity = channel.severity;
        };
      }) cfg.alerting.channels;
    };

    # Generate Dashboard Configuration stub (e.g. for Grafana)
    environment.etc."gateway/monitoring/grafana-slo-dashboard.json".text = builtins.toJSON {
      dashboard = {
        title = cfg.dashboard.title;
        panels = map (panel: {
          title = panel.title;
          type = panel.type;
          targets = if panel.objectives == "all" then lib.attrNames cfg.objectives else [ panel.objectives ];
        }) cfg.dashboard.panels;
      };
    };
  };
}

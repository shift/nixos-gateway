{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.gateway.configDrift;
  driftDetector = import ../lib/drift-detector.nix { inherit lib; };

  # Generate baseline creation scripts
  baselineScripts = {
    daily = driftDetector.utils.generateBaselineScript cfg.baseline;
  };

  # Generate drift detection scripts
  driftDetectionScripts = lib.mapAttrs' (scanName: scan:
    nameValuePair "drift-${scanName}" (driftDetector.utils.generateDriftDetectionScript cfg)
  ) (lib.listToAttrs (map (s: { name = s.name; value = s; }) cfg.monitoring.scheduled.scans));

  # Generate monitoring script
  monitoringScript = driftDetector.utils.generateMonitoringScript cfg.monitoring;

  # Python configuration drift detector service
  configDriftService = pkgs.writeScriptBin "gateway-drift-detector" ''
    #!${pkgs.python3.withPackages (ps: [ ps.requests ])}/bin/python3
    ${driftDetector.driftDetectorUtils}
  '';

in
{
  options.services.gateway.configDrift = {
    enable = mkEnableOption "Configuration Drift Detection";

    baseline = mkOption {
      type = types.submodule {
        options = {
          creation = mkOption {
            type = types.submodule {
              options = {
                schedule = mkOption {
                  type = types.str;
                  default = "daily";
                  description = "Baseline creation schedule";
                };

                time = mkOption {
                  type = types.str;
                  default = "03:00";
                  description = "Baseline creation time";
                };

                approval = mkOption {
                  type = types.enum [ "automatic" "manual" ];
                  default = "automatic";
                  description = "Baseline approval method";
                };

                sources = mkOption {
                  type = types.listOf types.str;
                  default = [
                    "/etc/nixos"
                    "/etc/gateway"
                    "/var/lib/gateway"
                  ];
                  description = "Baseline source paths";
                };
              };
            };
            default = {};
            description = "Baseline creation configuration";
          };

          storage = mkOption {
            type = types.submodule {
              options = {
                path = mkOption {
                  type = types.str;
                  default = "/var/lib/config-drift/baselines";
                  description = "Baseline storage path";
                };

                retention = mkOption {
                  type = types.str;
                  default = "90d";
                  description = "Baseline retention period";
                };

                encryption = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Encrypt baseline storage";
                };

                versioning = mkOption {
                  type = types.submodule {
                    options = {
                      enable = mkOption {
                        type = types.bool;
                        default = true;
                        description = "Enable baseline versioning";
                      };

                      maxVersions = mkOption {
                        type = types.int;
                        default = 30;
                        description = "Maximum baseline versions to keep";
                      };

                      compression = mkOption {
                        type = types.bool;
                        default = true;
                        description = "Compress baseline files";
                      };
                    };
                  };
                  default = {};
                  description = "Baseline versioning configuration";
                };
              };
            };
            default = {};
            description = "Baseline storage configuration";
          };

          validation = mkOption {
            type = types.submodule {
              options = {
                enable = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Enable baseline validation";
                };

                checks = mkOption {
                  type = types.listOf types.str;
                  default = [
                    "syntax-validation"
                    "semantic-validation"
                    "security-validation"
                    "compliance-validation"
                  ];
                  description = "Baseline validation checks";
                };
              };
            };
            default = {};
            description = "Baseline validation configuration";
          };
        };
      };
      default = {};
      description = "Configuration baseline settings";
    };

    monitoring = mkOption {
      type = types.submodule {
        options = {
          realTime = mkOption {
            type = types.submodule {
              options = {
                enable = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Enable real-time monitoring";
                };

                paths = mkOption {
                  type = types.listOf types.str;
                  default = [
                    "/etc/nixos"
                    "/etc/gateway"
                    "/var/lib/gateway"
                    "/etc/systemd"
                  ];
                  description = "Paths to monitor in real-time";
                };

                events = mkOption {
                  type = types.listOf types.str;
                  default = [
                    "create"
                    "modify"
                    "delete"
                    "permission-change"
                    "ownership-change"
                  ];
                  description = "File events to monitor";
                };

                filters = mkOption {
                  type = types.listOf (types.submodule {
                    options = {
                      path = mkOption {
                        type = types.str;
                        description = "Path pattern to filter";
                      };

                      action = mkOption {
                        type = types.enum [ "ignore" "alert" ];
                        default = "ignore";
                        description = "Action for matching paths";
                      };
                    };
                  });
                  default = [
                    { path = "*.tmp"; action = "ignore"; }
                    { path = "*.log"; action = "ignore"; }
                    { path = "cache/*"; action = "ignore"; }
                  ];
                  description = "Monitoring filters";
                };
              };
            };
            default = {};
            description = "Real-time monitoring configuration";
          };

          scheduled = mkOption {
            type = types.submodule {
              options = {
                enable = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Enable scheduled monitoring";
                };

                scans = mkOption {
                  type = types.listOf (types.submodule {
                    options = {
                      name = mkOption {
                        type = types.str;
                        description = "Scan name";
                      };

                      schedule = mkOption {
                        type = types.str;
                        description = "Scan schedule";
                      };

                      time = mkOption {
                        type = types.str;
                        default = "04:00";
                        description = "Scan time";
                      };

                      scope = mkOption {
                        type = types.enum [ "full" "security" "compliance" ];
                        default = "full";
                        description = "Scan scope";
                      };
                    };
                  });
                  default = [
                    {
                      name = "full-scan";
                      schedule = "daily";
                      time = "04:00";
                      scope = "full";
                    }
                    {
                      name = "security-scan";
                      schedule = "hourly";
                      scope = "security";
                    }
                    {
                      name = "compliance-scan";
                      schedule = "weekly";
                      scope = "compliance";
                    }
                  ];
                  description = "Scheduled scan configurations";
                };
              };
            };
            default = {};
            description = "Scheduled monitoring configuration";
          };

          comparison = mkOption {
            type = types.submodule {
              options = {
                algorithm = mkOption {
                  type = types.enum [ "hash-based" "content-diff" "attribute-check" ];
                  default = "hash-based";
                  description = "Comparison algorithm";
                };

                method = mkOption {
                  type = types.enum [ "sha256" "sha512" "md5" ];
                  default = "sha256";
                  description = "Hash method for comparison";
                };

                attributes = mkOption {
                  type = types.listOf types.str;
                  default = [
                    "content"
                    "permissions"
                    "ownership"
                    "timestamps"
                  ];
                  description = "File attributes to compare";
                };

                sensitivity = mkOption {
                  type = types.attrsOf types.str;
                  default = {
                    high = "security-files";
                    medium = "config-files";
                    low = "log-files";
                  };
                  description = "Sensitivity levels by file type";
                };
              };
            };
            default = {};
            description = "File comparison configuration";
          };
        };
      };
      default = {};
      description = "Monitoring configuration";
    };

    drift = mkOption {
      type = types.submodule {
        options = {
          classification = mkOption {
            type = types.submodule {
              options = {
                severity = mkOption {
                  type = types.listOf (types.submodule {
                    options = {
                      level = mkOption {
                        type = types.enum [ "critical" "high" "medium" "low" ];
                        description = "Severity level";
                      };

                      score = mkOption {
                        type = types.int;
                        description = "Severity score threshold";
                      };

                      types = mkOption {
                        type = types.listOf types.str;
                        description = "File types for this severity";
                      };

                      action = mkOption {
                        type = types.str;
                        description = "Default action for this severity";
                      };
                    };
                  });
                  default = [
                    {
                      level = "critical";
                      score = 90;
                      types = [ "security-policy" "access-control" "encryption-keys" ];
                      action = "immediate-alert";
                    }
                    {
                      level = "high";
                      score = 75;
                      types = [ "service-config" "network-config" "firewall-rules" ];
                      action = "alert-and-remediate";
                    }
                    {
                      level = "medium";
                      score = 50;
                      types = [ "system-config" "application-config" ];
                      action = "alert-and-log";
                    }
                    {
                      level = "low";
                      score = 25;
                      types = [ "documentation" "log-config" ];
                      action = "log-only";
                    }
                  ];
                  description = "Drift severity classification";
                };
              };
            };
            default = {};
            description = "Drift classification configuration";
          };

          detection = mkOption {
            type = types.submodule {
              options = {
                algorithms = mkOption {
                  type = types.listOf (types.submodule {
                    options = {
                      name = mkOption {
                        type = types.str;
                        description = "Algorithm name";
                      };

                      type = mkOption {
                        type = types.enum [ "cryptographic" "attribute" "behavioral" ];
                        description = "Algorithm type";
                      };

                      sensitivity = mkOption {
                        type = types.enum [ "high" "medium" "low" ];
                        description = "Detection sensitivity";
                      };
                    };
                  });
                  default = [
                    {
                      name = "content-hash";
                      type = "cryptographic";
                      sensitivity = "high";
                    }
                    {
                      name = "permission-check";
                      type = "attribute";
                      sensitivity = "medium";
                    }
                    {
                      name = "timestamp-analysis";
                      type = "behavioral";
                      sensitivity = "low";
                    }
                  ];
                  description = "Drift detection algorithms";
                };

                correlation = mkOption {
                  type = types.submodule {
                    options = {
                      enable = mkOption {
                        type = types.bool;
                        default = true;
                        description = "Enable event correlation";
                      };

                      window = mkOption {
                        type = types.str;
                        default = "5m";
                        description = "Correlation time window";
                      };

                      threshold = mkOption {
                        type = types.int;
                        default = 3;
                        description = "Correlation threshold";
                      };
                    };
                  };
                  default = {};
                  description = "Event correlation configuration";
                };
              };
            };
            default = {};
            description = "Drift detection configuration";
          };

          remediation = mkOption {
            type = types.submodule {
              options = {
                automatic = mkOption {
                  type = types.submodule {
                    options = {
                      enable = mkOption {
                        type = types.bool;
                        default = true;
                        description = "Enable automatic remediation";
                      };

                      actions = mkOption {
                        type = types.listOf (types.submodule {
                          options = {
                            trigger = mkOption {
                              type = types.str;
                              description = "Remediation trigger";
                            };

                            action = mkOption {
                              type = types.str;
                              description = "Remediation action";
                            };

                            approval = mkOption {
                              type = types.enum [ "automatic" "manual" ];
                              default = "automatic";
                              description = "Approval required";
                            };
                          };
                        });
                        default = [
                          {
                            trigger = "critical-drift";
                            action = "restore-from-baseline";
                            approval = "automatic";
                          }
                          {
                            trigger = "high-drift";
                            action = "create-ticket";
                            approval = "automatic";
                          }
                          {
                            trigger = "medium-drift";
                            action = "notify-admin";
                            approval = "automatic";
                          }
                        ];
                        description = "Automatic remediation actions";
                      };
                    };
                  };
                  default = {};
                  description = "Automatic remediation configuration";
                };

                manual = mkOption {
                  type = types.submodule {
                    options = {
                      enable = mkOption {
                        type = types.bool;
                        default = true;
                        description = "Enable manual remediation workflows";
                      };

                      workflows = mkOption {
                        type = types.listOf (types.submodule {
                          options = {
                            name = mkOption {
                              type = types.str;
                              description = "Workflow name";
                            };

                            steps = mkOption {
                              type = types.listOf (types.submodule {
                                options = {
                                   type = mkOption {
                                     type = types.str;
                                     description = "Step type";
                                   };
                                 };
                               });
                              description = "Workflow steps";
                            };
                          };
                        });
                        default = [
                          {
                            name = "security-drift";
                            steps = [
                              { type = "isolate-system"; }
                              { type = "notify-security"; }
                              { type = "investigate-change"; }
                              { type = "approve-remediation"; }
                              { type = "apply-remediation"; }
                            ];
                          }
                          {
                            name = "config-drift";
                            steps = [
                              { type = "analyze-change"; }
                              { type = "assess-impact"; }
                              { type = "approve-change"; }
                              { type = "update-baseline"; }
                            ];
                          }
                        ];
                        description = "Manual remediation workflows";
                      };
                    };
                  };
                  default = {};
                  description = "Manual remediation configuration";
                };
              };
            };
            default = {};
            description = "Drift remediation configuration";
          };
        };
      };
      default = {};
      description = "Drift detection and remediation configuration";
    };

    change = mkOption {
      type = types.submodule {
        options = {
          management = mkOption {
            type = types.submodule {
              options = {
                enable = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Enable change management";
                };

                approval = mkOption {
                  type = types.submodule {
                    options = {
                      required = mkOption {
                        type = types.bool;
                        default = true;
                        description = "Require approval for changes";
                      };

                      workflows = mkOption {
                        type = types.listOf (types.submodule {
                          options = {
                            name = mkOption {
                              type = types.str;
                              description = "Workflow name";
                            };

                            approvers = mkOption {
                              type = types.listOf types.str;
                              description = "Required approvers";
                            };

                            timeout = mkOption {
                              type = types.str;
                              default = "24h";
                              description = "Approval timeout";
                            };

                            autoApprove = mkOption {
                              type = types.bool;
                              default = false;
                              description = "Auto-approve changes";
                            };
                          };
                        });
                        default = [
                          {
                            name = "standard-change";
                            approvers = [ "ops-team" ];
                            timeout = "24h";
                            autoApprove = false;
                          }
                          {
                            name = "emergency-change";
                            approvers = [ "ops-manager" ];
                            timeout = "1h";
                            autoApprove = true;
                          }
                          {
                            name = "security-change";
                            approvers = [ "security-team" "ops-team" ];
                            timeout = "48h";
                            autoApprove = false;
                          }
                        ];
                        description = "Approval workflows";
                      };
                    };
                  };
                  default = {};
                  description = "Change approval configuration";
                };

                tracking = mkOption {
                  type = types.submodule {
                    options = {
                      enable = mkOption {
                        type = types.bool;
                        default = true;
                        description = "Enable change tracking";
                      };

                      attributes = mkOption {
                        type = types.listOf types.str;
                        default = [
                          "requester"
                          "timestamp"
                          "reason"
                          "approval"
                          "implementation"
                          "verification"
                        ];
                        description = "Change attributes to track";
                      };

                      retention = mkOption {
                        type = types.str;
                        default = "7y";
                        description = "Change record retention";
                      };
                    };
                  };
                  default = {};
                  description = "Change tracking configuration";
                };
              };
            };
            default = {};
            description = "Change management configuration";
          };

          attribution = mkOption {
            type = types.submodule {
              options = {
                enable = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Enable change attribution";
                };

                methods = mkOption {
                  type = types.listOf types.str;
                  default = [
                    "system-logs"
                    "audit-trails"
                    "session-records"
                    "api-calls"
                  ];
                  description = "Attribution methods";
                };

                correlation = mkOption {
                  type = types.submodule {
                    options = {
                      enable = mkOption {
                        type = types.bool;
                        default = true;
                        description = "Enable attribution correlation";
                      };

                      sources = mkOption {
                        type = types.listOf types.str;
                        default = [ "ssh" "sudo" "systemd" "application" ];
                        description = "Correlation sources";
                      };

                      confidence = mkOption {
                        type = types.float;
                        default = 0.8;
                        description = "Correlation confidence threshold";
                      };
                    };
                  };
                  default = {};
                  description = "Attribution correlation configuration";
                };
              };
            };
            default = {};
            description = "Change attribution configuration";
          };
        };
      };
      default = {};
      description = "Change management configuration";
    };

    analytics = mkOption {
      type = types.submodule {
        options = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Enable drift analytics";
          };

          metrics = mkOption {
            type = types.submodule {
              options = {
                driftFrequency = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Track drift frequency";
                };

                driftSeverity = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Track drift severity distribution";
                };

                remediationSuccess = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Track remediation success rates";
                };

                changeTrends = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Track change trends";
                };
              };
            };
            default = {};
            description = "Analytics metrics configuration";
          };

          reporting = mkOption {
            type = types.submodule {
              options = {
                schedules = mkOption {
                  type = types.listOf (types.submodule {
                    options = {
                      name = mkOption {
                        type = types.str;
                        description = "Report name";
                      };

                      frequency = mkOption {
                        type = types.str;
                        description = "Report frequency";
                      };

                      recipients = mkOption {
                        type = types.listOf types.str;
                        description = "Report recipients";
                      };

                      include = mkOption {
                        type = types.listOf types.str;
                        description = "Report contents";
                      };
                    };
                  });
                  default = [
                    {
                      name = "daily-drift-summary";
                      frequency = "daily";
                      recipients = [ "ops@example.com" ];
                      include = [ "drift-events" "remediation-actions" "trends" ];
                    }
                    {
                      name = "weekly-compliance";
                      frequency = "weekly";
                      recipients = [ "compliance@example.com" ];
                      include = [ "compliance-status" "violations" "recommendations" ];
                    }
                    {
                      name = "monthly-analysis";
                      frequency = "monthly";
                      recipients = [ "management@example.com" ];
                      include = [ "trend-analysis" "risk-assessment" "improvements" ];
                    }
                  ];
                  description = "Reporting schedules";
                };
              };
            };
            default = {};
            description = "Analytics reporting configuration";
          };

          dashboard = mkOption {
            type = types.submodule {
              options = {
                enable = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Enable analytics dashboard";
                };

                panels = mkOption {
                  type = types.listOf (types.submodule {
                    options = {
                      title = mkOption {
                        type = types.str;
                        description = "Panel title";
                      };

                      type = mkOption {
                        type = types.enum [ "timeline" "pie" "gauge" "trend" "table" ];
                        description = "Panel type";
                      };
                    };
                  });
                  default = [
                    { title = "Drift Events"; type = "timeline"; }
                    { title = "Severity Distribution"; type = "pie"; }
                    { title = "Remediation Success"; type = "gauge"; }
                    { title = "Change Trends"; type = "trend"; }
                  ];
                  description = "Dashboard panels";
                };
              };
            };
            default = {};
            description = "Analytics dashboard configuration";
          };
        };
      };
      default = {};
      description = "Analytics and reporting configuration";
    };

    integration = mkOption {
      type = types.submodule {
        options = {
          siem = mkOption {
            type = types.submodule {
              options = {
                enable = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Enable SIEM integration";
                };

                endpoint = mkOption {
                  type = types.str;
                  default = "https://siem.example.com";
                  description = "SIEM endpoint";
                };

                events = mkOption {
                  type = types.listOf types.str;
                  default = [ "drift-detected" "change-made" "remediation-action" ];
                  description = "Events to send to SIEM";
                };
              };
            };
            default = {};
            description = "SIEM integration configuration";
          };

          ticketing = mkOption {
            type = types.submodule {
              options = {
                enable = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Enable ticketing integration";
                };

                system = mkOption {
                  type = types.enum [ "jira" "servicenow" "zendesk" ];
                  default = "jira";
                  description = "Ticketing system";
                };

                endpoint = mkOption {
                  type = types.str;
                  default = "https://company.atlassian.net";
                  description = "Ticketing system endpoint";
                };

                projects = mkOption {
                  type = types.listOf types.str;
                  default = [ "SEC" "OPS" ];
                  description = "Ticketing projects";
                };

                priorities = mkOption {
                  type = types.listOf types.str;
                  default = [ "High" "Medium" "Low" ];
                  description = "Ticket priorities";
                };
              };
            };
            default = {};
            description = "Ticketing system integration";
          };

          compliance = mkOption {
            type = types.submodule {
              options = {
                enable = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Enable compliance integration";
                };

                frameworks = mkOption {
                  type = types.listOf types.str;
                  default = [ "sox" "hipaa" "pci-dss" "iso-27001" ];
                  description = "Compliance frameworks";
                };

                reporting = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Enable compliance reporting";
                };

                audit = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Enable audit logging";
                };

                retention = mkOption {
                  type = types.str;
                  default = "7y";
                  description = "Compliance record retention";
                };
              };
            };
            default = {};
            description = "Compliance integration configuration";
          };
        };
      };
      default = {};
      description = "External system integrations";
    };
  };

  config = mkIf cfg.enable {
    # Install configuration drift detector and scripts
    environment.systemPackages = [
      configDriftService
    ] ++ (map (name: pkgs.writeScriptBin name baselineScripts.${name}) (attrNames baselineScripts)) ++
        (map (name: pkgs.writeScriptBin name driftDetectionScripts.${name}) (attrNames driftDetectionScripts)) ++
        [ (pkgs.writeScriptBin "gateway-drift-monitoring" monitoringScript) ];

    # Create configuration drift directories
    systemd.tmpfiles.rules = [
      "d /var/lib/config-drift 0755 root root -"
      "d /var/lib/config-drift/baselines 0755 root root -"
      "d /var/log/gateway 0755 root root -"
    ];

    # Baseline creation services and timers
    systemd.services = lib.mkMerge [
      {
        "gateway-config-baseline" = {
          description = "Gateway configuration baseline creation";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.writeScript "gateway-config-baseline-script" baselineScripts.daily} daily-baseline";
            User = "root";
            Group = "root";
            PrivateTmp = true;
            ProtectSystem = "strict";
            ReadWritePaths = [ "/var/lib/config-drift" "/var/log/gateway" "/etc" "/var/lib" ];
          };
        };
      }
      (lib.mapAttrs' (scanName: scan:
        nameValuePair "gateway-drift-${scanName}" {
          description = "Gateway configuration drift detection for ${scanName}";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.writeScript "gateway-drift-${scanName}-script" driftDetectionScripts."drift-${scanName}"} /var/lib/config-drift/baselines/baseline_daily-baseline_latest";
            User = "root";
            Group = "root";
            PrivateTmp = true;
            ProtectSystem = "strict";
            ReadWritePaths = [ "/var/lib/config-drift" "/var/log/gateway" "/etc" "/var/lib" "/tmp" ];
          };
        }
      ) (lib.listToAttrs (map (s: { name = s.name; value = s; }) cfg.monitoring.scheduled.scans)))
      {
        "gateway-drift-monitoring" = {
          description = "Gateway real-time configuration drift monitoring";
          serviceConfig = {
            Type = "simple";
            ExecStart = "${pkgs.writeScript "gateway-drift-monitoring-script" monitoringScript}";
            User = "root";
            Group = "root";
            PrivateTmp = true;
            ProtectSystem = "strict";
            ReadWritePaths = [ "/var/lib/config-drift" "/var/log/gateway" "/etc" "/var/lib" ];
            Restart = "always";
            RestartSec = 10;
          };
        };
      }
    ];

    # Prometheus metrics (if enabled)
    services.prometheus.exporters.node = mkIf cfg.analytics.enable {
      enable = true;
      enabledCollectors = [ "systemd" ];
    };

    # Logrotate for configuration drift logs
    services.logrotate = {
      enable = true;
      settings."gateway-drift" = {
        files = "/var/log/gateway/drift-*.log";
        frequency = "weekly";
        rotate = 12;
        compress = true;
        missingok = true;
        notifempty = true;
      };
    };
  };
}

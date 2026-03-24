{
  lib,
  config,
  ...
}:
let
  inherit (lib) mkOption types;
in
{
  options.services.gateway.healthMonitoring = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable gateway health monitoring";
    };

    interval = mkOption {
      type = types.str;
      default = "30s";
      description = "Health check interval";
    };

    waitForNetwork = mkOption {
      type = types.bool;
      default = true;
      description = "Wait for network-online.target before starting health monitoring services";
    };

    timeout = mkOption {
      type = types.str;
      default = "10s";
      description = "Health check timeout";
    };

    levels = mkOption {
      type = types.submodule {
        options = {
          component = mkOption {
            type = types.submodule {
              options = {
                enable = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Enable component-level health checks";
                };
                interval = mkOption {
                  type = types.str;
                  default = "30s";
                  description = "Component health check interval";
                };
                timeout = mkOption {
                  type = types.str;
                  default = "10s";
                  description = "Component health check timeout";
                };
              };
            };
            default = { };
            description = "Component-level health monitoring configuration";
          };

          service = mkOption {
            type = types.submodule {
              options = {
                enable = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Enable service-level health aggregation";
                };
                interval = mkOption {
                  type = types.str;
                  default = "60s";
                  description = "Service health aggregation interval";
                };
                aggregation = mkOption {
                  type = types.enum [
                    "worst-case"
                    "average"
                    "weighted-average"
                  ];
                  default = "weighted-average";
                  description = "How to aggregate component health into service health";
                };
              };
            };
            default = { };
            description = "Service-level health monitoring configuration";
          };

          system = mkOption {
            type = types.submodule {
              options = {
                enable = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Enable system-level health aggregation";
                };
                interval = mkOption {
                  type = types.str;
                  default = "120s";
                  description = "System health aggregation interval";
                };
                aggregation = mkOption {
                  type = types.enum [
                    "worst-case"
                    "average"
                    "weighted-average"
                  ];
                  default = "weighted-average";
                  description = "How to aggregate service health into system health";
                };
              };
            };
            default = { };
            description = "System-level health monitoring configuration";
          };
        };
      };
      default = { };
      description = "Multi-level health monitoring configuration";
    };

    services = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            enable = mkOption {
              type = types.bool;
              default = true;
              description = "Enable health monitoring for this service";
            };

            components = mkOption {
              type = types.listOf types.str;
              description = "Components that belong to this service";
            };

            weight = mkOption {
              type = types.int;
              default = 1;
              description = "Weight of this service in system health calculation";
            };

            critical = mkOption {
              type = types.bool;
              default = false;
              description = "Whether this service is critical for system operation";
            };
          };
        }
      );
      default = {
        network = {
          components = [
            "network-interfaces"
            "routing"
            "firewall"
          ];
          weight = 30;
          critical = true;
        };
        dns = {
          components = [
            "dns-resolution"
            "dns-cache"
            "dns-zones"
          ];
          weight = 25;
          critical = true;
        };
        dhcp = {
          components = [
            "dhcp-server"
            "dhcp-database"
            "dhcp-leases"
          ];
          weight = 20;
          critical = false;
        };
        security = {
          components = [
            "ids"
            "firewall-rules"
            "threat-detection"
          ];
          weight = 15;
          critical = true;
        };
        system = {
          components = [
            "cpu"
            "memory"
            "disk"
            "temperature"
          ];
          weight = 10;
          critical = true;
        };
      };
      description = "Service definitions with component groupings";
    };

    components = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            enable = mkOption {
              type = types.bool;
              default = true;
              description = "Enable health monitoring for this component";
            };

            service = mkOption {
              type = types.str;
              description = "Which service this component belongs to";
            };

            weight = mkOption {
              type = types.int;
              default = 1;
              description = "Weight of this component in service health calculation";
            };

            interval = mkOption {
              type = types.str;
              default = "30s";
              description = "Health check interval for this component";
            };

            timeout = mkOption {
              type = types.str;
              default = "10s";
              description = "Health check timeout for this component";
            };

            checks = mkOption {
              type = types.listOf (
                types.submodule {
                  options = {
                    type = mkOption {
                      type = types.str;
                      description = "Health check type";
                    };

                    # Common fields
                    interval = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                    };
                    timeout = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                    };
                    retries = mkOption {
                      type = types.nullOr types.int;
                      default = null;
                    };

                    # Type-specific fields (add all possible fields here to be permissive)
                    target = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                    };
                    query = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                    };
                    port = mkOption {
                      type = types.nullOr types.int;
                      default = null;
                    };
                    protocol = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                    };
                    host = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                    };
                    zone = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                    };
                    path = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                    };
                    interface = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                    };
                    expectedState = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                    };
                    route = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                    };
                    name = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                    };
                    threshold = mkOption {
                      type = types.nullOr (types.either types.int types.str);
                      default = null;
                      description = "Health check threshold";
                    };
                    percentile = mkOption {
                      type = types.nullOr types.int;
                      default = null;
                      description = "Percentile for latency checks";
                    };
                    window = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                      description = "Time window for rate calculations";
                    };
                  };
                }
              );
              default = [ ];
              description = "List of health checks for this component";
            };

            thresholds = mkOption {
              type = types.attrsOf (
                types.submodule {
                  options = {
                    warning = mkOption {
                      type = types.nullOr (types.either types.int types.str);
                      default = null;
                      description = "Warning threshold";
                    };

                    critical = mkOption {
                      type = types.nullOr (types.either types.int types.str);
                      default = null;
                      description = "Critical threshold";
                    };

                    recovery = mkOption {
                      type = types.nullOr (types.either types.int types.str);
                      default = null;
                      description = "Recovery threshold";
                    };
                  };
                }
              );
              default = { };
              description = "Health thresholds for this component";
            };

            alerts = mkOption {
              type = types.submodule {
                options = {
                  enable = mkOption {
                    type = types.bool;
                    default = true;
                    description = "Enable alerts for this component";
                  };
                };
              };
              default = { };
              description = "Alert configuration for this component";
            };
          };
        }
      );
      default = { };
      description = "Health monitoring components configuration";
    };

    alerts = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            enable = mkOption {
              type = types.bool;
              default = true;
              description = "Enable alerting for this health check";
            };

            channels = mkOption {
              type = types.listOf (
                types.enum [
                  "email"
                  "slack"
                  "webhook"
                  "prometheus"
                ]
              );
              default = [ "email" ];
              description = "Alert channels";
            };

            webhook = mkOption {
              type = types.submodule {
                options = {
                  url = mkOption {
                    type = types.str;
                    description = "Webhook URL";
                  };

                  secret = mkOption {
                    type = types.str;
                    description = "Webhook secret";
                  };

                  timeout = mkOption {
                    type = types.int;
                    default = 10;
                    description = "Webhook timeout in seconds";
                  };
                };
              };
              default = { };
              description = "Webhook configuration";
            };

            email = mkOption {
              type = types.submodule {
                options = {
                  to = mkOption {
                    type = types.str;
                    description = "Email recipient";
                  };

                  from = mkOption {
                    type = types.str;
                    description = "Email sender";
                  };

                  subject = mkOption {
                    type = types.str;
                    description = "Email subject template";
                  };

                  body = mkOption {
                    type = types.str;
                    description = "Email body template";
                  };
                };
              };
              default = { };
              description = "Email configuration";
            };

            prometheus = mkOption {
              type = types.submodule {
                options = {
                  gateway = mkOption {
                    type = types.str;
                    description = "Prometheus gateway URL";
                  };

                  metric = mkOption {
                    type = types.str;
                    description = "Metric name";
                  };

                  labels = mkOption {
                    type = types.attrsOf types.str;
                    default = { };
                    description = "Metric labels";
                  };
                };
              };
              default = { };
              description = "Prometheus configuration";
            };
          };
        }
      );
      default = { };
      description = "Alert configuration";
    };

    dashboard = mkOption {
      type = types.submodule {
        options = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Enable health monitoring dashboard";
          };

          port = mkOption {
            type = types.int;
            default = 8080;
            description = "Dashboard port";
          };

          bindAddress = mkOption {
            type = types.str;
            default = "127.0.0.1";
            description = "Dashboard bind address";
          };
        };
      };
      default = { };
      description = "Health monitoring dashboard configuration";
    };

    analytics = mkOption {
      type = types.submodule {
        options = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Enable health analytics";
          };

          retention = mkOption {
            type = types.str;
            default = "30d";
            description = "Health data retention period";
          };

          aggregation = mkOption {
            type = types.enum [
              "none"
              "avg"
              "max"
              "min"
            ];
            default = "avg";
            description = "Health data aggregation method";
          };

          trends = mkOption {
            type = types.bool;
            default = true;
            description = "Enable trend analysis";
          };
        };
      };
      default = { };
      description = "Health analytics configuration";
    };

    remediation = mkOption {
      type = types.submodule {
        options = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Enable automatic remediation mechanisms";
          };

          escalation = mkOption {
            type = types.submodule {
              options = {
                enable = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Enable escalation procedures";
                };

                levels = mkOption {
                  type = types.attrsOf (
                    types.submodule {
                      options = {
                        timeout = mkOption {
                          type = types.str;
                          description = "Time before escalating to next level";
                        };

                        actions = mkOption {
                          type = types.listOf types.str;
                          description = "Remediation actions for this level";
                        };

                        notify = mkOption {
                          type = types.listOf types.str;
                          default = [ ];
                          description = "Who to notify at this escalation level";
                        };

                        requireApproval = mkOption {
                          type = types.bool;
                          default = false;
                          description = "Require manual approval for actions at this level";
                        };
                      };
                    }
                  );
                  default = {
                    "1" = {
                      timeout = "5m";
                      actions = [
                        "service-restart"
                        "resource-cleanup"
                      ];
                      notify = [ ];
                    };
                    "2" = {
                      timeout = "15m";
                      actions = [
                        "config-rollback"
                        "failover"
                      ];
                      notify = [ "ops-team" ];
                    };
                    "3" = {
                      timeout = "60m";
                      actions = [ "manual-intervention" ];
                      notify = [
                        "on-call"
                        "management"
                      ];
                      requireApproval = true;
                    };
                  };
                  description = "Escalation levels with actions and timeouts";
                };
              };
            };
            default = { };
            description = "Escalation procedures configuration";
          };

          actions = mkOption {
            type = types.attrsOf (
              types.submodule {
                options = {
                  enable = mkOption {
                    type = types.bool;
                    default = true;
                    description = "Enable this remediation action";
                  };

                  type = mkOption {
                    type = types.enum [
                      "service-restart"
                      "service-reload"
                      "config-rollback"
                      "resource-cleanup"
                      "failover"
                      "scale-up"
                      "custom-script"
                    ];
                    description = "Type of remediation action";
                  };

                  maxRetries = mkOption {
                    type = types.int;
                    default = 3;
                    description = "Maximum number of retry attempts";
                  };

                  retryDelay = mkOption {
                    type = types.str;
                    default = "30s";
                    description = "Delay between retry attempts";
                  };

                  backoff = mkOption {
                    type = types.enum [
                      "fixed"
                      "exponential"
                      "linear"
                    ];
                    default = "exponential";
                    description = "Backoff strategy for retries";
                  };

                  timeout = mkOption {
                    type = types.str;
                    default = "5m";
                    description = "Maximum time for action to complete";
                  };

                  validateBeforeAction = mkOption {
                    type = types.bool;
                    default = true;
                    description = "Validate system state before taking action";
                  };

                  rollbackOnFailure = mkOption {
                    type = types.bool;
                    default = true;
                    description = "Attempt rollback if action fails";
                  };

                  services = mkOption {
                    type = types.listOf types.str;
                    default = [ ];
                    description = "Services this action applies to";
                  };

                  script = mkOption {
                    type = types.nullOr types.str;
                    default = null;
                    description = "Custom script for custom-script actions";
                  };

                  parameters = mkOption {
                    type = types.attrsOf types.str;
                    default = { };
                    description = "Parameters for the remediation action";
                  };
                };
              }
            );
            default = {
              "service-restart" = {
                type = "service-restart";
                maxRetries = 3;
                retryDelay = "30s";
                validateBeforeAction = true;
              };

              "service-reload" = {
                type = "service-reload";
                maxRetries = 2;
                retryDelay = "10s";
                validateBeforeAction = true;
              };

              "config-rollback" = {
                type = "config-rollback";
                maxRetries = 1;
                validateBeforeAction = true;
                parameters = {
                  backupRetention = "7d";
                };
              };

              "resource-cleanup" = {
                type = "resource-cleanup";
                maxRetries = 2;
                parameters = {
                  actions = "clear-cache,rotate-logs,restart-services";
                };
              };

              "failover" = {
                type = "failover";
                maxRetries = 1;
                validateBeforeAction = true;
                parameters = {
                  backupInterface = "eth1";
                };
              };
            };
            description = "Available remediation actions";
          };

          triggers = mkOption {
            type = types.attrsOf (
              types.submodule {
                options = {
                  enable = mkOption {
                    type = types.bool;
                    default = true;
                    description = "Enable this remediation trigger";
                  };

                  condition = mkOption {
                    type = types.str;
                    description = "Condition that triggers remediation";
                  };

                  level = mkOption {
                    type = types.enum [
                      "component"
                      "service"
                      "system"
                    ];
                    default = "component";
                    description = "Level at which this trigger applies";
                  };

                  actions = mkOption {
                    type = types.listOf types.str;
                    description = "Actions to take when triggered";
                  };

                  cooldown = mkOption {
                    type = types.str;
                    default = "5m";
                    description = "Cooldown period before trigger can fire again";
                  };

                  priority = mkOption {
                    type = types.int;
                    default = 1;
                    description = "Trigger priority (higher = more important)";
                  };
                };
              }
            );
            default = {
              "service-down" = {
                condition = "component.status == 'critical' && component.service.critical == true";
                level = "component";
                actions = [ "service-restart" ];
                cooldown = "2m";
                priority = 10;
              };

              "high-resource-usage" = {
                condition = "component.metrics.cpu > 90 || component.metrics.memory > 90";
                level = "component";
                actions = [ "resource-cleanup" ];
                cooldown = "10m";
                priority = 5;
              };

              "config-error" = {
                condition = "component.checks.config.status == 'failed'";
                level = "component";
                actions = [ "config-rollback" ];
                cooldown = "5m";
                priority = 8;
              };

              "interface-failure" = {
                condition = "component.type == 'network-interface' && component.status == 'critical'";
                level = "component";
                actions = [ "failover" ];
                cooldown = "1m";
                priority = 9;
              };
            };
            description = "Remediation triggers and their conditions";
          };
        };
      };
      default = { };
      description = "Automatic remediation configuration";
    };

    scoring = mkOption {
      type = types.submodule {
        options = {
          component = mkOption {
            type = types.submodule {
              options = {
                aggregation = mkOption {
                  type = types.enum [
                    "worst-case"
                    "average"
                    "weighted-average"
                  ];
                  default = "weighted-average";
                  description = "How to aggregate check results into component health";
                };
                thresholds = mkOption {
                  type = types.attrsOf types.int;
                  default = {
                    excellent = 95;
                    good = 85;
                    warning = 70;
                    critical = 50;
                  };
                  description = "Component health score status thresholds";
                };
              };
            };
            default = { };
            description = "Component-level scoring configuration";
          };

          service = mkOption {
            type = types.submodule {
              options = {
                aggregation = mkOption {
                  type = types.enum [
                    "worst-case"
                    "average"
                    "weighted-average"
                  ];
                  default = "weighted-average";
                  description = "How to aggregate component health into service health";
                };
                thresholds = mkOption {
                  type = types.attrsOf types.int;
                  default = {
                    excellent = 95;
                    good = 85;
                    warning = 70;
                    critical = 50;
                  };
                  description = "Service health score status thresholds";
                };
              };
            };
            default = { };
            description = "Service-level scoring configuration";
          };

          system = mkOption {
            type = types.submodule {
              options = {
                aggregation = mkOption {
                  type = types.enum [
                    "worst-case"
                    "average"
                    "weighted-average"
                  ];
                  default = "weighted-average";
                  description = "How to aggregate service health into system health";
                };
                thresholds = mkOption {
                  type = types.attrsOf types.int;
                  default = {
                    excellent = 95;
                    good = 85;
                    warning = 70;
                    critical = 50;
                  };
                  description = "System health score status thresholds";
                };
              };
            };
            default = { };
            description = "System-level scoring configuration";
          };
        };
      };
      default = { };
      description = "Multi-level health scoring configuration";
    };

    prediction = mkOption {
      type = types.submodule {
        options = {
          enable = mkOption {
            type = types.bool;
            default = false;
            description = "Enable predictive health analytics";
          };

          dataRetention = mkOption {
            type = types.str;
            default = "90d";
            description = "How long to retain historical health data for predictions";
          };

          models = mkOption {
            type = types.attrsOf (
              types.submodule {
                options = {
                  enable = mkOption {
                    type = types.bool;
                    default = true;
                    description = "Enable this prediction model";
                  };

                  algorithm = mkOption {
                    type = types.enum [
                      "linear-regression"
                      "random-forest"
                      "time-series"
                      "neural-network"
                      "svm"
                    ];
                    default = "linear-regression";
                    description = "Prediction algorithm";
                  };

                  target = mkOption {
                    type = types.enum [
                      "performance"
                      "failure"
                      "capacity"
                      "anomaly"
                    ];
                    description = "What to predict";
                  };

                  trainingWindow = mkOption {
                    type = types.str;
                    default = "7d";
                    description = "Data window for training";
                  };

                  predictionHorizon = mkOption {
                    type = types.str;
                    default = "24h";
                    description = "How far ahead to predict";
                  };

                  features = mkOption {
                    type = types.listOf types.str;
                    default = [ ];
                    description = "Features to use for prediction";
                  };

                  confidence = mkOption {
                    type = types.submodule {
                      options = {
                        threshold = mkOption {
                          type = types.float;
                          default = 0.8;
                          description = "Minimum confidence threshold for alerts";
                        };
                        method = mkOption {
                          type = types.enum [
                            "bootstrap"
                            "cross-validation"
                            "analytical"
                          ];
                          default = "bootstrap";
                          description = "Confidence calculation method";
                        };
                      };
                    };
                    default = { };
                    description = "Confidence scoring configuration";
                  };

                  alerts = mkOption {
                    type = types.attrsOf (
                      types.submodule {
                        options = {
                          threshold = mkOption {
                            type = types.float;
                            description = "Alert threshold";
                          };
                          severity = mkOption {
                            type = types.enum [
                              "info"
                              "warning"
                              "critical"
                            ];
                            default = "warning";
                            description = "Alert severity";
                          };
                          horizon = mkOption {
                            type = types.str;
                            description = "Prediction horizon for this alert";
                          };
                        };
                      }
                    );
                    default = { };
                    description = "Prediction-based alerts";
                  };
                };
              }
            );
            default = {
              performance = {
                target = "performance";
                algorithm = "linear-regression";
                trainingWindow = "7d";
                predictionHorizon = "24h";
                features = [
                  "cpu"
                  "memory"
                  "network-throughput"
                  "response-time"
                ];
                alerts = {
                  degradation = {
                    threshold = 0.2;
                    severity = "warning";
                    horizon = "6h";
                  };
                };
              };

              failure = {
                target = "failure";
                algorithm = "random-forest";
                trainingWindow = "30d";
                predictionHorizon = "6h";
                features = [
                  "error-rate"
                  "latency"
                  "resource-utilization"
                  "failure-history"
                ];
                alerts = {
                  risk = {
                    threshold = 0.7;
                    severity = "critical";
                    horizon = "24h";
                  };
                };
              };

              capacity = {
                target = "capacity";
                algorithm = "time-series";
                trainingWindow = "90d";
                predictionHorizon = "30d";
                features = [
                  "growth-rate"
                  "seasonal-patterns"
                  "resource-usage"
                ];
                alerts = {
                  exhaustion = {
                    threshold = 0.8;
                    severity = "warning";
                    horizon = "7d";
                  };
                };
              };
            };
            description = "Prediction models configuration";
          };

          anomaly = mkOption {
            type = types.submodule {
              options = {
                enable = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Enable anomaly detection";
                };

                algorithm = mkOption {
                  type = types.enum [
                    "isolation-forest"
                    "one-class-svm"
                    "autoencoder"
                    "statistical"
                  ];
                  default = "statistical";
                  description = "Anomaly detection algorithm";
                };

                sensitivity = mkOption {
                  type = types.float;
                  default = 0.95;
                  description = "Anomaly detection sensitivity (higher = fewer false positives)";
                };

                trainingWindow = mkOption {
                  type = types.str;
                  default = "7d";
                  description = "Training window for anomaly detection";
                };
              };
            };
            default = { };
            description = "Anomaly detection configuration";
          };
        };
      };
      default = { };
      description = "Predictive analytics configuration";
    };
  };
}

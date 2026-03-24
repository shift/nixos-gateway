{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.gateway.disasterRecovery;
  failoverManager = import ../lib/failover-manager.nix { inherit lib; };

  # Generate health check scripts for each site
  healthCheckScripts = lib.mapAttrs' (siteName: site:
    nameValuePair "health-check-${siteName}" (failoverManager.utils.generateHealthCheckScript siteName site.health)
  ) cfg.sites;

  # Generate failover scripts
  failoverScripts = lib.mapAttrs' (procedureName: procedure:
    nameValuePair "failover-${procedureName}" (failoverManager.utils.generateFailoverScript procedure cfg)
  ) (lib.listToAttrs (map (p: { name = p.name; value = p; }) cfg.failover.procedures));

  # Generate recovery scripts
  recoveryScripts = lib.mapAttrs' (procedureName: procedure:
    nameValuePair "recovery-${procedureName}" (failoverManager.utils.generateRecoveryScript procedure cfg)
  ) (lib.listToAttrs (map (p: { name = p.name; value = p; }) cfg.recovery.procedures));

  # Python disaster recovery manager service
  disasterRecoveryService = pkgs.writeScriptBin "gateway-dr" ''
    #!${pkgs.python3.withPackages (ps: [ ps.requests ])}/bin/python3
    ${failoverManager.failoverUtils}
  '';

in
{
  options.services.gateway.disasterRecovery = {
    enable = mkEnableOption "Disaster Recovery and Failover";

    objectives = mkOption {
      type = types.submodule {
        options = {
          rto = mkOption {
            type = types.attrsOf types.str;
            default = {
              critical = "15m";
              important = "1h";
              normal = "4h";
            };
            description = "Recovery Time Objectives by priority";
          };

          rpo = mkOption {
            type = types.attrsOf types.str;
            default = {
              critical = "5m";
              important = "15m";
              normal = "1h";
            };
            description = "Recovery Point Objectives by priority";
          };

          availability = mkOption {
            type = types.submodule {
              options = {
                target = mkOption {
                  type = types.str;
                  default = "99.9%";
                  description = "Target availability percentage";
                };

                measurement = mkOption {
                  type = types.str;
                  default = "monthly";
                  description = "Availability measurement period";
                };
              };
            };
            default = {};
            description = "Availability objectives";
          };
        };
      };
      default = {};
      description = "Disaster recovery objectives";
    };

    sites = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Site name";
          };

          location = mkOption {
            type = types.str;
            description = "Site location";
          };

          role = mkOption {
            type = types.enum [ "primary" "secondary" "backup" ];
            description = "Site role";
          };

          services = mkOption {
            type = types.listOf types.str;
            default = [
              "dns"
              "dhcp"
              "firewall"
              "ids"
              "monitoring"
            ];
            description = "Services running at this site";
          };

          health = mkOption {
            type = types.submodule {
              options = {
                checks = mkOption {
                  type = types.listOf (types.submodule {
                    options = {
                      type = mkOption {
                        type = types.enum [ "interface" "service" "connectivity" ];
                        description = "Health check type";
                      };

                      interface = mkOption {
                        type = types.nullOr types.str;
                        default = null;
                        description = "Network interface to check";
                      };

                      service = mkOption {
                        type = types.nullOr types.str;
                        default = null;
                        description = "Service to check";
                      };

                      target = mkOption {
                        type = types.nullOr types.str;
                        default = null;
                        description = "Connectivity target";
                      };
                    };
                  });
                  description = "Health checks for this site";
                };

                interval = mkOption {
                  type = types.str;
                  default = "30s";
                  description = "Health check interval";
                };

                threshold = mkOption {
                  type = types.int;
                  default = 3;
                  description = "Failure threshold";
                };
              };
            };
            description = "Health monitoring configuration";
          };

          synchronization = mkOption {
            type = types.nullOr (types.submodule {
              options = {
                enable = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Enable data synchronization";
                };

                type = mkOption {
                  type = types.enum [ "real-time" "periodic" "manual" ];
                  default = "real-time";
                  description = "Synchronization type";
                };

                sources = mkOption {
                  type = types.listOf types.str;
                  default = [ "configuration" "databases" "certificates" ];
                  description = "Data sources to synchronize";
                };

                methods = mkOption {
                  type = types.listOf (types.submodule {
                    options = {
                      type = mkOption {
                        type = types.enum [ "rsync" "database-replication" "file-sync" ];
                        description = "Synchronization method";
                      };

                      interval = mkOption {
                        type = types.nullOr types.str;
                        default = null;
                        description = "Synchronization interval";
                      };
                    };
                  });
                  description = "Synchronization methods";
                };
              };
            });
            default = null;
            description = "Data synchronization configuration";
          };
        };
      });
      default = {
        primary = {
          name = "datacenter-1";
          location = "us-west-2";
          role = "primary";

          services = [
            "dns"
            "dhcp"
            "firewall"
            "ids"
            "monitoring"
          ];

          health = {
            checks = [
              { type = "interface"; interface = "eth0"; }
              { type = "service"; service = "knot"; }
              { type = "service"; service = "kea-dhcp4-server"; }
              { type = "connectivity"; target = "8.8.8.8"; }
            ];
            interval = "30s";
            threshold = 3;
          };
        };

        secondary = {
          name = "datacenter-2";
          location = "us-east-1";
          role = "secondary";

          services = [
            "dns"
            "dhcp"
            "firewall"
            "ids"
            "monitoring"
          ];

          synchronization = {
            enable = true;
            type = "real-time";
            sources = [ "configuration" "databases" "certificates" ];

            methods = [
              { type = "rsync"; interval = "5m"; }
              { type = "database-replication"; }
            ];
          };

          health = {
            checks = [
              { type = "interface"; interface = "eth0"; }
              { type = "service"; service = "knot"; }
              { type = "service"; service = "kea-dhcp4-server"; }
            ];
            interval = "30s";
            threshold = 3;
          };
        };
      };
      description = "Site configurations";
    };

    failover = mkOption {
      type = types.submodule {
        options = {
          triggers = mkOption {
            type = types.listOf (types.submodule {
              options = {
                name = mkOption {
                  type = types.str;
                  description = "Trigger name";
                };

                condition = mkOption {
                  type = types.str;
                  description = "Trigger condition";
                };

                duration = mkOption {
                  type = types.str;
                  default = "5m";
                  description = "Condition duration before trigger";
                };

                action = mkOption {
                  type = types.str;
                  description = "Action to take";
                };

                priority = mkOption {
                  type = types.enum [ "low" "medium" "high" "critical" ];
                  default = "medium";
                  description = "Trigger priority";
                };
              };
            });
            default = [
              {
                name = "site-failure";
                condition = "site.health.checks.failed >= threshold";
                duration = "2m";
                action = "initiate-failover";
                priority = "critical";
              }
              {
                name = "service-failure";
                condition = "service.health.failed >= threshold";
                duration = "5m";
                action = "service-failover";
                priority = "high";
              }
              {
                name = "manual-failover";
                condition = "manual.trigger";
                action = "initiate-failover";
                priority = "medium";
              }
            ];
            description = "Failover triggers";
          };

          procedures = mkOption {
            type = types.listOf (types.submodule {
              options = {
                name = mkOption {
                  type = types.str;
                  description = "Procedure name";
                };

                type = mkOption {
                  type = types.enum [ "site" "service" ];
                  description = "Failover type";
                };

                source = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = "Source site/service";
                };

                target = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = "Target site/service";
                };

                steps = mkOption {
                  type = types.listOf (types.submodule {
                    options = {
                      type = mkOption {
                        type = types.enum [
                          "validate-target"
                          "synchronize-data"
                          "update-dns"
                          "redirect-traffic"
                          "verify-services"
                          "notify-stakeholders"
                          "stop-service"
                          "start-service"
                          "update-configuration"
                          "verify-functionality"
                          "update-monitoring"
                        ];
                        description = "Step type";
                      };
                    };
                  });
                  description = "Failover steps";
                };

                rollback = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Enable rollback on failure";
                };

                timeout = mkOption {
                  type = types.str;
                  default = "15m";
                  description = "Failover timeout";
                };
              };
            });
            default = [
              {
                name = "site-failover";
                type = "site";
                source = "primary";
                target = "secondary";

                steps = [
                  { type = "validate-target"; }
                  { type = "synchronize-data"; }
                  { type = "update-dns"; }
                  { type = "redirect-traffic"; }
                  { type = "verify-services"; }
                  { type = "notify-stakeholders"; }
                ];

                rollback = true;
                timeout = "15m";
              }
              {
                name = "service-failover";
                type = "service";

                steps = [
                  { type = "stop-service"; }
                  { type = "start-service"; }
                  { type = "update-configuration"; }
                  { type = "verify-functionality"; }
                  { type = "update-monitoring"; }
                ];

                rollback = true;
                timeout = "5m";
              }
            ];
            description = "Failover procedures";
          };

          dns = mkOption {
            type = types.submodule {
              options = {
                enable = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Enable DNS failover";
                };

                provider = mkOption {
                  type = types.enum [ "route53" "cloudflare" "manual" ];
                  default = "route53";
                  description = "DNS provider";
                };

                zone = mkOption {
                  type = types.str;
                  default = "example.com";
                  description = "DNS zone";
                };

                records = mkOption {
                  type = types.listOf (types.submodule {
                    options = {
                      name = mkOption {
                        type = types.str;
                        description = "Record name";
                      };

                      type = mkOption {
                        type = types.str;
                        default = "A";
                        description = "Record type";
                      };

                      ttl = mkOption {
                        type = types.int;
                        default = 60;
                        description = "TTL";
                      };

                      healthCheck = mkOption {
                        type = types.bool;
                        default = true;
                        description = "Enable health checks";
                      };

                      values = mkOption {
                        type = types.listOf (types.submodule {
                          options = {
                            ip = mkOption {
                              type = types.str;
                              description = "IP address";
                            };

                            site = mkOption {
                              type = types.str;
                              description = "Site name";
                            };

                            weight = mkOption {
                              type = types.int;
                              default = 100;
                              description = "Weight";
                            };
                          };
                        });
                        description = "Record values";
                      };
                    };
                  });
                  description = "DNS records";
                };

                failover = mkOption {
                  type = types.submodule {
                    options = {
                      primary = mkOption {
                        type = types.submodule {
                          options = {
                            ip = mkOption {
                              type = types.str;
                              description = "Primary IP";
                            };

                            weight = mkOption {
                              type = types.int;
                              default = 100;
                              description = "Primary weight";
                            };
                          };
                        };
                        description = "Primary site configuration";
                      };

                      secondary = mkOption {
                        type = types.submodule {
                          options = {
                            ip = mkOption {
                              type = types.str;
                              description = "Secondary IP";
                            };

                            weight = mkOption {
                              type = types.int;
                              default = 0;
                              description = "Secondary weight";
                            };
                          };
                        };
                        description = "Secondary site configuration";
                      };

                      healthCheck = mkOption {
                        type = types.submodule {
                          options = {
                            path = mkOption {
                              type = types.str;
                              default = "/health";
                              description = "Health check path";
                            };

                            port = mkOption {
                              type = types.int;
                              default = 80;
                              description = "Health check port";
                            };

                            interval = mkOption {
                              type = types.str;
                              default = "30s";
                              description = "Health check interval";
                            };

                            timeout = mkOption {
                              type = types.str;
                              default = "5s";
                              description = "Health check timeout";
                            };
                          };
                        };
                        default = {};
                        description = "Health check configuration";
                      };
                    };
                  };
                  default = {};
                  description = "DNS failover configuration";
                };
              };
            };
            default = {};
            description = "DNS failover configuration";
          };

          traffic = mkOption {
            type = types.submodule {
              options = {
                enable = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Enable traffic redirection";
                };

                methods = mkOption {
                  type = types.listOf (types.submodule {
                    options = {
                      type = mkOption {
                        type = types.enum [ "bgp" "anycast" "dns" ];
                        description = "Traffic redirection method";
                      };

                      as = mkOption {
                        type = types.nullOr types.int;
                        default = null;
                        description = "BGP AS number";
                      };

                      prefix = mkOption {
                        type = types.nullOr types.str;
                        default = null;
                        description = "IP prefix for anycast";
                      };

                      ttl = mkOption {
                        type = types.nullOr types.int;
                        default = null;
                        description = "DNS TTL";
                      };
                    };
                  });
                  default = [
                    { type = "bgp"; as = 65001; }
                    { type = "anycast"; prefix = "192.0.2.0/24"; }
                    { type = "dns"; ttl = 60; }
                  ];
                  description = "Traffic redirection methods";
                };

                redirection = mkOption {
                  type = types.submodule {
                    options = {
                      enable = mkOption {
                        type = types.bool;
                        default = true;
                        description = "Enable traffic redirection";
                      };

                      method = mkOption {
                        type = types.str;
                        default = "bgp-med";
                        description = "Redirection method";
                      };

                      paths = mkOption {
                        type = types.attrsOf (types.submodule {
                          options = {
                            med = mkOption {
                              type = types.int;
                              description = "BGP MED value";
                            };
                          };
                        });
                        default = {
                          primary = { med = 100; };
                          secondary = { med = 200; };
                        };
                        description = "Traffic paths";
                      };
                    };
                  };
                  default = {};
                  description = "Traffic redirection configuration";
                };
              };
            };
            default = {};
            description = "Traffic redirection configuration";
          };
        };
      };
      default = {};
      description = "Failover configuration";
    };

    recovery = mkOption {
      type = types.submodule {
        options = {
          procedures = mkOption {
            type = types.listOf (types.submodule {
              options = {
                name = mkOption {
                  type = types.str;
                  description = "Procedure name";
                };

                type = mkOption {
                  type = types.enum [ "system" "service" ];
                  description = "Recovery type";
                };

                steps = mkOption {
                  type = types.listOf (types.submodule {
                    options = {
                      type = mkOption {
                        type = types.enum [
                          "hardware-prepare"
                          "os-install"
                          "network-configure"
                          "backup-restore"
                          "service-start"
                          "verification"
                          "service-stop"
                          "config-restore"
                          "data-restore"
                          "functionality-test"
                        ];
                        description = "Step type";
                      };
                    };
                  });
                  description = "Recovery steps";
                };

                estimatedTime = mkOption {
                  type = types.str;
                  description = "Estimated recovery time";
                };

                dependencies = mkOption {
                  type = types.listOf types.str;
                  default = [];
                  description = "Recovery dependencies";
                };
              };
            });
            default = [
              {
                name = "bare-metal-recovery";
                type = "system";

                steps = [
                  { type = "hardware-prepare"; }
                  { type = "os-install"; }
                  { type = "network-configure"; }
                  { type = "backup-restore"; }
                  { type = "service-start"; }
                  { type = "verification"; }
                ];

                estimatedTime = "2h";
                dependencies = [ "backup-system" "hardware" ];
              }
              {
                name = "service-recovery";
                type = "service";

                steps = [
                  { type = "service-stop"; }
                  { type = "config-restore"; }
                  { type = "data-restore"; }
                  { type = "service-start"; }
                  { type = "functionality-test"; }
                ];

                estimatedTime = "15m";
                dependencies = [ "backup-system" ];
              }
            ];
            description = "Recovery procedures";
          };

          testing = mkOption {
            type = types.submodule {
              options = {
                enable = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Enable recovery testing";
                };

                schedule = mkOption {
                  type = types.str;
                  default = "monthly";
                  description = "Testing schedule";
                };

                type = mkOption {
                  type = types.enum [ "simulation" "actual" ];
                  default = "simulation";
                  description = "Testing type";
                };

                scenarios = mkOption {
                  type = types.listOf (types.submodule {
                    options = {
                      name = mkOption {
                        type = types.str;
                        description = "Scenario name";
                      };

                      simulation = mkOption {
                        type = types.str;
                        description = "Simulation type";
                      };

                      duration = mkOption {
                        type = types.str;
                        description = "Test duration";
                      };

                      expectedRTO = mkOption {
                        type = types.str;
                        description = "Expected RTO";
                      };
                    };
                  });
                  default = [
                    {
                      name = "site-failure";
                      simulation = "network-isolation";
                      duration = "30m";
                      expectedRTO = "15m";
                    }
                    {
                      name = "service-failure";
                      simulation = "service-crash";
                      duration = "10m";
                      expectedRTO = "5m";
                    }
                    {
                      name = "data-corruption";
                      simulation = "database-corruption";
                      duration = "20m";
                      expectedRTO = "30m";
                    }
                  ];
                  description = "Test scenarios";
                };
              };
            };
            default = {};
            description = "Recovery testing configuration";
          };
        };
      };
      default = {};
      description = "Recovery configuration";
    };

    monitoring = mkOption {
      type = types.submodule {
        options = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Enable disaster recovery monitoring";
          };

          alerts = mkOption {
            type = types.attrsOf (types.submodule {
              options = {
                severity = mkOption {
                  type = types.enum [ "low" "medium" "high" "critical" ];
                  description = "Alert severity";
                };

                enabled = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Enable this alert";
                };
              };
            });
            default = {
              siteFailure = { severity = "critical"; };
              failoverFailure = { severity = "critical"; };
              recoveryFailure = { severity = "high"; };
              rtoExceeded = { severity = "high"; };
              rpoExceeded = { severity = "medium"; };
            };
            description = "Alert configurations";
          };

          metrics = mkOption {
            type = types.submodule {
              options = {
                siteHealth = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Track site health";
                };

                failoverTime = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Track failover duration";
                };

                recoveryTime = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Track recovery duration";
                };

                availability = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Track availability metrics";
                };
              };
            };
            default = {};
            description = "Monitoring metrics";
          };
        };
      };
      default = {};
      description = "Monitoring and alerting configuration";
    };

    communication = mkOption {
      type = types.submodule {
        options = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Enable communication procedures";
          };

          procedures = mkOption {
            type = types.listOf (types.submodule {
              options = {
                name = mkOption {
                  type = types.str;
                  description = "Procedure name";
                };

                trigger = mkOption {
                  type = types.str;
                  description = "Trigger event";
                };

                channels = mkOption {
                  type = types.listOf (types.submodule {
                    options = {
                      type = mkOption {
                        type = types.enum [ "email" "slack" "sms" "webhook" ];
                        description = "Communication channel";
                      };

                      recipients = mkOption {
                        type = types.nullOr (types.listOf types.str);
                        default = null;
                        description = "Email/SMS recipients";
                      };

                      webhook = mkOption {
                        type = types.nullOr types.str;
                        default = null;
                        description = "Webhook URL";
                      };

                      channel = mkOption {
                        type = types.nullOr types.str;
                        default = null;
                        description = "Slack channel";
                      };
                    };
                  });
                  description = "Communication channels";
                };

                template = mkOption {
                  type = types.str;
                  description = "Message template";
                };

                priority = mkOption {
                  type = types.enum [ "low" "medium" "high" "critical" ];
                  default = "medium";
                  description = "Message priority";
                };
              };
            });
            default = [
              {
                name = "incident-notification";
                trigger = "disaster-declared";

                channels = [
                  { type = "email"; recipients = [ "ops@example.com" ]; }
                  { type = "slack"; channel = "#incidents"; }
                  { type = "sms"; recipients = [ "+15551234567" ]; }
                ];

                template = "disaster-notification";
                priority = "high";
              }
              {
                name = "status-updates";
                trigger = "recovery-progress";

                channels = [
                  { type = "slack"; channel = "#incidents"; }
                  { type = "web"; webhook = "https://status.example.com/webhook"; }
                ];

                template = "status-update";
              }
            ];
            description = "Communication procedures";
          };

          stakeholders = mkOption {
            type = types.listOf (types.submodule {
              options = {
                name = mkOption {
                  type = types.str;
                  description = "Stakeholder group name";
                };

                role = mkOption {
                  type = types.enum [ "responder" "observer" "affected" ];
                  description = "Stakeholder role";
                };

                notifications = mkOption {
                  type = types.listOf types.str;
                  description = "Notification events";
                };

                contact = mkOption {
                  type = types.listOf types.str;
                  description = "Contact methods";
                };
              };
            });
            default = [
              {
                name = "operations-team";
                role = "responder";
                notifications = [ "incident" "progress" "resolution" ];
                contact = [ "email" "slack" "sms" ];
              }
              {
                name = "management";
                role = "observer";
                notifications = [ "incident" "resolution" ];
                contact = [ "email" "slack" ];
              }
              {
                name = "customers";
                role = "affected";
                notifications = [ "resolution" ];
                contact = [ "email" "web" ];
              }
            ];
            description = "Stakeholder definitions";
          };
        };
      };
      default = {};
      description = "Communication configuration";
    };

    documentation = mkOption {
      type = types.submodule {
        options = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Enable documentation procedures";
          };

          procedures = mkOption {
            type = types.listOf (types.submodule {
              options = {
                name = mkOption {
                  type = types.str;
                  description = "Document name";
                };

                type = mkOption {
                  type = types.enum [ "runbook" "reference" "checklist" ];
                  description = "Document type";
                };

                location = mkOption {
                  type = types.str;
                  description = "Document location";
                };

                update = mkOption {
                  type = types.str;
                  description = "Update frequency";
                };

                approval = mkOption {
                  type = types.str;
                  description = "Approval required from";
                };
              };
            });
            default = [
              {
                name = "disaster-recovery-plan";
                type = "runbook";
                location = "/docs/dr-plan.md";
                update = "quarterly";
                approval = "management";
              }
              {
                name = "contact-list";
                type = "reference";
                location = "/docs/contacts.md";
                update = "monthly";
                approval = "hr";
              }
              {
                name = "recovery-checklist";
                type = "checklist";
                location = "/docs/recovery-checklist.md";
                update = "monthly";
                approval = "ops";
              }
            ];
            description = "Documentation procedures";
          };

          training = mkOption {
            type = types.submodule {
              options = {
                enable = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Enable training procedures";
                };

                schedule = mkOption {
                  type = types.str;
                  default = "quarterly";
                  description = "Training schedule";
                };

                participants = mkOption {
                  type = types.listOf types.str;
                  default = [ "ops-team" "management" ];
                  description = "Training participants";
                };

                scenarios = mkOption {
                  type = types.listOf types.str;
                  default = [
                    "site-failure"
                    "service-failure"
                    "data-loss"
                  ];
                  description = "Training scenarios";
                };

                certification = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Require certification";
                };
              };
            };
            default = {};
            description = "Training configuration";
          };
        };
      };
      default = {};
      description = "Documentation and training configuration";
    };
  };

  config = mkIf cfg.enable {
    # Install disaster recovery manager and scripts
    environment.systemPackages = [
      disasterRecoveryService
    ] ++ (map (name: pkgs.writeScriptBin name healthCheckScripts.${name}) (attrNames healthCheckScripts)) ++
        (map (name: pkgs.writeScriptBin name failoverScripts.${name}) (attrNames failoverScripts)) ++
        (map (name: pkgs.writeScriptBin name recoveryScripts.${name}) (attrNames recoveryScripts));

    # Create disaster recovery directories
    systemd.tmpfiles.rules = [
      "d /var/log/gateway 0755 root root -"
      "d /docs 0755 root root -"
    ];

    # Health check services and timers for each site
    systemd.services = lib.mkMerge [
      (lib.mapAttrs' (siteName: site:
        nameValuePair "gateway-dr-health-${siteName}" {
          description = "Disaster recovery health check for ${siteName}";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.writeScript "gateway-dr-health-${siteName}-script" healthCheckScripts."health-check-${siteName}"}";
            User = "root";
            Group = "root";
            PrivateTmp = true;
            ProtectSystem = "strict";
            ReadWritePaths = [ "/var/log/gateway" ];
          };
        }
      ) cfg.sites)
      (lib.mapAttrs' (procedureName: procedure:
        nameValuePair "gateway-dr-failover-${procedureName}" {
          description = "Disaster recovery failover for ${procedureName}";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.writeScript "gateway-dr-failover-${procedureName}-script" failoverScripts."failover-${procedureName}"}";
            User = "root";
            Group = "root";
            PrivateTmp = true;
            ProtectSystem = "strict";
            ReadWritePaths = [ "/var/log/gateway" "/etc" "/var/lib" ];
          };
        }
      ) (lib.listToAttrs (map (p: { name = p.name; value = p; }) cfg.failover.procedures)))
      (lib.mapAttrs' (procedureName: procedure:
        nameValuePair "gateway-dr-recovery-${procedureName}" {
          description = "Disaster recovery procedure for ${procedureName}";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.writeScript "gateway-dr-recovery-${procedureName}-script" recoveryScripts."recovery-${procedureName}"}";
            User = "root";
            Group = "root";
            PrivateTmp = true;
            ProtectSystem = "strict";
            ReadWritePaths = [ "/var/log/gateway" "/etc" "/var/lib" "/tmp" ];
          };
        }
      ) (lib.listToAttrs (map (p: { name = p.name; value = p; }) cfg.recovery.procedures)))
    ];

    systemd.timers = lib.mapAttrs' (siteName: site:
      nameValuePair "gateway-dr-health-${siteName}" {
        description = "Timer for disaster recovery health check ${siteName}";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = site.health.interval or "*:0/5";  # Every 5 minutes by default
          Persistent = true;
        };
      }
    ) cfg.sites;

    # Prometheus metrics (if enabled)
    services.prometheus.exporters.node = mkIf cfg.monitoring.enable {
      enable = true;
      enabledCollectors = [ "systemd" ];
    };

    # Logrotate for disaster recovery logs
    services.logrotate = {
      enable = true;
      settings."gateway-dr" = {
        files = "/var/log/gateway/*.log";
        frequency = "weekly";
        rotate = 12;
        compress = true;
        missingok = true;
        notifempty = true;
      };
    };
  };
}

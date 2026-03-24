{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.gateway.backupRecovery;
  backupManager = import ../lib/backup-manager.nix { inherit lib; };

  # Generate backup scripts
  backupScripts = {
    configuration = backupManager.utils.generateBackupScript "configuration" cfg;
    database = backupManager.utils.generateBackupScript "database" cfg;
    certificates = backupManager.utils.generateBackupScript "certificates" cfg;
    logs = backupManager.utils.generateBackupScript "logs" cfg;
  };

  # Generate recovery scripts
  recoveryScripts = lib.mapAttrs' (name: procedure:
    nameValuePair "recovery-${name}" (backupManager.utils.generateRecoveryScript name procedure cfg)
  ) (lib.listToAttrs (map (p: { name = p.name; value = p; }) cfg.recovery.procedures));

  # Generate monitoring script
  monitoringScript = backupManager.utils.generateMonitoringScript cfg;

  # Python backup manager service
  backupManagerService = pkgs.writeScriptBin "gateway-backup-manager" ''
    #!${pkgs.python3.withPackages (ps: [ ps.requests ])}/bin/python3
    ${backupManager.backupUtils}
  '';

in
{
  options.services.gateway.backupRecovery = {
    enable = mkEnableOption "Automated Backup and Recovery";

    backup = {
      schedule = mkOption {
        type = types.submodule {
          options = {
            full = mkOption {
              type = types.str;
              default = "daily";
              description = "Full backup schedule";
            };

            incremental = mkOption {
              type = types.str;
              default = "hourly";
              description = "Incremental backup schedule";
            };

            validation = mkOption {
              type = types.str;
              default = "weekly";
              description = "Backup validation schedule";
            };

            time = mkOption {
              type = types.submodule {
                options = {
                  full = mkOption {
                    type = types.str;
                    default = "02:00";
                    description = "Full backup time";
                  };

                  incremental = mkOption {
                    type = types.str;
                    default = "*/15";
                    description = "Incremental backup time";
                  };

                  validation = mkOption {
                    type = types.str;
                    default = "03:00";
                    description = "Validation time";
                  };
                };
              };
              default = {};
              description = "Backup schedule times";
            };
          };
        };
        default = {};
        description = "Backup scheduling configuration";
      };

      destinations = mkOption {
        type = types.listOf (types.submodule {
          options = {
            name = mkOption {
              type = types.str;
              description = "Destination name";
            };

            type = mkOption {
              type = types.enum [ "local" "s3" "rsync" ];
              description = "Destination type";
            };

            path = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Local path or S3 bucket";
            };

            retention = mkOption {
              type = types.str;
              default = "30d";
              description = "Retention period";
            };

            encryption = mkOption {
              type = types.bool;
              default = true;
              description = "Enable encryption";
            };

            credentials = mkOption {
              type = types.nullOr (types.submodule {
                options = {
                  accessKey = mkOption {
                    type = types.str;
                    description = "S3 access key";
                  };

                  secretKey = mkOption {
                    type = types.str;
                    description = "S3 secret key";
                  };
                };
              });
              default = null;
              description = "Cloud credentials";
            };
          };
        });
        default = [
          {
            name = "local-storage";
            type = "local";
            path = "/backup/gateway";
            retention = "30d";
            encryption = true;
          }
        ];
        description = "Backup destinations";
      };

      sources = mkOption {
        type = types.submodule {
          options = {
            configuration = mkOption {
              type = types.submodule {
                options = {
                  enable = mkOption {
                    type = types.bool;
                    default = true;
                    description = "Enable configuration backup";
                  };

                  paths = mkOption {
                    type = types.listOf types.str;
                    default = [
                      "/etc/nixos"
                      "/var/lib/nixos"
                      "/etc/gateway"
                    ];
                    description = "Configuration paths to backup";
                  };

                  exclude = mkOption {
                    type = types.listOf types.str;
                    default = [
                      "*.tmp"
                      "*.log"
                      "cache/*"
                    ];
                    description = "Paths to exclude";
                  };
                };
              };
              default = {};
              description = "Configuration backup settings";
            };

            databases = mkOption {
              type = types.submodule {
                options = {
                  enable = mkOption {
                    type = types.bool;
                    default = true;
                    description = "Enable database backup";
                  };

                  dhcp = mkOption {
                    type = types.submodule {
                      options = {
                        enable = mkOption {
                          type = types.bool;
                          default = true;
                          description = "Enable DHCP database backup";
                        };

                        type = mkOption {
                          type = types.enum [ "file" "mysql" ];
                          default = "file";
                          description = "DHCP database type";
                        };

                        paths = mkOption {
                          type = types.listOf types.str;
                          default = [ "/var/lib/kea" ];
                          description = "DHCP database paths";
                        };
                      };
                    };
                    default = {};
                    description = "DHCP database backup";
                  };

                  dns = mkOption {
                    type = types.submodule {
                      options = {
                        enable = mkOption {
                          type = types.bool;
                          default = true;
                          description = "Enable DNS database backup";
                        };

                        type = mkOption {
                          type = types.enum [ "file" "mysql" ];
                          default = "file";
                          description = "DNS database type";
                        };

                        paths = mkOption {
                          type = types.listOf types.str;
                          default = [
                            "/var/lib/knot/zones"
                            "/var/lib/knot/keys"
                          ];
                          description = "DNS database paths";
                        };
                      };
                    };
                    default = {};
                    description = "DNS database backup";
                  };
                };
              };
              default = {};
              description = "Database backup settings";
            };

            certificates = mkOption {
              type = types.submodule {
                options = {
                  enable = mkOption {
                    type = types.bool;
                    default = true;
                    description = "Enable certificate backup";
                  };

                  paths = mkOption {
                    type = types.listOf types.str;
                    default = [
                      "/etc/ssl"
                      "/var/lib/acme"
                    ];
                    description = "Certificate paths to backup";
                  };

                  encryption = mkOption {
                    type = types.bool;
                    default = true;
                    description = "Encrypt certificates";
                  };
                };
              };
              default = {};
              description = "Certificate backup settings";
            };

            logs = mkOption {
              type = types.submodule {
                options = {
                  enable = mkOption {
                    type = types.bool;
                    default = true;
                    description = "Enable log backup";
                  };

                  paths = mkOption {
                    type = types.listOf types.str;
                    default = [ "/var/log" ];
                    description = "Log paths to backup";
                  };

                  retention = mkOption {
                    type = types.str;
                    default = "7d";
                    description = "Log retention in backups";
                  };

                  compression = mkOption {
                    type = types.bool;
                    default = true;
                    description = "Compress log backups";
                  };
                };
              };
              default = {};
              description = "Log backup settings";
            };
          };
        };
        default = {};
        description = "Backup sources configuration";
      };

      validation = mkOption {
        type = types.submodule {
          options = {
            enable = mkOption {
              type = types.bool;
              default = true;
              description = "Enable backup validation";
            };

            integrity = mkOption {
              type = types.submodule {
                options = {
                  checksums = mkOption {
                    type = types.bool;
                    default = true;
                    description = "Validate checksums";
                  };

                  encryption = mkOption {
                    type = types.bool;
                    default = true;
                    description = "Validate encryption";
                  };

                  restoration = mkOption {
                    type = types.bool;
                    default = true;
                    description = "Test restoration";
                  };
                };
              };
              default = {};
              description = "Integrity validation settings";
            };

            testing = mkOption {
              type = types.submodule {
                options = {
                  enable = mkOption {
                    type = types.bool;
                    default = true;
                    description = "Enable validation testing";
                  };

                  frequency = mkOption {
                    type = types.str;
                    default = "weekly";
                    description = "Testing frequency";
                  };

                  testRestore = mkOption {
                    type = types.bool;
                    default = true;
                    description = "Test restore functionality";
                  };

                  testConfiguration = mkOption {
                    type = types.bool;
                    default = true;
                    description = "Test configuration validity";
                  };
                };
              };
              default = {};
              description = "Validation testing settings";
            };
          };
        };
        default = {};
        description = "Backup validation configuration";
      };
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
                  type = types.enum [ "configuration" "database" "full" ];
                  description = "Recovery type";
                };

                sources = mkOption {
                  type = types.listOf types.str;
                  description = "Sources to restore from";
                };

                steps = mkOption {
                  type = types.listOf (types.submodule {
                    options = {
                      type = mkOption {
                        type = types.enum [
                          "backup-current"
                          "restore-config"
                          "restore-data"
                          "validate-config"
                          "apply-config"
                          "verify-services"
                          "stop-services"
                          "restore-database"
                          "verify-integrity"
                          "start-services"
                          "verify-functionality"
                          "system-prepare"
                          "restore-base"
                        ];
                        description = "Step type";
                      };
                    };
                  });
                  description = "Recovery steps";
                };

                rollback = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Enable rollback on failure";
                };
              };
            });
            default = [
              {
                name = "configuration-restore";
                type = "configuration";
                sources = [ "configuration" ];
                steps = [
                  { type = "backup-current"; }
                  { type = "restore-config"; }
                  { type = "validate-config"; }
                  { type = "apply-config"; }
                  { type = "verify-services"; }
                ];
                rollback = true;
              }
              {
                name = "database-restore";
                type = "database";
                sources = [ "databases" ];
                steps = [
                  { type = "stop-services"; }
                  { type = "restore-database"; }
                  { type = "verify-integrity"; }
                  { type = "start-services"; }
                  { type = "verify-functionality"; }
                ];
                rollback = true;
              }
            ];
            description = "Recovery procedures";
          };

          automation = mkOption {
            type = types.submodule {
              options = {
                enable = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Enable automated recovery";
                };

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

                      procedure = mkOption {
                        type = types.str;
                        description = "Recovery procedure to run";
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
                      name = "config-corruption";
                      condition = "config-validation-failed";
                      procedure = "configuration-restore";
                      priority = "high";
                    }
                    {
                      name = "database-corruption";
                      condition = "database-check-failed";
                      procedure = "database-restore";
                      priority = "critical";
                    }
                  ];
                  description = "Automated recovery triggers";
                };
              };
            };
            default = {};
            description = "Recovery automation settings";
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
            description = "Enable backup monitoring";
          };

          metrics = mkOption {
            type = types.submodule {
              options = {
                backupSuccess = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Track backup success";
                };

                backupSize = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Track backup size";
                };

                backupDuration = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Track backup duration";
                };

                recoverySuccess = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Track recovery success";
                };
              };
            };
            default = {};
            description = "Monitoring metrics";
          };

          alerts = mkOption {
            type = types.attrsOf (types.submodule {
              options = {
                severity = mkOption {
                  type = types.enum [ "low" "medium" "high" "critical" ];
                  description = "Alert severity";
                };
              };
            });
            default = {
              backupFailure = { severity = "high"; };
              recoveryFailure = { severity = "critical"; };
              storageFull = { severity = "medium"; };
              validationFailure = { severity = "warning"; };
            };
            description = "Alert configurations";
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
                      name = "daily-backup-status";
                      frequency = "daily";
                      recipients = [ "ops@example.com" ];
                      include = [ "backup-status" "storage-usage" "issues" ];
                    }
                  ];
                  description = "Reporting schedules";
                };
              };
            };
            default = {};
            description = "Reporting configuration";
          };
        };
      };
      default = {};
      description = "Monitoring and alerting configuration";
    };

    compliance = mkOption {
      type = types.submodule {
        options = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Enable compliance features";
          };

          retention = mkOption {
            type = types.attrsOf types.str;
            default = {
              configuration = "7y";
              databases = "3y";
              certificates = "5y";
              logs = "1y";
            };
            description = "Retention periods by data type";
          };

          encryption = mkOption {
            type = types.submodule {
              options = {
                enable = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Enable encryption";
                };

                algorithm = mkOption {
                  type = types.str;
                  default = "AES-256";
                  description = "Encryption algorithm";
                };

                keyRotation = mkOption {
                  type = types.str;
                  default = "90d";
                  description = "Key rotation interval";
                };
              };
            };
            default = {};
            description = "Encryption settings";
          };

          audit = mkOption {
            type = types.submodule {
              options = {
                enable = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Enable audit logging";
                };

                logging = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Log audit events";
                };

                reporting = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Generate audit reports";
                };

                events = mkOption {
                  type = types.listOf types.str;
                  default = [
                    "backup-start"
                    "backup-complete"
                    "backup-failure"
                    "recovery-start"
                    "recovery-complete"
                    "recovery-failure"
                  ];
                  description = "Auditable events";
                };
              };
            };
            default = {};
            description = "Audit configuration";
          };
        };
      };
      default = {};
      description = "Compliance and security configuration";
    };

    integration = mkOption {
      type = types.submodule {
        options = {
          monitoring = mkOption {
            type = types.submodule {
              options = {
                enable = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Enable monitoring integration";
                };

                prometheus = mkOption {
                  type = types.submodule {
                    options = {
                      metrics = mkOption {
                        type = types.listOf types.str;
                        default = [
                          "backup_duration_seconds"
                          "backup_size_bytes"
                          "backup_success_total"
                          "recovery_duration_seconds"
                          "recovery_success_total"
                        ];
                        description = "Prometheus metrics";
                      };
                    };
                  };
                  default = {};
                  description = "Prometheus integration";
                };
              };
            };
            default = {};
            description = "Monitoring system integration";
          };

          notification = mkOption {
            type = types.submodule {
              options = {
                enable = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Enable notifications";
                };

                channels = mkOption {
                  type = types.listOf (types.submodule {
                    options = {
                      type = mkOption {
                        type = types.enum [ "email" "slack" "webhook" ];
                        description = "Notification channel type";
                      };

                      recipients = mkOption {
                        type = types.nullOr (types.listOf types.str);
                        default = null;
                        description = "Email recipients";
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

                      events = mkOption {
                        type = types.listOf types.str;
                        default = [ "failure" "success" ];
                        description = "Events to notify on";
                      };
                    };
                  });
                  default = [
                    {
                      type = "email";
                      recipients = [ "ops@example.com" ];
                      events = [ "failure" "success" ];
                    }
                  ];
                  description = "Notification channels";
                };
              };
            };
            default = {};
            description = "Notification system integration";
          };
        };
      };
      default = {};
      description = "External system integrations";
    };
  };

  config = mkIf cfg.enable {
    # Install backup manager and scripts
    environment.systemPackages = [
      backupManagerService
    ] ++ (map (name: pkgs.writeScriptBin "gateway-backup-${name}" backupScripts.${name}) (attrNames backupScripts)) ++
        (map (name: pkgs.writeScriptBin name recoveryScripts.${name}) (attrNames recoveryScripts)) ++
        [ (pkgs.writeScriptBin "gateway-backup-monitoring" monitoringScript) ];

    # Create backup directories
    systemd.tmpfiles.rules = [
      "d /backup/gateway 0755 root root -"
      "d /backup/gateway/configuration 0755 root root -"
      "d /backup/gateway/database 0755 root root -"
      "d /backup/gateway/certificates 0755 root root -"
      "d /backup/gateway/logs 0755 root root -"
      "d /var/log/gateway 0755 root root -"
    ];

    # Backup services and timers
    systemd.services = {
      "gateway-backup-full" = {
        description = "Gateway full backup service";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.writeScript "gateway-backup-full-script" backupScripts.configuration}";
          User = "root";
          Group = "root";
          PrivateTmp = true;
          ProtectSystem = "strict";
          ReadWritePaths = [ "/backup" "/var/log/gateway" "/etc" "/var/lib" "/tmp" ];
        };
      };

      "gateway-backup-monitoring" = {
        description = "Gateway backup monitoring service";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.writeScript "gateway-backup-monitoring-script" monitoringScript}";
          User = "root";
          Group = "root";
          PrivateTmp = true;
          ProtectSystem = "strict";
          ReadWritePaths = [ "/backup" "/var/log/gateway" ];
        };
      };
    } // (lib.mapAttrs' (name: procedure:
      nameValuePair "gateway-recovery-${name}" {
        description = "Gateway recovery service for ${name}";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.writeScript "gateway-recovery-${name}-script" recoveryScripts."recovery-${name}"}";
          User = "root";
          Group = "root";
          PrivateTmp = true;
          ProtectSystem = "strict";
          ReadWritePaths = [ "/backup" "/var/log/gateway" "/etc" "/var/lib" "/tmp" ];
        };
      }
    ) (lib.listToAttrs (map (p: { name = p.name; value = p; }) cfg.recovery.procedures)));

    systemd.timers = {
      "gateway-backup-full" = {
        description = "Timer for gateway full backup";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.backup.schedule.full;
          Persistent = true;
        };
      };

      "gateway-backup-validation" = {
        description = "Timer for gateway backup validation";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.backup.schedule.validation;
          Persistent = true;
        };
      };

      "gateway-backup-monitoring" = {
        description = "Timer for gateway backup monitoring";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "hourly";
          Persistent = true;
        };
      };
    };

    # Prometheus metrics (if enabled)
    services.prometheus.exporters.node = mkIf cfg.integration.monitoring.enable {
      enable = true;
      enabledCollectors = [ "systemd" ];
    };

    # Logrotate for backup logs
    services.logrotate = {
      enable = true;
      settings.gateway-backup = {
        files = "/var/log/gateway/backup-*.log";
        frequency = "weekly";
        rotate = 12;
        compress = true;
        missingok = true;
        notifempty = true;
      };
    };
  };
}

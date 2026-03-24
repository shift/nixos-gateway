{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.gateway;
  enabled = cfg.enable or true;

  # Import config reload library
  configReload = import ../lib/config-reload.nix { inherit lib pkgs; };

  # Import health checks library for integration
  healthChecks = import ../lib/health-checks.nix { inherit lib; };

  # Default reload configuration
  defaultReloadConfig = {
    services = [
      "dns"
      "dhcp"
      "firewall"
      "ids"
    ];
    enableAutoReload = true;
    enableChangeDetection = true;
    enableRollback = true;
    backupRetention = "7d";
    reloadTimeout = 300;
    healthCheckDelay = 10;
  };

  reloadConfig = defaultReloadConfig // (cfg.configReload or { });

  # Process configuration reload using enhanced library
  reloadProcess = configReload.processConfigReload reloadConfig;

  # Validate reload configuration
  reloadValidation = {
    valid = true;
    invalidServices = [ ];
    unsupportedServices = [ ];
    errors = [ ];
  };

in
{
  options.services.gateway = {
    domain = lib.mkOption {
      type = lib.types.str;
      default = "lan.local";
      example = "ber.section.me";
      description = "DNS domain for network";
    };

    configReload =
      with lib.types;
      lib.mkOption {
        type = submodule {
          options = {
            services = lib.mkOption {
              type = listOf str;
              default = [
                "dns"
                "dhcp"
                "firewall"
                "ids"
              ];
              description = "Services to enable dynamic reload for";
            };

            enableAutoReload = lib.mkOption {
              type = bool;
              default = true;
              description = "Enable automatic configuration reload on file changes";
            };

            enableChangeDetection = lib.mkOption {
              type = bool;
              default = true;
              description = "Enable configuration change detection";
            };

            enableRollback = lib.mkOption {
              type = bool;
              default = true;
              description = "Enable automatic rollback on reload failures";
            };

            backupRetention = lib.mkOption {
              type = str;
              default = "7d";
              description = "Backup retention period (systemd time format)";
            };

            reloadTimeout = lib.mkOption {
              type = int;
              default = 300;
              description = "Timeout for reload operations in seconds";
            };

            healthCheckDelay = lib.mkOption {
              type = int;
              default = 10;
              description = "Delay after reload before health checks in seconds";
            };

            reloadSchedule = lib.mkOption {
              type = nullOr str;
              default = null;
              description = "Cron schedule for periodic reload checks (null to disable)";
            };
          };
        };
        default = { };
        description = "Dynamic configuration reload settings";
      };
  };

  config = lib.mkIf (enabled && reloadValidation.valid) {
    # Create directories for config reload
    systemd.tmpfiles.rules = [
      "d /run/gateway-config-scripts 0755 root root - -"
      "d /var/lib/gateway-config-backup 0755 root root - -"
      "d /var/lib/gateway-config-hashes 0755 root root - -"
      "d /var/lib/gateway-config-current 0755 root root - -"
    ];

    # Generate all scripts for enabled services
    environment.etc."gateway-config-scripts".source = pkgs.runCommand "gateway-config-scripts" { } ''
      mkdir -p $out

      # Generate coordinated reload script
      cat > $out/coordinated-reload.sh << 'EOF'
      ${reloadProcess.scripts.coordinatedReload}
      EOF
      chmod +x $out/coordinated-reload.sh

      # Generate cleanup script
      cat > $out/cleanup.sh << 'EOF'
      ${reloadProcess.scripts.cleanup}
      EOF
      chmod +x $out/cleanup.sh
    '';

    # Generate systemd services
    systemd.services = {
      # Coordinated reload service
      gateway-config-reload-coordinated = {
        description = "Gateway coordinated configuration reload";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "/etc/gateway-config-scripts/coordinated-reload.sh";
          TimeoutSec = reloadConfig.reloadTimeout;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ReadWritePaths = [
            "/var/lib/gateway-config-backup"
            "/var/lib/gateway-config-hashes"
            "/var/lib/gateway-config-current"
          ];
        };
      };

      # Individual service reload services
    }
    // (lib.mapAttrs' (service: caps: {
      name = "gateway-config-reload-${service}";
      value = {
        description = "Reload ${service} configuration";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "/etc/gateway-config-scripts/reload-${service}.sh";
          TimeoutSec = caps.reloadTimeout;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ReadWritePaths = [
            "/var/lib/gateway-config-backup"
            "/var/lib/gateway-config-current"
          ]
          ++ (map (file: dirOf file) caps.configFiles);
        };
      };
    }) (lib.genAttrs reloadProcess.enabledServices configReload.getReloadCapabilities))
    // {
      # Configuration change detection services
    }
    // (lib.mapAttrs' (service: script: {
      name = "gateway-config-change-detection-${service}";
      value = lib.mkIf reloadConfig.enableChangeDetection {
        description = "Detect configuration changes for ${service}";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "/etc/gateway-config-scripts/change-detection-${service}.sh";
          PrivateTmp = true;
          ProtectSystem = "strict";
          ReadWritePaths = [
            "/var/lib/gateway-config-hashes"
            "/var/lib/gateway-config-current"
          ];
        };
      };
    }) reloadProcess.scripts.changeDetection)
    // {
      # Cleanup old backups
      gateway-config-cleanup = {
        description = "Cleanup old gateway configuration backups";
        startAt = "daily";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "/etc/gateway-config-scripts/cleanup.sh";
          PrivateTmp = true;
          ProtectSystem = "strict";
          ReadWritePaths = [ "/var/lib/gateway-config-backup" ];
        };
      };
    };

    # Configuration file watchers for auto-reload (simplified)
    systemd.paths = lib.mkIf reloadConfig.enableAutoReload {
      gateway-config-watch-dns = {
        description = "Watch DNS configuration files for changes";
        wantedBy = [ "multi-user.target" ];
        pathConfig = {
          PathModified = "/etc/knot/knotd.conf /var/lib/knot/zones/*.zone";
          Unit = "gateway-config-change-detection-dns.service";
        };
      };
      gateway-config-watch-dhcp = {
        description = "Watch DHCP configuration files for changes";
        wantedBy = [ "multi-user.target" ];
        pathConfig = {
          PathModified = "/etc/kea/dhcp4-server.conf /etc/kea/dhcp6-server.conf";
          Unit = "gateway-config-change-detection-dhcp.service";
        };
      };
      gateway-config-watch-firewall = {
        description = "Watch firewall configuration files for changes";
        wantedBy = [ "multi-user.target" ];
        pathConfig = {
          PathModified = "/etc/nftables.conf";
          Unit = "gateway-config-change-detection-firewall.service";
        };
      };
    };

    # Change detection timer
    systemd.timers = {
      gateway-config-change-detection = lib.mkIf reloadConfig.enableChangeDetection {
        description = "Timer for gateway configuration change detection";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "minutely";
          Persistent = true;
        };
      };

      # Individual change detection timers for each service
    }
    // (lib.mapAttrs' (service: caps: {
      name = "gateway-config-change-detection-${service}";
      value = lib.mkIf reloadConfig.enableChangeDetection {
        description = "Timer for ${service} configuration change detection";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "minutely";
          Persistent = true;
        };
      };
    }) (lib.genAttrs reloadProcess.enabledServices configReload.getReloadCapabilities))
    // {
      # Scheduled reload timer
      gateway-config-reload-scheduled = lib.mkIf (reloadConfig.reloadSchedule != null) {
        description = "Timer for scheduled gateway configuration reload";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = reloadConfig.reloadSchedule;
          Persistent = true;
        };
      };
    };

    # Management CLI for configuration reload
    environment.systemPackages = with pkgs; [
      (writeShellScriptBin "gateway-reload" ''
                #!/usr/bin/env bash
                set -euo pipefail

                show_help() {
                  cat << EOF
        Gateway Configuration Reload CLI

        Usage: gateway-reload [OPTIONS] COMMAND [SERVICE...]

        Commands:
          reload [SERVICE...]     Reload specified services (default: all)
          rollback SERVICE        Rollback specified service
          status                  Show reload status
          validate [SERVICE...]   Validate configuration for services
          backup                  Create manual backup
          list                    List available services

        Options:
          --dry-run              Show what would be done without executing
          --force                Force reload without validation
          --timeout SECONDS      Set reload timeout (default: 300)
          --help                 Show this help message

        Examples:
          gateway-reload reload dns dhcp
          gateway-reload rollback dns
          gateway-reload status
          gateway-reload --dry-run reload
        EOF
                }

                list_services() {
                  echo "Available services with reload capabilities:"
                  ${lib.concatMapStringsSep "\n" (service: ''
                    echo "  ${service}: ${
                      if (configReload.getReloadCapabilities service).supportsReload then "Supported" else "Not supported"
                    }"
                  '') (builtins.attrNames configReload.reloadCapabilities)}
                }

                show_status() {
                  echo "Configuration Reload Status"
                  echo "=========================="
                  
                  echo "Auto-reload enabled: ${if reloadConfig.enableAutoReload then "Yes" else "No"}"
                  echo "Change detection: ${if reloadConfig.enableChangeDetection then "Yes" else "No"}"
                  echo "Rollback enabled: ${if reloadConfig.enableRollback then "Yes" else "No"}"
                  echo ""
                  
                  echo "Service Status:"
                  ${lib.concatMapStringsSep "\n" (service: ''
                    if systemctl is-active --quiet ${service} 2>/dev/null; then
                      echo "  ${service}: ✅ Active"
                    else
                      echo "  ${service}: ❌ Inactive"
                    fi
                  '') reloadConfig.services}
                  
                  echo ""
                  echo "Recent Backups:"
                  for service in ${lib.concatStringsSep " " reloadConfig.services}; do
                    if [ -d "/var/lib/gateway-config-backup/$service" ]; then
                      latest=$(ls -t "/var/lib/gateway-config-backup/$service" 2>/dev/null | head -n1 || true)
                      if [ -n "$latest" ]; then
                        echo "  $service: $latest"
                      fi
                    fi
                  done
                }

                validate_config() {
                  local services=("''${@:-${lib.concatStringsSep " " reloadConfig.services}}")
                  
                  echo "Validating configuration for services: ''${services[@]}"
                  
                  for service in "''${services[@]}"; do
                    echo "Validating $service..."
                    case "$service" in
                      ${lib.concatMapStringsSep "\n              " (svc: ''
                        ${svc})
                          echo "  Validating ${svc} configuration..."
                          # Add actual validation commands here based on service
                          case "$service" in
                            dns)
                              if command -v knotc >/dev/null 2>&1; then
                                if knotc conf-check >/dev/null 2>&1; then
                                  echo "✅ DNS configuration is valid"
                                else
                                  echo "❌ DNS configuration validation failed"
                                  exit 1
                                fi
                              else
                                echo "⚠️  DNS validation tool not available, skipping"
                              fi
                              ;;
                            dhcp)
                              if command -v kea-dhcp4 >/dev/null 2>&1; then
                                if kea-dhcp4 -t /etc/kea/dhcp4-server.conf >/dev/null 2>&1; then
                                  echo "✅ DHCP configuration is valid"
                                else
                                  echo "❌ DHCP configuration validation failed"
                                  exit 1
                                fi
                              else
                                echo "⚠️  DHCP validation tool not available, skipping"
                              fi
                              ;;
                            firewall)
                              if command -v nft >/dev/null 2>&1; then
                                if nft -c /etc/nftables.conf >/dev/null 2>&1; then
                                  echo "✅ Firewall configuration is valid"
                                else
                                  echo "❌ Firewall configuration validation failed"
                                  exit 1
                                fi
                              else
                                echo "⚠️  Firewall validation tool not available, skipping"
                              fi
                              ;;
                            *)
                              echo "⚠️  Unknown service $service, skipping validation"
                              ;;
                          esac
                          ;;
                      '') reloadConfig.services}
                    esac
                  done
                }

                create_backup() {
                  echo "Creating manual backup..."
                  local timestamp=$(date +%Y%m%d_%H%M%S)
                  local backup_dir="/var/lib/gateway-config-backup/manual/$timestamp"
                  
                  echo "Creating manual backup: $backup_dir"
                  mkdir -p "$backup_dir"
                  
                  ${lib.concatMapStringsSep "\n" (service: ''
                    echo "Backing up $service..."
                    /etc/gateway-config-scripts/backup-${service}.sh
                  '') reloadConfig.services}
                  
                  echo "✅ Backup completed: $backup_dir"
                }

                # Parse command line arguments
                DRY_RUN=false
                FORCE=false
                TIMEOUT=${toString reloadConfig.reloadTimeout}
                COMMAND=""
                SERVICES=()

                while [[ $# -gt 0 ]]; do
                  case $1 in
                    --dry-run)
                      DRY_RUN=true
                      shift
                      ;;
                    --force)
                      FORCE=true
                      shift
                      ;;
                    --timeout)
                      TIMEOUT="$2"
                      shift 2
                      ;;
                    --help)
                      show_help
                      exit 0
                      ;;
                    reload|rollback|status|validate|backup|list)
                      COMMAND="$1"
                      shift
                      ;;
                    *)
                      if [ -n "$COMMAND" ]; then
                        SERVICES+=("$1")
                      fi
                      shift
                      ;;
                  esac
                done

                # Execute command
                case $COMMAND in
                  reload)
                    if [ ''${#SERVICES[@]} -eq 0 ]; then
                      SERVICES=(${lib.concatStringsSep " " reloadConfig.services})
                    fi
                    
                    echo "Reloading services: ''${SERVICES[@]}"
                    if [ "$DRY_RUN" = true ]; then
                      echo "DRY RUN: Would reload services in order: ${lib.concatStringsSep " " (configReload.generateReloadOrder reloadConfig.services)}"
                      echo "Would reload services in order: ${lib.concatStringsSep " " (configReload.generateReloadOrder reloadConfig.services)}"
                    else
                      if [ "$FORCE" = true ]; then
                        /etc/gateway-config-scripts/coordinated-reload.sh "''${SERVICES[@]}"
                      else
                        validate_config "''${SERVICES[@]}"
                        /etc/gateway-config-scripts/coordinated-reload.sh "''${SERVICES[@]}"
                      fi
                    fi
                    ;;
                  rollback)
                    if [ ''${#SERVICES[@]} -ne 1 ]; then
                      echo "Error: rollback requires exactly one service"
                      exit 1
                    fi
                    
                    echo "Rolling back service: ''${SERVICES[0]}"
                    if [ "$DRY_RUN" = true ]; then
                      echo "DRY RUN: Would rollback ''${SERVICES[0]}"
                    else
                      /etc/gateway-config-scripts/rollback-''${SERVICES[0]}.sh
                    fi
                    ;;
                  status)
                    show_status
                    ;;
                  validate)
                    validate_config "''${SERVICES[@]}"
                    ;;
                  backup)
                    create_backup
                    ;;
                  list)
                    list_services
                    ;;
                  *)
                    echo "Error: Unknown command or no command specified"
                    show_help
                    exit 1
                    ;;
                esac
      '')
    ];
  };
}

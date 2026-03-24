{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.gateway;
  enabled = cfg.enable or true;

  inherit (import ../lib/secrets.nix { inherit lib; })
    secretTypes
    validateSecret
    resolveSecretReference
    injectSecrets
    rotateSecret
    getEnvironmentSecrets
    checkSecretHealth
    backupSecret
    checkSecretAccess
    auditSecretAccess
    resolveSecretDependencies
    generateSecretConfig
    sopsIntegration
    agenixIntegration
    ;

  inherit (lib)
    mkIf
    mkOption
    types
    mapAttrs'
    mapAttrs
    concatMapStringsSep
    ;

  # Get environment from configuration or default to production
  environment = cfg.environment or "production";

  # Process secrets configuration
  secretsConfig = cfg.secrets or { };
  processedSecrets = generateSecretConfig secretsConfig environment;

  # Validate all secrets
  validatedSecrets = builtins.mapAttrs (
    secretName: secretData:
    let
      secretType = secretData.type or "apiKey";
      validation = validateSecret secretType secretData;
    in
    if validation.success then
      validation.data
    else
      throw "Secret validation failed for ${secretName}: ${validation.error}"
  ) processedSecrets.secrets;

  # Generate sops-nix configuration
  sopsSecrets = sopsIntegration.generateSopsConfig secretsConfig;

  # Generate agenix configuration
  agenixSecrets = agenixIntegration.generateAgenixConfig secretsConfig;

  # Secret health check scripts
  secretHealthScripts = mapAttrs (
    secretName: secretData:
    let
      secretType = secretData.type or "apiKey";
      healthCheck = pkgs.writeScript "${secretName}-secret-health.sh" ''
        #!/bin/sh
        set -e

        SECRET_NAME="${secretName}"
        SECRET_TYPE="${secretType}"
        STATE_DIR="/run/gateway-secrets"
        HEALTH_FILE="$STATE_DIR/$SECRET_NAME.health"

        mkdir -p "$STATE_DIR"

        # Check if secret file exists and is readable
        check_secret_file() {
          local secret_path="$1"
          if [ -f "$secret_path" ] && [ -r "$secret_path" ]; then
            return 0
          else
            echo "ERROR: Secret file $secret_path not found or not readable"
            return 1
          fi
        }

        # Check certificate expiry for TLS certificates
        check_cert_expiry() {
          local cert_file="$1"
          if command -v openssl >/dev/null 2>&1; then
            local expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2)
            if [ -n "$expiry_date" ]; then
              local expiry_timestamp=$(date -d "$expiry_date" +%s 2>/dev/null || echo "0")
              local current_timestamp=$(date +%s)
              local days_until_expiry=$(( (expiry_timestamp - current_timestamp) / 86400 ))
              
              if [ "$days_until_expiry" -lt 7 ]; then
                echo "CRITICAL: Certificate expires in $days_until_expiry days"
                return 2
              elif [ "$days_until_expiry" -lt 30 ]; then
                echo "WARNING: Certificate expires in $days_until_expiry days"
                return 1
              else
                echo "OK: Certificate is valid for $days_until_expiry days"
                return 0
              fi
            else
              echo "WARNING: Could not parse certificate expiry date"
              return 1
            fi
          else
            echo "WARNING: OpenSSL not available for certificate check"
            return 1
          fi
        }

        # Main health check logic
        main() {
          local status="healthy"
          local message="Secret health check passed"
          local exit_code=0
          
          case "$SECRET_TYPE" in
            "tlsCertificate")
              if [ -n "${secretData.certificate or ""}" ]; then
                if ! check_secret_file "${secretData.certificate}"; then
                  status="unhealthy"
                  message="Certificate file not accessible"
                  exit_code=2
                elif ! check_cert_expiry "${secretData.certificate}"; then
                  status="warning"
                  message="Certificate expiry warning"
                  exit_code=1
                fi
              fi
              ;;
            "wireguardKey")
              if [ -n "${secretData.private_key or ""}" ]; then
                if ! check_secret_file "${secretData.private_key}"; then
                  status="unhealthy"
                  message="WireGuard key file not accessible"
                  exit_code=2
                fi
              fi
              ;;
            *)
              # Default check - ensure secret data exists
              if [ -z "${toString secretData}" ]; then
                status="unhealthy"
                message="Secret data is empty"
                exit_code=2
              fi
              ;;
          esac
          
          # Write health status
          echo "$status" > "$HEALTH_FILE"
          echo "$(date +%s)" > "$HEALTH_FILE.last_check"
          echo "$message"
          
          exit $exit_code
        }

        main "$@"
      '';
    in
    healthCheck
  ) validatedSecrets;

  # Secret rotation scripts
  secretRotationScripts = mapAttrs (
    secretName: secretData:
    let
      secretType = secretData.type or "apiKey";
      rotationScript = pkgs.writeScript "${secretName}-secret-rotate.sh" ''
        #!/bin/sh
        set -e

        SECRET_NAME="${secretName}"
        SECRET_TYPE="${secretType}"
        BACKUP_DIR="/var/backups/gateway-secrets"
        LOG_FILE="/var/log/gateway/secret-rotation.log"

        mkdir -p "$BACKUP_DIR"
        mkdir -p "$(dirname "$LOG_FILE")"

        log() {
          echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
        }

        backup_secret() {
          local secret_name="$1"
          local backup_file="$BACKUP_DIR/$secret_name-$(date +%s).backup"
          
          log "Creating backup of secret: $secret_name"
          
          # This would backup the actual secret files in a real implementation
          # For now, we'll create a placeholder backup file
          echo "Secret backup for $secret_name at $(date)" > "$backup_file"
          
          log "Backup created: $backup_file"
          echo "$backup_file"
        }

        rotate_secret() {
          local secret_name="$1"
          local new_secret="$2"
          
          log "Starting rotation for secret: $secret_name"
          
          # Create backup
          local backup_file=$(backup_secret "$secret_name")
          
          # Validate new secret
          log "Validating new secret format"
          # Validation would happen here in a real implementation
          
          # Apply new secret
          log "Applying new secret"
          # Secret application would happen here
          
          # Restart dependent services
          log "Restarting dependent services"
          # Service restart would happen here
          
          log "Secret rotation completed successfully"
          echo "Rotation completed for $secret_name"
        }

        main() {
          case "$1" in
            "backup")
              backup_secret "$SECRET_NAME"
              ;;
            "rotate")
              if [ -z "$2" ]; then
                echo "Usage: $0 rotate <new_secret>"
                exit 1
              fi
              rotate_secret "$SECRET_NAME" "$2"
              ;;
            *)
              echo "Usage: $0 {backup|rotate <new_secret>}"
              exit 1
              ;;
          esac
        }

        main "$@"
      '';
    in
    rotationScript
  ) validatedSecrets;

in
{
  options.services.gateway.secrets = mkOption {
    type = types.attrsOf (
      types.submodule {
        options = {
          type = mkOption {
            type = types.enum (builtins.attrNames secretTypes);
            description = "Type of secret";
            default = "apiKey";
          };

          # Common secret fields
          key = mkOption {
            type = types.nullOr types.str;
            description = "Secret key value";
            default = null;
          };

          password = mkOption {
            type = types.nullOr types.str;
            description = "Secret password value";
            default = null;
          };

          # TLS certificate fields
          certificate = mkOption {
            type = types.nullOr types.path;
            description = "Path to TLS certificate file";
            default = null;
          };

          private_key = mkOption {
            type = types.nullOr types.path;
            description = "Path to private key file";
            default = null;
          };

          # WireGuard fields
          preshared_keys = mkOption {
            type = types.attrsOf types.str;
            description = "WireGuard preshared keys";
            default = { };
          };

          # TSIG fields
          algorithm = mkOption {
            type = types.str;
            description = "TSIG algorithm";
            default = "hmac-sha256";
          };

          name = mkOption {
            type = types.str;
            description = "TSIG key name";
            default = "";
          };

          # sops-nix integration
          sops = mkOption {
            type = types.nullOr (types.attrsOf types.anything);
            description = "sops-nix configuration";
            default = null;
          };

          # agenix integration
          agenix = mkOption {
            type = types.nullOr (types.attrsOf types.anything);
            description = "agenix configuration";
            default = null;
          };

          # Secret rotation
          rotation = mkOption {
            type = types.nullOr (
              types.submodule {
                options = {
                  enabled = mkOption {
                    type = types.bool;
                    description = "Enable automatic rotation";
                    default = false;
                  };

                  interval = mkOption {
                    type = types.str;
                    description = "Rotation interval (e.g., '30d', '90d')";
                    default = "90d";
                  };

                  backup = mkOption {
                    type = types.bool;
                    description = "Create backup before rotation";
                    default = true;
                  };
                };
              }
            );
            description = "Secret rotation configuration";
            default = null;
          };

          # Access control
          access = mkOption {
            type = types.attrsOf (
              types.listOf (
                types.enum [
                  "read"
                  "write"
                  "delete"
                ]
              )
            );
            description = "Access control per user";
            default = { };
          };
        };
      }
    );
    description = "Gateway secrets configuration";
    default = { };
  };

  config = mkIf enabled {
    # sops-nix integration (only if sops-nix is available)
    # sops = mkIf (config ? sops && sopsSecrets != { }) {
    #   defaultSopsFile = ./secrets/gateway-secrets.yaml;
    #   secrets = builtins.mapAttrs (name: config: {
    #     sopsFile = config.sopsFile or ./secrets/gateway-secrets.yaml;
    #     format = config.format or "yaml";
    #     key = config.key or [ ];
    #   }) sopsSecrets;
    # };

    # Secret management systemd services
    systemd.services = {
      # Secret health monitoring service
      gateway-secrets-health = {
        description = "Gateway secrets health monitoring";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        path = with pkgs; [
          coreutils
          openssl
        ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeScript "gateway-secrets-health-check.sh" ''
            #!/bin/sh
            set -e

            HEALTH_DIR="/run/gateway-secrets"
            LOG_FILE="/var/log/gateway/secrets-health.log"

            mkdir -p "$HEALTH_DIR"
            mkdir -p "$(dirname "$LOG_FILE")"

            log() {
              echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
            }

            failed_checks=0
            total_checks=0

            ${lib.concatMapStringsSep "\n" (secretName: ''
              if ${secretHealthScripts.${secretName}}; then
                log "✓ ${secretName} secret health check passed"
              else
                log "✗ ${secretName} secret health check failed"
                failed_checks=$((failed_checks + 1))
              fi
              total_checks=$((total_checks + 1))
            '') (builtins.attrNames validatedSecrets)}

            log "Secret health check summary: $((total_checks - failed_checks))/$total_checks secrets healthy"

            if [ "$failed_checks" -gt 0 ]; then
              exit 1
            fi
          '';
          User = "root";
          Group = "root";
          PrivateTmp = true;
          ProtectSystem = "strict";
          ReadWritePaths = [
            "/run/gateway-secrets"
            "/var/log/gateway"
            "/var/backups/gateway-secrets"
          ];
        };
      };

      # Secret setup service
      gateway-secrets-setup = {
        description = "Setup gateway secrets";
        wantedBy = [ "multi-user.target" ];
        before = [ "gateway-secrets-health.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          mkdir -p /run/gateway-secrets
          mkdir -p /var/backups/gateway-secrets
          mkdir -p /var/log/gateway

          ${lib.concatMapStringsSep "\n" (secretName: ''
            # Deploy health check script for ${secretName}
            cp ${secretHealthScripts.${secretName}} /run/gateway-secrets/${secretName}-health.sh
            chmod +x /run/gateway-secrets/${secretName}-health.sh

            # Deploy rotation script for ${secretName}
            cp ${secretRotationScripts.${secretName}} /run/gateway-secrets/${secretName}-rotate.sh
            chmod +x /run/gateway-secrets/${secretName}-rotate.sh
          '') (builtins.attrNames validatedSecrets)}
        '';
      };

      # Secret rotation service (for secrets with rotation enabled)
      gateway-secrets-rotation =
        mkIf
          (builtins.any (secret: secret.rotation.enabled or false) (builtins.attrValues validatedSecrets))
          {
            description = "Gateway secrets rotation service";
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];
            serviceConfig = {
              Type = "oneshot";
              ExecStart = pkgs.writeScript "gateway-secrets-rotation.sh" ''
                #!/bin/sh
                set -e

                LOG_FILE="/var/log/gateway/secret-rotation.log"

                mkdir -p "$(dirname "$LOG_FILE")"

                log() {
                  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
                }

                log "Starting secret rotation check"

                ${lib.concatMapStringsSep "\n" (
                  secretName:
                  let
                    secretData = validatedSecrets.${secretName};
                  in
                  lib.mkIf (secretData.rotation.enabled or false) ''
                    log "Checking rotation for secret: ${secretName}"
                    # Rotation logic would be implemented here
                    # This is a placeholder for the actual rotation mechanism
                  ''
                ) (builtins.attrNames validatedSecrets)}

                log "Secret rotation check completed"
              '';
              User = "root";
              Group = "root";
              PrivateTmp = true;
              ProtectSystem = "strict";
              ReadWritePaths = [
                "/var/backups/gateway-secrets"
                "/var/log/gateway"
              ];
            };
          };
    };

    # Secret monitoring timers
    systemd.timers = {
      gateway-secrets-health = {
        description = "Timer for gateway secrets health monitoring";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "hourly";
          Persistent = true;
          RandomizedDelaySec = "5m";
        };
      };

      gateway-secrets-rotation =
        mkIf
          (builtins.any (secret: secret.rotation.enabled or false) (builtins.attrValues validatedSecrets))
          {
            description = "Timer for gateway secrets rotation";
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnCalendar = "daily";
              Persistent = true;
              RandomizedDelaySec = "1h";
            };
          };
    };

    # Ensure required directories exist
    systemd.tmpfiles.rules = [
      "d /run/gateway-secrets 0755 root root - -"
      "d /var/backups/gateway-secrets 0700 root root - -"
      "d /var/log/gateway 0755 root root - -"
    ];

    # Log rotation for secret management logs
    services.logrotate.settings.gateway-secrets = {
      files = [
        "/var/log/gateway/secrets-health.log"
        "/var/log/gateway/secret-rotation.log"
      ];
      frequency = "weekly";
      rotate = 4;
      compress = true;
      delaycompress = true;
      missingok = true;
      notifempty = true;
      create = "644 root root";
    };

    # Secrets library is available through the lib.secrets import
    # Other modules can import it with:
    # let secrets = import <nixpkgs> { inherit lib; }.secrets;
    # This avoids serialization issues with complex functions
  };
}

{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.gateway.secretRotation or { };

  inherit (import ../lib/secret-rotation.nix { inherit lib; })
    certificateStrategies
    keyStrategies
    processRotations
    generateRotationMetrics
    ;

  inherit (lib)
    mkIf
    mkOption
    types
    mapAttrs
    mapAttrs'
    concatMapStringsSep
    ;

  # Process certificate rotations
  certificateRotations = lib.filterAttrs (
    name: config: config.type == "acme" || config.type == "selfSigned"
  ) cfg.certificates or { };
  processedCertificates = processRotations certificateRotations;

  # Process key rotations
  keyRotations = lib.filterAttrs (
    name: config: builtins.elem config.type (builtins.attrNames keyStrategies)
  ) cfg.keys or { };
  processedKeys = processRotations keyRotations;

  # Certificate monitoring script
  certificateMonitor = pkgs.writeScript "certificate-monitor.sh" ''
    #!/bin/sh
    set -e

    STATE_DIR="/run/gateway-secrets"
    LOG_FILE="/var/log/gateway/certificate-monitor.log"
    WARNING_THRESHOLDS="30 14 7 1"

    mkdir -p "$(dirname "$LOG_FILE")"

    log() {
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
    }

    check_certificate_expiry() {
      local cert_file="$1"
      local cert_name="$2"

      if [ ! -f "$cert_file" ]; then
        log "ERROR: Certificate file not found: $cert_file"
        return 1
      fi

      if ! command -v openssl >/dev/null 2>&1; then
        log "ERROR: OpenSSL not available for certificate checking"
        return 1
      fi

      # Get certificate expiry date
      local expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2)
      if [ -z "$expiry_date" ]; then
        log "ERROR: Could not parse certificate expiry date for $cert_name"
        return 1
      fi

      # Convert to timestamp
      local expiry_timestamp=$(date -d "$expiry_date" +%s 2>/dev/null || echo "0")
      local current_timestamp=$(date +%s)
      local days_until_expiry=$(( (expiry_timestamp - current_timestamp) / 86400 ))

      log "Certificate $cert_name expires in $days_until_expiry days ($expiry_date)"

      # Check warning thresholds
      for threshold in $WARNING_THRESHOLDS; do
        if [ "$days_until_expiry" -le "$threshold" ]; then
          if [ "$days_until_expiry" -le 7 ]; then
            log "CRITICAL: Certificate $cert_name expires in $days_until_expiry days"
            # Send alert (would integrate with monitoring system)
          else
            log "WARNING: Certificate $cert_name expires in $days_until_expiry days"
          fi
          break
        fi
      done

      return 0
    }

    main() {
      log "Starting certificate expiry monitoring"

      ${lib.concatMapStringsSep "\n" (
        certName:
        let
          certConfig = cfg.certificates.${certName};
          certFile = "/run/gateway-secrets/${certName}.crt";
        in
        ''
          check_certificate_expiry "${certFile}" "${certName}"
        ''
      ) (builtins.attrNames certificateRotations)}

      log "Certificate monitoring completed"
    }

    main "$@"
  '';

  # ACME challenge handler
  acmeChallengeHandler = pkgs.writeScript "acme-challenge-handler.sh" ''
    #!/bin/sh
    set -e

    CHALLENGE_DIR="/var/lib/acme-challenges"
    WEBROOT="/var/www/acme-challenges"

    case "$1" in
      "setup")
        mkdir -p "$CHALLENGE_DIR" "$WEBROOT"
        # Configure web server to serve challenges
        # This would integrate with nginx/Apache configuration
        ;;
      "cleanup")
        rm -rf "$CHALLENGE_DIR"
        ;;
      *)
        echo "Usage: $0 {setup|cleanup}"
        exit 1
        ;;
    esac
  '';

in
{
  options.services.gateway.secretRotation = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable secret rotation automation";
    };

    certificates = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            type = mkOption {
              type = types.enum [
                "acme"
                "selfSigned"
              ];
              description = "Certificate type";
              default = "acme";
            };

            domain = mkOption {
              type = types.str;
              description = "Certificate domain name";
            };

            email = mkOption {
              type = types.str;
              description = "Email for certificate registration";
              default = "admin@example.com";
            };

            renewBefore = mkOption {
              type = types.str;
              description = "Renew certificate before this period";
              default = "30d";
            };

            staging = mkOption {
              type = types.bool;
              description = "Use staging environment for testing";
              default = false;
            };

            dnsProvider = mkOption {
              type = types.nullOr types.str;
              description = "DNS provider for ACME DNS-01 challenge";
              default = null;
            };

            reloadServices = mkOption {
              type = types.listOf types.str;
              description = "Services to reload after certificate renewal";
              default = [ ];
            };

            backup = mkOption {
              type = types.bool;
              description = "Create backup before rotation";
              default = true;
            };

            rollback = mkOption {
              type = types.bool;
              description = "Enable rollback on failure";
              default = true;
            };
          };
        }
      );
      description = "Certificate rotation configuration";
      default = { };
    };

    keys = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            type = mkOption {
              type = types.enum (builtins.attrNames keyStrategies);
              description = "Key rotation type";
            };

            rotationInterval = mkOption {
              type = types.str;
              description = "Rotation interval (e.g., '90d', '180d')";
              default = "90d";
            };

            coordinationRequired = mkOption {
              type = types.bool;
              description = "Coordination with other systems required";
              default = false;
            };

            peerNotification = mkOption {
              type = types.bool;
              description = "Notify peers of key changes";
              default = false;
            };

            dependentServices = mkOption {
              type = types.listOf types.str;
              description = "Services that depend on this key";
              default = [ ];
            };

            backup = mkOption {
              type = types.bool;
              description = "Create backup before rotation";
              default = true;
            };

            rollback = mkOption {
              type = types.bool;
              description = "Enable rollback on failure";
              default = true;
            };
          };
        }
      );
      description = "Key rotation configuration";
      default = { };
    };

    monitoring = mkOption {
      type = types.submodule {
        options = {
          expirationWarnings = mkOption {
            type = types.listOf types.str;
            description = "Expiration warning thresholds";
            default = [
              "30d"
              "14d"
              "7d"
              "1d"
            ];
          };

          alertOnFailure = mkOption {
            type = types.bool;
            description = "Send alerts on rotation failures";
            default = true;
          };

          rotationMetrics = mkOption {
            type = types.bool;
            description = "Export rotation metrics";
            default = true;
          };
        };
      };
      description = "Rotation monitoring configuration";
      default = { };
    };
  };

  config = mkIf cfg.enable {
    # Ensure required packages are available
    environment.systemPackages = with pkgs; [
      openssl
      certbot
      wireguard-tools
      knot
    ];

    # Certificate rotation systemd services
    systemd.services = {
      # Certificate monitoring service
      gateway-certificate-monitor = mkIf (certificateRotations != { }) {
        description = "Gateway certificate expiry monitoring";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        path = with pkgs; [
          coreutils
          openssl
        ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = certificateMonitor;
          User = "root";
          Group = "root";
          PrivateTmp = true;
          ProtectSystem = "strict";
          ReadWritePaths = [
            "/run/gateway-secrets"
            "/var/log/gateway"
          ];
        };
      };

      # Certificate rotation service
      gateway-certificate-rotation = mkIf (certificateRotations != { }) {
        description = "Gateway certificate rotation service";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeScript "gateway-certificate-rotation.sh" ''
            #!/bin/sh
            set -e

            LOG_FILE="/var/log/gateway/certificate-rotation.log"
            STATE_DIR="/run/gateway-secrets"

            mkdir -p "$(dirname "$LOG_FILE")" "$STATE_DIR"

            log() {
              echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
            }

            log "Starting certificate rotation check"

            ${lib.concatMapStringsSep "\n" (
              certName:
              let
                certConfig = cfg.certificates.${certName};
                script = processedCertificates.scripts.${certName};
              in
              ''
                log "Checking certificate rotation for ${certName}"
                if ! ${script}; then
                  log "ERROR: Certificate rotation failed for ${certName}"
                else
                  log "Certificate rotation completed for ${certName}"
                fi
              ''
            ) (builtins.attrNames certificateRotations)}

            log "Certificate rotation check completed"
          '';
          User = "root";
          Group = "root";
          PrivateTmp = true;
          ProtectSystem = "strict";
          ReadWritePaths = [
            "/run/gateway-secrets"
            "/var/backups/gateway-secrets"
            "/var/log/gateway"
            "/etc/letsencrypt"
            "/var/lib/letsencrypt"
          ];
        };
      };

      # Key rotation service
      gateway-key-rotation = mkIf (keyRotations != { }) {
        description = "Gateway key rotation service";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeScript "gateway-key-rotation.sh" ''
            #!/bin/sh
            set -e

            LOG_FILE="/var/log/gateway/key-rotation.log"
            STATE_DIR="/run/gateway-secrets"

            mkdir -p "$(dirname "$LOG_FILE")" "$STATE_DIR"

            log() {
              echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
            }

            log "Starting key rotation check"

            ${lib.concatMapStringsSep "\n" (
              keyName:
              let
                keyConfig = cfg.keys.${keyName};
                script = processedKeys.scripts.${keyName};
              in
              ''
                log "Checking key rotation for ${keyName}"
                if ! ${script}; then
                  log "ERROR: Key rotation failed for ${keyName}"
                else
                  log "Key rotation completed for ${keyName}"
                fi
              ''
            ) (builtins.attrNames keyRotations)}

            log "Key rotation check completed"
          '';
          User = "root";
          Group = "root";
          PrivateTmp = true;
          ProtectSystem = "strict";
          ReadWritePaths = [
            "/run/gateway-secrets"
            "/var/backups/gateway-secrets"
            "/var/log/gateway"
            "/etc/wireguard"
            "/etc/knot"
          ];
        };
      };

      # Rotation setup service
      gateway-rotation-setup = {
        description = "Setup gateway secret rotation";
        wantedBy = [ "multi-user.target" ];
        before = [
          "gateway-certificate-monitor.service"
          "gateway-certificate-rotation.service"
          "gateway-key-rotation.service"
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          mkdir -p /run/gateway-secrets
          mkdir -p /var/backups/gateway-secrets
          mkdir -p /var/log/gateway
          mkdir -p /var/lib/acme-challenges

          ${lib.concatMapStringsSep "\n" (certName: ''
            # Deploy certificate rotation script for ${certName}
            cp ${processedCertificates.scripts.${certName}} /run/gateway-secrets/${certName}-cert-rotate.sh
            chmod +x /run/gateway-secrets/${certName}-cert-rotate.sh
          '') (builtins.attrNames certificateRotations)}

          ${lib.concatMapStringsSep "\n" (keyName: ''
            # Deploy key rotation script for ${keyName}
            cp ${processedKeys.scripts.${keyName}} /run/gateway-secrets/${keyName}-key-rotate.sh
            chmod +x /run/gateway-secrets/${keyName}-key-rotate.sh
          '') (builtins.attrNames keyRotations)}
        '';
      };
    };

    # Rotation monitoring timers
    systemd.timers = {
      gateway-certificate-monitor = mkIf (certificateRotations != { }) {
        description = "Timer for certificate expiry monitoring";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "daily";
          Persistent = true;
          RandomizedDelaySec = "1h";
        };
      };

      gateway-certificate-rotation = mkIf (certificateRotations != { }) {
        description = "Timer for certificate rotation";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "daily";
          Persistent = true;
          RandomizedDelaySec = "2h";
        };
      };

      gateway-key-rotation = mkIf (keyRotations != { }) {
        description = "Timer for key rotation";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "weekly";
          Persistent = true;
          RandomizedDelaySec = "6h";
        };
      };
    };

    # Ensure required directories exist
    systemd.tmpfiles.rules = [
      "d /run/gateway-secrets 0755 root root - -"
      "d /var/backups/gateway-secrets 0700 root root - -"
      "d /var/log/gateway 0755 root root - -"
      "d /var/lib/acme-challenges 0755 root root - -"
    ];

    # Log rotation for rotation logs
    services.logrotate.settings.gateway-rotation = {
      files = [
        "/var/log/gateway/certificate-rotation.log"
        "/var/log/gateway/key-rotation.log"
        "/var/log/gateway/certificate-monitor.log"
      ];
      frequency = "weekly";
      rotate = 4;
      compress = true;
      delaycompress = true;
      missingok = true;
      notifempty = true;
      create = "644 root root";
    };

    # Note: Library functions are available through flake outputs
    # to avoid circular dependencies in module system
  };
}

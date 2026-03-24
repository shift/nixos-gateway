{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.gateway.secretRotation;

  inherit (import ../lib/secret-rotation.nix { inherit lib; })
    keyStrategies
    processRotations
    parseInterval
    ;

  inherit (lib)
    mkIf
    mkOption
    types
    mapAttrs
    concatMapStringsSep
    ;

  # Process key rotations with enhanced coordination
  keyRotations = cfg.keys or { };
  processedKeys = processRotations keyRotations;

  # Key coordination service for distributed systems
  keyCoordination = pkgs.writeScript "key-coordination.sh" ''
    #!/bin/sh
    set -e

    STATE_DIR="/run/gateway-secrets"
    COORDINATION_DIR="/var/lib/gateway-key-coordination"
    LOG_FILE="/var/log/gateway/key-coordination.log"

    mkdir -p "$STATE_DIR" "$COORDINATION_DIR" "$(dirname "$LOG_FILE")"

    log() {
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
    }

    # Initialize coordination for a key
    init_coordination() {
      local key_name="$1"
      local coordination_file="$COORDINATION_DIR/$key_name.coord"
      
      if [ ! -f "$coordination_file" ]; then
        echo "status=initiated" > "$coordination_file"
        echo "timestamp=$(date +%s)" >> "$coordination_file"
        echo "node=$(hostname)" >> "$coordination_file"
        log "Coordination initiated for key: $key_name"
      fi
    }

    # Check if coordination is required
    check_coordination_required() {
      local key_name="$1"
      local coordination_file="$COORDINATION_DIR/$key_name.coord"
      
      if [ -f "$coordination_file" ]; then
        local status=$(grep "status=" "$coordination_file" | cut -d= -f2)
        case "$status" in
          "initiated")
            log "Coordination in progress for key: $key_name"
            return 0
            ;;
          "completed")
            log "Coordination already completed for key: $key_name"
            return 1
            ;;
          *)
            log "Unknown coordination status for key: $key_name: $status"
            return 1
            ;;
        esac
      fi
      return 1
    }

    # Mark coordination as completed
    complete_coordination() {
      local key_name="$1"
      local coordination_file="$COORDINATION_DIR/$key_name.coord"
      
      echo "status=completed" > "$coordination_file"
      echo "timestamp=$(date +%s)" >> "$coordination_file"
      echo "node=$(hostname)" >> "$coordination_file"
      log "Coordination completed for key: $key_name"
    }

    # Notify peers of key change
    notify_peers() {
      local key_name="$1"
      local new_public_key="$2"
      local peers="$3"
      
      log "Notifying peers of key change for: $key_name"
      
      for peer in $peers; do
        log "Sending notification to peer: $peer"
        # This would implement actual peer notification
        # Could use SSH, API calls, message queue, etc.
        echo "New public key for $key_name: $new_public_key" | \
          ssh "$peer" "cat > /tmp/key-update-$key_name.pub" || \
          log "WARNING: Failed to notify peer: $peer"
      done
    }

    # Main coordination logic
    main() {
      local action="$1"
      local key_name="$2"
      shift 2
      
      case "$action" in
        "init")
          init_coordination "$key_name"
          ;;
        "check")
          check_coordination_required "$key_name"
          ;;
        "complete")
          complete_coordination "$key_name"
          ;;
        "notify")
          if [ $# -lt 2 ]; then
            echo "Usage: $0 notify <key_name> <new_public_key> <peer1> [peer2...]"
            exit 1
          fi
          local new_public_key="$1"
          shift
          notify_peers "$key_name" "$new_public_key" "$@"
          ;;
        *)
          echo "Usage: $0 {init|check|complete|notify} <key_name> [args...]"
          exit 1
          ;;
      esac
    }

    main "$@"
  '';

  # Enhanced key rotation with coordination
  enhancedKeyRotation =
    keyName: keyConfig:
    let
      baseScript = processedKeys.scripts.${keyName};
      coordinationRequired = keyConfig.coordinationRequired or false;
      peerNotification = keyConfig.peerNotification or false;
      peers = keyConfig.peers or [ ];
    in
    ''
      #!/bin/sh
      set -e

      KEY_NAME="${keyName}"
      KEY_TYPE="${keyConfig.type}"
      COORDINATION_REQUIRED=${if coordinationRequired then "true" else "false"}
      PEER_NOTIFICATION=${if peerNotification then "true" else "false"}
      PEERS="${concatMapStringsSep " " (p: "\"${p}\"") peers}"

      STATE_DIR="/run/gateway-secrets"
      COORDINATION_SCRIPT="${keyCoordination}"
      LOG_FILE="/var/log/gateway/enhanced-key-rotation.log"

      mkdir -p "$(dirname "$LOG_FILE")"

      log() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
      }

      # Enhanced coordination logic
      coordinate_rotation() {
        if [ "$COORDINATION_REQUIRED" = "true" ]; then
          log "Initiating coordination for key rotation: $KEY_NAME"
          
          # Initialize coordination
          if ! "$COORDINATION_SCRIPT" init "$KEY_NAME"; then
            log "ERROR: Failed to initialize coordination for $KEY_NAME"
            return 1
          fi
          
          # Check if coordination is still required
          if ! "$COORDINATION_SCRIPT" check "$KEY_NAME"; then
            log "Coordination not required or already completed for $KEY_NAME"
            return 0
          fi
          
          log "Coordination check passed for $KEY_NAME"
        fi
        return 0
      }

      # Enhanced peer notification
      notify_peers_of_change() {
        if [ "$PEER_NOTIFICATION" = "true" ] && [ -n "$PEERS" ]; then
          local public_key_file="$STATE_DIR/$KEY_NAME.public"
          
          if [ -f "$public_key_file" ]; then
            local new_public_key=$(cat "$public_key_file")
            log "Notifying peers of key change for $KEY_NAME"
            
            # Split peers string and pass to coordination script
            eval "$COORDINATION_SCRIPT notify \"$KEY_NAME\" \"$new_public_key\" $PEERS" || \
              log "WARNING: Failed to notify some peers for $KEY_NAME"
          else
            log "WARNING: No public key file found for peer notification: $KEY_NAME"
          fi
        fi
      }

      # Enhanced validation with coordination
      validate_with_coordination() {
        local validation_result=$?
        
        if [ $validation_result -eq 0 ]; then
          # Rotation successful - complete coordination
          if [ "$COORDINATION_REQUIRED" = "true" ]; then
            "$COORDINATION_SCRIPT" complete "$KEY_NAME" || \
              log "WARNING: Failed to complete coordination for $KEY_NAME"
          fi
          
          # Notify peers
          notify_peers_of_change
        else
          log "ERROR: Key rotation validation failed for $KEY_NAME"
          return 1
        fi
        
        return $validation_result
      }

      # Main enhanced rotation logic
      main() {
        log "Starting enhanced key rotation for $KEY_NAME (type: $KEY_TYPE)"
        
        # Coordinate with other systems if required
        if ! coordinate_rotation; then
          log "ERROR: Coordination failed for $KEY_NAME"
          exit 1
        fi
        
        # Run base rotation script
        log "Executing base rotation script for $KEY_NAME"
        if ! ${baseScript}; then
          log "ERROR: Base rotation script failed for $KEY_NAME"
          exit 1
        fi
        
        # Validate and complete coordination
        if ! validate_with_coordination; then
          log "ERROR: Validation or coordination failed for $KEY_NAME"
          exit 1
        fi
        
        log "Enhanced key rotation completed successfully for $KEY_NAME"
      }

      main "$@"
    '';

in
{
  options.services.gateway.secretRotation = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable secret rotation automation";
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

            peers = mkOption {
              type = types.listOf types.str;
              description = "List of peer systems to notify";
              default = [ ];
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

            # Enhanced options for specific key types
            interface = mkOption {
              type = types.nullOr types.str;
              description = "Network interface (for WireGuard keys)";
              default = null;
            };

            algorithm = mkOption {
              type = types.str;
              description = "Algorithm (for TSIG keys)";
              default = "hmac-sha256";
            };

            keySize = mkOption {
              type = types.int;
              description = "Key size in bits";
              default = 256;
            };

            serviceName = mkOption {
              type = types.nullOr types.str;
              description = "Service name (for API keys)";
              default = null;
            };

            updateCommand = mkOption {
              type = types.nullOr types.str;
              description = "Custom command to run after key update";
              default = null;
            };
          };
        }
      );
      description = "Enhanced key rotation configuration";
      default = { };
    };
  };

  config = mkIf cfg.enable {
    # Enhanced key rotation systemd services
    systemd.services = {
      # Key coordination service
      gateway-key-coordination =
        mkIf (builtins.any (key: key.coordinationRequired or false) (builtins.attrValues keyRotations))
          {
            description = "Gateway key coordination service";
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];
            path = with pkgs; [
              coreutils
              openssh
            ];
            serviceConfig = {
              Type = "oneshot";
              ExecStart = pkgs.writeScript "gateway-key-coordination-init.sh" ''
                #!/bin/sh
                set -e

                COORDINATION_DIR="/var/lib/gateway-key-coordination"
                LOG_FILE="/var/log/gateway/key-coordination.log"

                mkdir -p "$COORDINATION_DIR" "$(dirname "$LOG_FILE")"

                log() {
                  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
                }

                log "Initializing key coordination service"

                ${lib.concatMapStringsSep "\n" (
                  keyName:
                  let
                    keyConfig = keyRotations.${keyName};
                  in
                  lib.mkIf (keyConfig.coordinationRequired or false) ''
                    log "Setting up coordination for key: ${keyName}"
                    # Initialize coordination state
                    echo "status=ready" > "$COORDINATION_DIR/${keyName}.coord"
                    echo "timestamp=$(date +%s)" >> "$COORDINATION_DIR/${keyName}.coord"
                    echo "node=$(hostname)" >> "$COORDINATION_DIR/${keyName}.coord"
                  ''
                ) (builtins.attrNames keyRotations)}

                log "Key coordination service initialized"
              '';
              User = "root";
              Group = "root";
              PrivateTmp = true;
              ProtectSystem = "strict";
              ReadWritePaths = [
                "/var/lib/gateway-key-coordination"
                "/var/log/gateway"
              ];
            };
          };

      # Enhanced key rotation service
      gateway-enhanced-key-rotation = mkIf (keyRotations != { }) {
        description = "Gateway enhanced key rotation service";
        after = [
          "network-online.target"
          "gateway-key-coordination.service"
        ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeScript "gateway-enhanced-key-rotation.sh" ''
            #!/bin/sh
            set -e

            LOG_FILE="/var/log/gateway/enhanced-key-rotation.log"
            STATE_DIR="/run/gateway-secrets"

            mkdir -p "$(dirname "$LOG_FILE")" "$STATE_DIR"

            log() {
              echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
            }

            log "Starting enhanced key rotation check"

            ${lib.concatMapStringsSep "\n" (
              keyName:
              let
                keyConfig = keyRotations.${keyName};
                enhancedScript = enhancedKeyRotation keyName keyConfig;
              in
              ''
                log "Checking enhanced key rotation for ${keyName}"
                if ! ${enhancedScript}; then
                  log "ERROR: Enhanced key rotation failed for ${keyName}"
                else
                  log "Enhanced key rotation completed for ${keyName}"
                fi
              ''
            ) (builtins.attrNames keyRotations)}

            log "Enhanced key rotation check completed"
          '';
          User = "root";
          Group = "root";
          PrivateTmp = true;
          ProtectSystem = "strict";
          ReadWritePaths = [
            "/run/gateway-secrets"
            "/var/backups/gateway-secrets"
            "/var/log/gateway"
            "/var/lib/gateway-key-coordination"
            "/etc/wireguard"
            "/etc/knot"
          ];
        };
      };
    };

    # Enhanced key rotation timers
    systemd.timers = {
      gateway-enhanced-key-rotation = mkIf (keyRotations != { }) {
        description = "Timer for enhanced key rotation";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "weekly";
          Persistent = true;
          RandomizedDelaySec = "6h";
        };
      };
    };

    # Ensure coordination directory exists
    systemd.tmpfiles.rules = [
      "d /var/lib/gateway-key-coordination 0755 root root - -"
    ];

    # Log rotation for enhanced key rotation logs
    services.logrotate.settings.gateway-enhanced-key-rotation = {
      files = [
        "/var/log/gateway/enhanced-key-rotation.log"
        "/var/log/gateway/key-coordination.log"
      ];
      frequency = "weekly";
      rotate = 4;
      compress = true;
      delaycompress = true;
      missingok = true;
      notifempty = true;
      create = "644 root root";
    };

    # Add enhanced key rotation scripts to runtime directory
    systemd.services.gateway-enhanced-key-rotation-setup = mkIf (keyRotations != { }) {
      description = "Setup enhanced key rotation scripts";
      wantedBy = [ "multi-user.target" ];
      before = [ "gateway-enhanced-key-rotation.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        mkdir -p /run/gateway-secrets

        ${lib.concatMapStringsSep "\n" (keyName: ''
            # Deploy enhanced key rotation script for ${keyName}
            cat > /run/gateway-secrets/${keyName}-enhanced-rotate.sh << 'EOF'
          ${enhancedKeyRotation keyName keyRotations.${keyName}}
          EOF
            chmod +x /run/gateway-secrets/${keyName}-enhanced-rotate.sh
        '') (builtins.attrNames keyRotations)}

        # Deploy coordination script
        cp ${keyCoordination} /run/gateway-secrets/key-coordination.sh
        chmod +x /run/gateway-secrets/key-coordination.sh
      '';
    };
  };
}

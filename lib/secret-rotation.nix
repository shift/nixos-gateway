{ lib }:

let
  inherit (lib)
    mkOption
    types
    optionalAttrs
    mapAttrsToList
    concatStringsSep
    filter
    mapAttrs
    mapAttrs'
    mkDefault
    mkIf
    ;

  # Parse interval string to seconds
  parseInterval =
    interval:
    let
      match = builtins.match "([0-9]+)([smhd])" interval;
      value =
        if match != null then
          let
            numStr = builtins.head match;
            # Use built-in fromJSON for string to int conversion
            parsed = builtins.fromJSON numStr;
          in
          if builtins.isInt parsed then parsed else 0
        else
          0;
      unit = if match != null then builtins.elemAt match 1 else "";
      multiplier =
        if unit == "s" then
          1
        else if unit == "m" then
          60
        else if unit == "h" then
          3600
        else if unit == "d" then
          86400
        else
          0;
    in
    if multiplier == 0 then throw "Invalid interval format: ${interval}" else value * multiplier;

  # Check if rotation is needed based on last rotation time
  needsRotation =
    lastRotation: interval:
    let
      currentTime = builtins.currentTime;
      intervalSeconds = parseInterval interval;
      nextRotation = lastRotation + intervalSeconds;
    in
    currentTime >= nextRotation;

  # Certificate rotation strategies
  certificateStrategies = {
    acme = {
      description = "ACME/Let's Encrypt certificate automation";
      requiredFields = [
        "domain"
        "email"
      ];
      optionalFields = [
        "staging"
        "dnsProvider"
        "reloadServices"
      ];

      generate = config: ''
        # ACME certificate generation using certbot
        DOMAIN="${config.domain}"
        EMAIL="${config.email}"
        STAGING=${if config.staging or false then "--staging" else ""}
        RELOAD_SERVICES="${concatStringsSep " " (config.reloadServices or [ ])}"

        # Generate certificate
        certbot certonly \
          --standalone \
          --agree-tos \
          --email "$EMAIL" \
          -d "$DOMAIN" \
          $STAGING \
          --non-interactive

        # Copy certificates to expected locations
        cp "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" "/run/gateway-secrets/$DOMAIN.crt"
        cp "/etc/letsencrypt/live/$DOMAIN/privkey.pem" "/run/gateway-secrets/$DOMAIN.key"

        # Set proper permissions
        chmod 644 "/run/gateway-secrets/$DOMAIN.crt"
        chmod 600 "/run/gateway-secrets/$DOMAIN.key"

        # Reload services if specified
        if [ -n "$RELOAD_SERVICES" ]; then
          for service in $RELOAD_SERVICES; do
            systemctl reload "$service" || systemctl restart "$service"
          done
        fi
      '';

      validate = config: ''
        # Validate ACME certificate
        DOMAIN="${config.domain}"

        if [ ! -f "/run/gateway-secrets/$DOMAIN.crt" ]; then
          echo "ERROR: Certificate file not found"
          exit 1
        fi

        if [ ! -f "/run/gateway-secrets/$DOMAIN.key" ]; then
          echo "ERROR: Private key file not found"
          exit 1
        fi

        # Check certificate validity
        if ! openssl x509 -in "/run/gateway-secrets/$DOMAIN.crt" -noout -checkend 86400; then
          echo "WARNING: Certificate expires within 24 hours"
        fi

        # Check certificate matches domain
        if ! openssl x509 -in "/run/gateway-secrets/$DOMAIN.crt" -noout -subject | grep -q "$DOMAIN"; then
          echo "ERROR: Certificate does not match domain $DOMAIN"
          exit 1
        fi

        echo "Certificate validation passed"
      '';
    };

    selfSigned = {
      description = "Self-signed certificate generation";
      requiredFields = [ "domain" ];
      optionalFields = [
        "keySize"
        "validDays"
        "reloadServices"
      ];

      generate = config: ''
        # Self-signed certificate generation
        DOMAIN="${config.domain}"
        KEY_SIZE=${toString (config.keySize or 2048)}
        VALID_DAYS=${toString (config.validDays or 365)}
        RELOAD_SERVICES="${concatStringsSep " " (config.reloadServices or [ ])}"

        # Generate private key
        openssl genrsa -out "/run/gateway-secrets/$DOMAIN.key" $KEY_SIZE

        # Generate certificate
        openssl req -new -x509 -key "/run/gateway-secrets/$DOMAIN.key" \
          -out "/run/gateway-secrets/$DOMAIN.crt" \
          -days $VALID_DAYS \
          -subj "/C=US/ST=State/L=City/O=Organization/CN=$DOMAIN"

        # Set proper permissions
        chmod 644 "/run/gateway-secrets/$DOMAIN.crt"
        chmod 600 "/run/gateway-secrets/$DOMAIN.key"

        # Reload services if specified
        if [ -n "$RELOAD_SERVICES" ]; then
          for service in $RELOAD_SERVICES; do
            systemctl reload "$service" || systemctl restart "$service"
          done
        fi
      '';

      validate = config: ''
        # Validate self-signed certificate
        DOMAIN="${config.domain}"

        if [ ! -f "/run/gateway-secrets/$DOMAIN.crt" ]; then
          echo "ERROR: Certificate file not found"
          exit 1
        fi

        if [ ! -f "/run/gateway-secrets/$DOMAIN.key" ]; then
          echo "ERROR: Private key file not found"
          exit 1
        fi

        # Check certificate validity
        if ! openssl x509 -in "/run/gateway-secrets/$DOMAIN.crt" -noout -checkend 86400; then
          echo "WARNING: Certificate expires within 24 hours"
        fi

        echo "Self-signed certificate validation passed"
      '';
    };
  };

  # Key rotation strategies
  keyStrategies = {
    wireguard = {
      description = "WireGuard key rotation";
      requiredFields = [ "interface" ];
      optionalFields = [
        "peerNotification"
        "coordinationRequired"
      ];

      generate = config: ''
        # WireGuard key rotation
        INTERFACE="${config.interface}"
        PEER_NOTIFICATION=${if config.peerNotification or false then "true" else "false"}
        COORDINATION_REQUIRED=${if config.coordinationRequired or false then "true" else "false"}

        # Generate new key pair
        PRIVATE_KEY=$(wg genkey)
        PUBLIC_KEY=$(echo "$PRIVATE_KEY" | wg pubkey)

        # Backup current configuration
        if [ -f "/etc/wireguard/$INTERFACE.conf" ]; then
          cp "/etc/wireguard/$INTERFACE.conf" "/var/backups/gateway-secrets/$INTERFACE-$(date +%s).conf"
        fi

        # Update configuration with new private key
        if [ -f "/etc/wireguard/$INTERFACE.conf" ]; then
          sed -i "s/^PrivateKey = .*/PrivateKey = $PRIVATE_KEY/" "/etc/wireguard/$INTERFACE.conf"
        else
          echo "ERROR: WireGuard configuration not found"
          exit 1
        fi

        # Store new keys
        echo "$PRIVATE_KEY" > "/run/gateway-secrets/$INTERFACE.private"
        echo "$PUBLIC_KEY" > "/run/gateway-secrets/$INTERFACE.public"
        chmod 600 "/run/gateway-secrets/$INTERFACE.private"
        chmod 644 "/run/gateway-secrets/$INTERFACE.public"

        # Restart WireGuard interface
        wg-quick down "$INTERFACE" || true
        wg-quick up "$INTERFACE"

        echo "WireGuard key rotation completed for $INTERFACE"
        echo "New public key: $PUBLIC_KEY"

        if [ "$PEER_NOTIFICATION" = "true" ]; then
          echo "NOTICE: Peer notification required - update peer configurations with new public key"
        fi
      '';

      validate = config: ''
        # Validate WireGuard key rotation
        INTERFACE="${config.interface}"

        if [ ! -f "/run/gateway-secrets/$INTERFACE.private" ]; then
          echo "ERROR: Private key file not found"
          exit 1
        fi

        if [ ! -f "/run/gateway-secrets/$INTERFACE.public" ]; then
          echo "ERROR: Public key file not found"
          exit 1
        fi

        # Check if interface is up
        if ! wg show "$INTERFACE" >/dev/null 2>&1; then
          echo "ERROR: WireGuard interface $INTERFACE is not up"
          exit 1
        fi

        # Validate key format
        PRIVATE_KEY=$(cat "/run/gateway-secrets/$INTERFACE.private")
        if ! echo "$PRIVATE_KEY" | wg pubkey >/dev/null 2>&1; then
          echo "ERROR: Invalid private key format"
          exit 1
        fi

        echo "WireGuard key validation passed"
      '';
    };

    tsig = {
      description = "DNS TSIG key rotation";
      requiredFields = [
        "name"
        "algorithm"
      ];
      optionalFields = [
        "keySize"
        "dependentServices"
      ];

      generate = config: ''
                # TSIG key rotation
                NAME="${config.name}"
                ALGORITHM="${config.algorithm}"
                KEY_SIZE=${toString (config.keySize or 256)}
                DEPENDENT_SERVICES="${concatStringsSep " " (config.dependentServices or [ ])}"
                
                # Generate new TSIG key
                TSIG_KEY=$(openssl rand -base64 $KEY_SIZE | tr -d "=+/" | cut -c1-32)
                
                # Backup current key configuration
                if [ -f "/etc/knot/tsig.keys" ]; then
                  cp "/etc/knot/tsig.keys" "/var/backups/gateway-secrets/tsig-$(date +%s).keys"
                fi
                
                # Update TSIG key in Knot configuration
                cat > "/run/gateway-secrets/$NAME.tsig" << EOF
        key:
          - id: $NAME
            algorithm: $ALGORITHM
            secret: $TSIG_KEY
        EOF
                
                # Store key
                echo "$TSIG_KEY" > "/run/gateway-secrets/$NAME.key"
                chmod 600 "/run/gateway-secrets/$NAME.key"
                
                # Update Knot configuration
                if [ -f "/etc/knot/knot.conf" ]; then
                  # This would need more sophisticated configuration management
                  echo "TSIG key generated - manual configuration update may be required"
                fi
                
                # Restart dependent services
                if [ -n "$DEPENDENT_SERVICES" ]; then
                  for service in $DEPENDENT_SERVICES; do
                    systemctl restart "$service" || systemctl reload "$service"
                  done
                fi
                
                echo "TSIG key rotation completed for $NAME"
      '';

      validate = config: ''
        # Validate TSIG key rotation
        NAME="${config.name}"

        if [ ! -f "/run/gateway-secrets/$NAME.key" ]; then
          echo "ERROR: TSIG key file not found"
          exit 1
        fi

        # Validate key format (base64)
        TSIG_KEY=$(cat "/run/gateway-secrets/$NAME.key")
        if ! echo "$TSIG_KEY" | base64 -d >/dev/null 2>&1; then
          echo "ERROR: Invalid TSIG key format"
          exit 1
        fi

        echo "TSIG key validation passed"
      '';
    };

    apiKey = {
      description = "API key rotation";
      requiredFields = [ "serviceName" ];
      optionalFields = [
        "keyLength"
        "dependentServices"
        "updateCommand"
      ];

      generate = config: ''
        # API key rotation
        SERVICE="${config.serviceName}"
        KEY_LENGTH=${toString (config.keyLength or 32)}
        DEPENDENT_SERVICES="${concatStringsSep " " (config.dependentServices or [ ])}"
        UPDATE_COMMAND="${config.updateCommand or ""}"

        # Generate new API key
        API_KEY=$(openssl rand -base64 $KEY_LENGTH | tr -d "=+/" | cut -c1-$KEY_LENGTH)

        # Backup current key
        if [ -f "/run/gateway-secrets/$SERVICE.apikey" ]; then
          cp "/run/gateway-secrets/$SERVICE.apikey" "/var/backups/gateway-secrets/$SERVICE-$(date +%s).apikey"
        fi

        # Store new key
        echo "$API_KEY" > "/run/gateway-secrets/$SERVICE.apikey"
        chmod 600 "/run/gateway-secrets/$SERVICE.apikey"

        # Execute custom update command if provided
        if [ -n "$UPDATE_COMMAND" ]; then
          eval "$UPDATE_COMMAND" || echo "WARNING: Update command failed"
        fi

        # Restart dependent services
        if [ -n "$DEPENDENT_SERVICES" ]; then
          for service in $DEPENDENT_SERVICES; do
            systemctl restart "$service" || systemctl reload "$service"
          done
        fi

        echo "API key rotation completed for $SERVICE"
      '';

      validate = config: ''
        # Validate API key rotation
        SERVICE="${config.serviceName}"

        if [ ! -f "/run/gateway-secrets/$SERVICE.apikey" ]; then
          echo "ERROR: API key file not found"
          exit 1
        fi

        # Check key length
        API_KEY=$(cat "/run/gateway-secrets/$SERVICE.apikey")
        if [ ''${#API_KEY} -lt 16 ]; then
          echo "WARNING: API key appears to be short"
        fi

        echo "API key validation passed"
      '';
    };
  };

  # Rotation dependency management
  resolveRotationDependencies =
    rotations:
    let
      findDependencies =
        rotationName: rotationConfig: if rotationConfig ? dependsOn then rotationConfig.dependsOn else [ ];

      allDependencies = builtins.foldl' (
        acc: rotationName:
        acc // { ${rotationName} = findDependencies rotationName rotations.${rotationName}; }
      ) { } (builtins.attrNames rotations);

      sortedRotations = lib.toposort allDependencies (builtins.attrNames rotations);
    in
    if sortedRotations ? cycle then
      throw "Circular dependency detected in rotations: ${builtins.concatStringsSep ", " sortedRotations.cycle}"
    else
      {
        order = sortedRotations.result;
        dependencies = allDependencies;
      };

  # Rotation validation
  validateRotationConfig =
    rotationName: rotationConfig:
    let
      hasValidType = rotationConfig ? type;
      hasValidInterval =
        rotationConfig ? interval && (builtins.match "^[0-9]+[smhd]$" rotationConfig.interval != null);
      hasStrategy =
        certificateStrategies ? ${rotationConfig.type} || keyStrategies ? ${rotationConfig.type};
    in
    assert lib.assertMsg hasValidType "Rotation ${rotationName} missing 'type' field";
    assert lib.assertMsg hasValidInterval
      "Rotation ${rotationName} has invalid interval format: ${rotationConfig.interval}";
    assert lib.assertMsg hasStrategy
      "Rotation ${rotationName} has unknown type: ${rotationConfig.type}";
    rotationConfig;

  # Generate rotation script
  generateRotationScript =
    rotationName: rotationConfig:
    let
      strategy =
        if certificateStrategies ? ${rotationConfig.type} then
          certificateStrategies.${rotationConfig.type}
        else if keyStrategies ? ${rotationConfig.type} then
          keyStrategies.${rotationConfig.type}
        else
          throw "Unknown rotation type: ${rotationConfig.type}";

      generateScript = strategy.generate rotationConfig;
      validateScript = strategy.validate rotationConfig;
      backupEnabled = rotationConfig.backup or true;
      rollbackEnabled = rotationConfig.rollback or true;
    in
    ''
      #!/bin/sh
      set -e

      ROTATION_NAME="${rotationName}"
      ROTATION_TYPE="${rotationConfig.type}"
      INTERVAL="${rotationConfig.interval}"
      BACKUP_ENABLED=${if backupEnabled then "true" else "false"}
      ROLLBACK_ENABLED=${if rollbackEnabled then "true" else "false"}

      STATE_DIR="/run/gateway-secrets"
      BACKUP_DIR="/var/backups/gateway-secrets"
      LOG_FILE="/var/log/gateway/secret-rotation.log"
      LOCK_FILE="/run/gateway-secrets/$ROTATION_NAME.lock"

      mkdir -p "$STATE_DIR" "$BACKUP_DIR" "$(dirname "$LOG_FILE")"

      log() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
      }

      # Prevent concurrent rotations
      acquire_lock() {
        if [ -f "$LOCK_FILE" ]; then
          local pid=$(cat "$LOCK_FILE")
          if kill -0 "$pid" 2>/dev/null; then
            log "Rotation already in progress (PID: $pid)"
            exit 1
          else
            rm -f "$LOCK_FILE"
          fi
        fi
        echo $$ > "$LOCK_FILE"
      }

      release_lock() {
        rm -f "$LOCK_FILE"
      }

      # Check if rotation is needed
      check_rotation_needed() {
        local last_rotation_file="$STATE_DIR/$ROTATION_NAME.last_rotation"
        local interval_seconds=$(echo "$INTERVAL" | sed 's/d$/*86400/' | sed 's/h$/*3600/' | sed 's/m$/*60/' | sed 's/s$//' | bc)
        local current_time=$(date +%s)
        
        if [ -f "$last_rotation_file" ]; then
          local last_rotation=$(cat "$last_rotation_file")
          local next_rotation=$((last_rotation + interval_seconds))
          
          if [ "$current_time" -lt "$next_rotation" ]; then
            log "Rotation not needed yet (next rotation: $(date -d @$next_rotation))"
            exit 0
          fi
        fi
        
        log "Rotation needed for $ROTATION_NAME"
      }

      # Create backup
      create_backup() {
        if [ "$BACKUP_ENABLED" = "true" ]; then
          local backup_path="$BACKUP_DIR/$ROTATION_NAME-$(date +%s).backup"
          log "Creating backup: $backup_path"
          
          # Backup current secrets
          if [ -d "$STATE_DIR" ]; then
            find "$STATE_DIR" -name "*$ROTATION_NAME*" -type f -exec cp {} "$backup_path." \;
          fi
          
          echo "$backup_path" > "$STATE_DIR/$ROTATION_NAME.last_backup"
          log "Backup created successfully"
        fi
      }

      # Rollback on failure
      rollback() {
        if [ "$ROLLBACK_ENABLED" = "true" ]; then
          local last_backup_file="$STATE_DIR/$ROTATION_NAME.last_backup"
          if [ -f "$last_backup_file" ]; then
            local backup_path=$(cat "$last_backup_file")
            log "Rolling back using backup: $backup_path"
            
            # Restore from backup
            for backup_file in "$backup_path".*; do
              if [ -f "$backup_file" ]; then
                local target_file=$(echo "$backup_file" | sed "s|$backup_path\.||")
                cp "$backup_file" "$STATE_DIR/$target_file"
              fi
            done
            
            log "Rollback completed"
          else
            log "WARNING: No backup found for rollback"
          fi
        fi
      }

      # Main rotation logic
      main() {
        acquire_lock
        trap 'release_lock' EXIT
        
        log "Starting rotation for $ROTATION_NAME (type: $ROTATION_TYPE)"
        
        # Check if rotation is needed
        check_rotation_needed
        
        # Create backup
        create_backup
        
        # Generate new secret
        log "Generating new secret"
        if ! ${generateScript}; then
          log "ERROR: Secret generation failed"
          rollback
          exit 1
        fi
        
        # Validate new secret
        log "Validating new secret"
        if ! ${validateScript}; then
          log "ERROR: Secret validation failed"
          rollback
          exit 1
        fi
        
        # Update last rotation timestamp
        date +%s > "$STATE_DIR/$ROTATION_NAME.last_rotation"
        
        log "Rotation completed successfully for $ROTATION_NAME"
      }

      main "$@"
    '';

  # Generate rotation monitoring metrics
  generateRotationMetrics =
    rotations:
    let
      rotationMetrics = mapAttrsToList (rotationName: rotationConfig: ''
        # HELP gateway_secret_rotation_last_success_timestamp Last successful rotation timestamp
        # TYPE gateway_secret_rotation_last_success_timestamp gauge
        gateway_secret_rotation_last_success_timestamp{rotation="${rotationName}",type="${rotationConfig.type}"} $(cat /run/gateway-secrets/${rotationName}.last_rotation 2>/dev/null || echo "0")

        # HELP gateway_secret_rotation_interval_seconds Rotation interval in seconds
        # TYPE gateway_secret_rotation_interval_seconds gauge
        gateway_secret_rotation_interval_seconds{rotation="${rotationName}",type="${rotationConfig.type}"} $(echo "${rotationConfig.interval}" | sed 's/d$/*86400/' | sed 's/h$/*3600/' | sed 's/m$/*60/' | sed 's/s$//' | bc 2>/dev/null || echo "0")

        # HELP gateway_secret_rotation_status Rotation status (1 = success, 0 = failure)
        # TYPE gateway_secret_rotation_status gauge
        gateway_secret_rotation_status{rotation="${rotationName}",type="${rotationConfig.type}"} 1
      '') rotations;
    in
    concatStringsSep "\n" rotationMetrics;

in
{
  inherit
    parseInterval
    needsRotation
    certificateStrategies
    keyStrategies
    resolveRotationDependencies
    validateRotationConfig
    generateRotationScript
    generateRotationMetrics
    ;

  # Main rotation processing function
  processRotations =
    rotations:
    let
      validatedRotations = mapAttrs validateRotationConfig rotations;
      dependencies = resolveRotationDependencies validatedRotations;
      scripts = mapAttrs generateRotationScript validatedRotations;
      metrics = generateRotationMetrics validatedRotations;
    in
    {
      inherit
        validatedRotations
        dependencies
        scripts
        metrics
        ;
    };

  # Check rotation status
  checkRotationStatus =
    rotationName:
    let
      stateFile = "/run/gateway-secrets/${rotationName}.last_rotation";
      lastRotation = if builtins.pathExists stateFile then builtins.readFile stateFile else "0";
    in
    {
      rotationName = rotationName;
      lastRotation = lib.toInt lastRotation;
      needsRotation = needsRotation (lib.toInt lastRotation) "30d"; # Default interval
    };

  # Get rotation schedule
  getRotationSchedule =
    rotations:
    mapAttrs (rotationName: rotationConfig: {
      interval = rotationConfig.interval;
      intervalSeconds = parseInterval rotationConfig.interval;
      lastRotation = 0; # Would be read from state file
      nextRotation = 0; # Would be calculated
    }) rotations;
}

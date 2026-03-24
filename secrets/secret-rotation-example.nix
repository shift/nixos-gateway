# Secret Rotation Example
# This file demonstrates how to implement automated secret rotation

{
  # Example NixOS configuration for secret rotation
  system = {
    # Enable secret rotation service
    systemd.services.gateway-secret-rotation = {
      description = "Gateway Secret Rotation Service";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "/run/gateway-secrets/rotate-secrets.sh";
        User = "root";
        Group = "root";
        PrivateTmp = true;
        ProtectSystem = "strict";
        ReadWritePaths = [
          "/var/backups/gateway-secrets"
          "/var/log/gateway"
          "/run/gateway-secrets"
        ];
      };
    };

    # Timer for automatic rotation
    systemd.timers.gateway-secret-rotation = {
      description = "Timer for gateway secret rotation";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
    };
  };

  # Example rotation script
  rotationScript = ''
    #!/bin/bash
    set -euo pipefail

    # Configuration
    BACKUP_DIR="/var/backups/gateway-secrets"
    LOG_FILE="/var/log/gateway/secret-rotation.log"
    SECRETS_DIR="/run/gateway-secrets"

    # Logging function
    log() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
    }

    # Function to rotate TLS certificate
    rotate_tls_certificate() {
        local secret_name="$1"
        local cert_file="$SECRETS_DIR/$secret_name.crt"
        local key_file="$SECRETS_DIR/$secret_name.key"
        
        log "Starting rotation for TLS certificate: $secret_name"
        
        # Check if certificate is expiring soon
        if command -v openssl >/dev/null 2>&1; then
            local expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2)
            local expiry_timestamp=$(date -d "$expiry_date" +%s 2>/dev/null || echo "0")
            local current_timestamp=$(date +%s)
            local days_until_expiry=$(( (expiry_timestamp - current_timestamp) / 86400 ))
            
            if [ "$days_until_expiry" -lt 30 ]; then
                log "Certificate expires in $days_until_expiry days, initiating rotation"
                
                # Create backup
                local backup_file="$BACKUP_DIR/$secret_name-$(date +%s).backup"
                cp "$cert_file" "$backup_file.cert"
                cp "$key_file" "$backup_file.key"
                log "Created backup: $backup_file"
                
                # Generate new certificate (placeholder - actual implementation would use ACME or PKI)
                log "Generating new certificate for $secret_name"
                # certbot certonly --standalone -d "$secret_name" --cert-name "$secret_name"
                
                # Update services that use the certificate
                log "Restarting services that use the certificate"
                systemctl reload nginx || true
                systemctl reload haproxy || true
                
                log "Certificate rotation completed for $secret_name"
            else
                log "Certificate is still valid for $days_until_expiry days, no rotation needed"
            fi
        else
            log "OpenSSL not available, cannot check certificate expiry"
        fi
    }

    # Function to rotate API keys
    rotate_api_key() {
        local secret_name="$1"
        local key_file="$SECRETS_DIR/$secret_name.apikey"
        
        log "Starting rotation for API key: $secret_name"
        
        # Check if key needs rotation (based on age or policy)
        local key_age=$(($(date +%s) - $(stat -c %Y "$key_file" 2>/dev/null || echo "0")))
        local max_age=$(( 90 * 24 * 3600 ))  # 90 days
        
        if [ "$key_age" -gt "$max_age" ]; then
            log "API key is $(( key_age / 86400 )) days old, initiating rotation"
            
            # Create backup
            local backup_file="$BACKUP_DIR/$secret_name-$(date +%s).backup"
            cp "$key_file" "$backup_file"
            log "Created backup: $backup_file"
            
            # Generate new API key (placeholder - actual implementation would call the service API)
            log "Generating new API key for $secret_name"
            # new_key=$(generate_api_key "$secret_name")
            # echo "$new_key" > "$key_file"
            
            # Update service configurations
            log "Updating service configurations for $secret_name"
            # update_service_config "$secret_name" "$new_key"
            
            # Restart affected services
            log "Restarting services that use the API key"
            systemctl restart prometheus || true
            systemctl restart grafana || true
            
            log "API key rotation completed for $secret_name"
        else
            log "API key is $(( key_age / 86400 )) days old, no rotation needed"
        fi
    }

    # Function to rotate database passwords
    rotate_database_password() {
        local secret_name="$1"
        local password_file="$SECRETS_DIR/$secret_name.password"
        
        log "Starting rotation for database password: $secret_name"
        
        # Check if password needs rotation
        local password_age=$(($(date +%s) - $(stat -c %Y "$password_file" 2>/dev/null || echo "0")))
        local max_age=$(( 90 * 24 * 3600 ))  # 90 days
        
        if [ "$password_age" -gt "$max_age" ]; then
            log "Database password is $(( password_age / 86400 )) days old, initiating rotation"
            
            # Create backup
            local backup_file="$BACKUP_DIR/$secret_name-$(date +%s).backup"
            cp "$password_file" "$backup_file"
            log "Created backup: $backup_file"
            
            # Generate new password
            log "Generating new database password for $secret_name"
            new_password=$(openssl rand -base64 32)
            echo "$new_password" > "$password_file"
            chmod 600 "$password_file"
            
            # Update database password
            log "Updating database password for $secret_name"
            # psql -c "ALTER USER $secret_name PASSWORD '$new_password';" || true
            
            # Update application configurations
            log "Updating application configurations for $secret_name"
            # update_app_config "$secret_name" "$new_password"
            
            # Restart affected services
            log "Restarting services that use the database password"
            systemctl restart postgresql || true
            systemctl restart prometheus || true
            
            log "Database password rotation completed for $secret_name"
        else
            log "Database password is $(( password_age / 86400 )) days old, no rotation needed"
        fi
    }

    # Main rotation logic
    main() {
        log "Starting secret rotation check"
        
        # Ensure directories exist
        mkdir -p "$BACKUP_DIR" "$(dirname "$LOG_FILE")" "$SECRETS_DIR"
        
        # Rotate TLS certificates
        if [ -f "$SECRETS_DIR/gateway-cert.crt" ]; then
            rotate_tls_certificate "gateway-cert"
        fi
        
        # Rotate API keys
        if [ -f "$SECRETS_DIR/prometheus-remote.apikey" ]; then
            rotate_api_key "prometheus-remote"
        fi
        
        if [ -f "$SECRETS_DIR/grafana-admin.apikey" ]; then
            rotate_api_key "grafana-admin"
        fi
        
        # Rotate database passwords
        if [ -f "$SECRETS_DIR/metrics-db.password" ]; then
            rotate_database_password "metrics-db"
        fi
        
        if [ -f "$SECRETS_DIR/logs-db.password" ]; then
            rotate_database_password "logs-db"
        fi
        
        log "Secret rotation check completed"
    }

    # Run main function
    main "$@"
  '';
}

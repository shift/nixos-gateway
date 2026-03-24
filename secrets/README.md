# Gateway Secrets Management

This directory contains example configurations and documentation for managing secrets in the NixOS Gateway Configuration Framework.

## Overview

The secrets management system provides:

- **Encrypted storage** using agenix or sops-nix
- **Multiple secret types** (TLS certificates, API keys, database passwords, etc.)
- **Automatic rotation** with configurable intervals
- **Access control** with user and service permissions
- **Environment-specific secrets** for different deployment environments
- **Health monitoring** and backup capabilities
- **Audit logging** for compliance

## Supported Secret Types

### TLS Certificates (`tlsCertificate`)
- Certificate and private key files
- Automatic expiry checking
- Integration with web services (nginx, haproxy)

### WireGuard Keys (`wireguardKey`)
- Private keys and preshared keys
- VPN configuration integration
- Manual rotation support

### DNS TSIG Keys (`tsigKey`)
- Dynamic DNS update authentication
- Support for multiple algorithms (hmac-sha256, etc.)
- Integration with BIND/NSD

### API Keys (`apiKey`)
- Service authentication tokens
- Automatic rotation support
- Service-specific access control

### Database Passwords (`databasePassword`)
- Database credential management
- Integration with PostgreSQL/MySQL
- Secure password generation

## File Structure

```
secrets/
├── README.md                           # This file
├── gateway-secrets.nix                 # Agenix-based secrets configuration
├── gateway-secrets.yaml                # SOPS-based secrets configuration
├── environment-secrets.nix            # Environment-specific secrets
├── agenix-example.nix                 # Agenix setup example
├── sops-example.yaml                  # SOPS setup example
├── secret-rotation-example.nix        # Automated rotation example
├── agenix/                            # Agenix encrypted files
│   ├── gateway-secrets/
│   │   ├── tls/
│   │   ├── vpn/
│   │   ├── dns/
│   │   ├── monitoring/
│   │   └── databases/
│   └── .age-key                        # Age private key (protect this!)
├── sops/                              # SOPS encrypted files
│   ├── gateway-secrets.yaml
│   ├── development/
│   ├── staging/
│   ├── production/
│   └── testing/
└── backups/                           # Secret rotation backups
    ├── tls/
    ├── vpn/
    ├── dns/
    ├── monitoring/
    └── databases/
```

## Quick Start

### Using Agenix

1. **Install agenix:**
   ```bash
   nix-env -iA nixpkgs.agenix
   ```

2. **Generate age key pair:**
   ```bash
   agenix --keygen
   ```

3. **Configure secrets:**
   ```bash
   cp secrets/agenix-example.nix secrets/secrets.nix
   # Edit secrets.nix with your public keys
   ```

4. **Encrypt secrets:**
   ```bash
   agenix -e secrets/gateway-secrets.nix
   ```

5. **Deploy with NixOS:**
   ```nix
   {
     imports = [ ./secrets/gateway-secrets.nix ];
     
     services.gateway.secrets = {
       gateway-cert = {
         type = "tlsCertificate";
         certificate = ./agenix/gateway-secrets/tls/gateway.crt.age;
         private_key = ./agenix/gateway-secrets/tls/gateway.key.age;
       };
     };
   }
   ```

### Using SOPS

1. **Install sops:**
   ```bash
   nix-env -iA nixpkgs.sops
   ```

2. **Configure .sops.yaml:**
   ```bash
   cp secrets/sops-example.yaml .sops.yaml
   # Edit .sops.yaml with your keys
   ```

3. **Encrypt secrets:**
   ```bash
   sops --encrypt secrets/gateway-secrets.yaml > secrets/gateway-secrets.yaml.enc
   ```

4. **Deploy with NixOS:**
   ```nix
   {
     imports = [ <sops-nix/modules/sops> ];
     
     sops.defaultSopsFile = ./secrets/gateway-secrets.yaml.enc;
     
     services.gateway.secrets = {
       gateway-cert = {
         type = "tlsCertificate";
         certificate = config.sops.secrets.gateway-cert.path;
         private_key = config.sops.secrets.gateway-key.path;
       };
     };
   }
   ```

## Configuration Examples

### Basic Secret Configuration

```nix
services.gateway.secrets = {
  # TLS certificate
  gateway-cert = {
    type = "tlsCertificate";
    certificate = ./certs/gateway.crt.age;
    private_key = ./certs/gateway.key.age;
    
    rotation = {
      enabled = true;
      interval = "90d";
      backup = true;
    };
    
    access = {
      "root" = [ "read" "write" "delete" ];
      "nginx" = [ "read" ];
    };
  };
  
  # API key
  prometheus-api = {
    type = "apiKey";
    key = ./monitoring/prometheus.key.age;
    
    rotation = {
      enabled = true;
      interval = "60d";
      backup = true;
    };
    
    access = {
      "root" = [ "read" "write" "delete" ];
      "prometheus" = [ "read" ];
    };
  };
};
```

### Environment-Specific Secrets

```nix
# In your gateway configuration
services.gateway = {
  environment = "production";  # or "development", "staging", "testing"
  
  secrets = import ./secrets/environment-secrets.nix;
};
```

## Secret Rotation

The system supports automatic secret rotation with:

- **Configurable intervals** (e.g., "30d", "90d", "180d")
- **Backup creation** before rotation
- **Service restart** after rotation
- **Audit logging** of rotation events
- **Health monitoring** of rotated secrets

### Manual Rotation

```bash
# Rotate a specific secret
/run/gateway-secrets/gateway-cert-rotate.sh rotate

# Create backup only
/run/gateway-secrets/gateway-cert-rotate.sh backup
```

### Automatic Rotation

```nix
services.gateway.secrets.gateway-cert.rotation = {
  enabled = true;
  interval = "90d";  # Rotate every 90 days
  backup = true;     # Create backup before rotation
};
```

## Health Monitoring

Secret health is monitored automatically:

```bash
# Check all secrets
systemctl start gateway-secrets-health.service

# Check specific secret
/run/gateway-secrets/gateway-cert-health.sh

# View health status
cat /run/gateway-secrets/gateway-cert.health
```

## Access Control

Secrets support fine-grained access control:

```nix
services.gateway.secrets.gateway-cert.access = {
  "root" = [ "read" "write" "delete" ];     # Full access
  "nginx" = [ "read" ];                     # Read-only access
  "backup-service" = [ "read" "write" ];   # Backup access
};
```

## Security Best Practices

1. **Protect encryption keys:**
   - Store age private keys securely
   - Use hardware security modules when possible
   - Rotate encryption keys regularly

2. **Limit secret access:**
   - Use principle of least privilege
   - Separate secrets by environment
   - Audit access regularly

3. **Monitor secret health:**
   - Check certificate expiry
   - Monitor rotation logs
   - Set up alerts for failures

4. **Backup secrets:**
   - Enable automatic backups
   - Store backups securely
   - Test backup restoration

## Troubleshooting

### Common Issues

1. **Secret decryption fails:**
   - Check encryption keys are correct
   - Verify file permissions
   - Check sops/agenix configuration

2. **Health checks fail:**
   - Verify secret files exist and are readable
   - Check certificate expiry
   - Review service permissions

3. **Rotation fails:**
   - Check backup directory permissions
   - Verify service restart commands
   - Review rotation logs

### Debug Commands

```bash
# Check secret status
systemctl status gateway-secrets-setup.service
systemctl status gateway-secrets-health.service

# View logs
journalctl -u gateway-secrets-health.service
journalctl -u gateway-secrets-rotation.service

# Check file permissions
ls -la /run/gateway-secrets/
ls -la /var/backups/gateway-secrets/

# Test secret access
sudo -u nginx cat /run/gateway-secrets/gateway-cert.crt
```

## Integration with Other Modules

The secrets management system integrates with:

- **DNS module** (TSIG keys for dynamic updates)
- **VPN module** (WireGuard keys and preshared keys)
- **Monitoring module** (API keys for Prometheus/Grafana)
- **Security module** (TLS certificates for HTTPS services)
- **Database module** (Database credentials)

## Documentation

- [NixOS Gateway Framework](../README.md)
- [Task 07: Secrets Management Integration](../improvements/07-secrets-management-integration.md)
- [Agenix Documentation](https://github.com/ryantm/agenix)
- [SOPS Documentation](https://github.com/mozilla/sops)
- [sops-nix Documentation](https://github.com/Mic92/sops-nix)
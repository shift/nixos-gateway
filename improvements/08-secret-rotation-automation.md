# Secret Rotation Automation

**Status: Completed**

## Description
Implement automated secret rotation for certificates, keys, and other time-sensitive secrets with minimal service disruption.

## Requirements

### Current State
- Manual secret rotation required
- No automated certificate renewal
- Potential service interruptions during rotation

### Improvements Needed

#### 1. Rotation Framework
- Automated rotation scheduling
- Rotation dependency management
- Rollback mechanisms for failed rotations
- Rotation audit logging

#### 2. Certificate Management
- ACME/Let's Encrypt integration
- Certificate expiration monitoring
- Automatic certificate renewal
- Certificate chain validation

#### 3. Key Rotation
- TLS private key rotation
- VPN key rotation with peer coordination
- TSIG key rotation for DNS
- API key rotation with service updates

#### 4. Service Integration
- Graceful service reloads during rotation
- Zero-downtime rotation strategies
- Service-specific rotation procedures
- Rotation status monitoring

## Implementation Details

### Files to Create
- `lib/secret-rotation.nix` - Rotation framework
- `modules/certificate-manager.nix` - Certificate automation
- `modules/key-rotation.nix` - Key rotation management

### Rotation Configuration
```nix
services.gateway.secretRotation = {
  enable = true;
  
  certificates = {
    gateway = {
      domain = "gateway.example.com";
      email = "admin@example.com";
      renewBefore = "30d";
      reloadServices = [ "nginx" "knot" ];
    };
  };
  
  keys = {
    vpn = {
      rotationInterval = "90d";
      coordinationRequired = true;
      peerNotification = true;
    };
    
    dns = {
      rotationInterval = "180d";
      dependentServices = [ "kea-dhcp-ddns" "knot" ];
    };
  };
  
  monitoring = {
    expirationWarnings = [ "30d" "14d" "7d" "1d" ];
    alertOnFailure = true;
    rotationMetrics = true;
  };
};
```

### Integration Points
- ACME client integration
- Service reload coordination
- Monitoring and alerting
- Secret management integration

## Testing Requirements
- Rotation automation tests
- Certificate renewal tests
- Service continuity tests
- Failure scenario tests

## Dependencies
- 07-secrets-management-integration
- 03-service-health-checks

## Estimated Effort
- High (complex rotation coordination)
- 3 weeks implementation
- 2 weeks testing

## Success Criteria
- Certificates renewed automatically before expiration
- Zero-downtime key rotation
- Clear rotation status and alerts
- Automatic rollback on failures
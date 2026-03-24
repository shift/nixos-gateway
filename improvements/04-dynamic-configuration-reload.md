# Dynamic Configuration Reload

**Status: Completed**

## Description
Implement runtime configuration reload capabilities for gateway services without requiring full system rebuilds and reboots.

## Requirements

### Current State
- Configuration changes require full NixOS rebuild
- Service restarts needed for most changes
- No runtime configuration management

### Improvements Needed

#### 1. Hot Reload Support
- Identify services that support configuration reloading
- Implement configuration diff detection
- Create reload orchestration system
- Maintain service availability during reloads

#### 2. Service-Specific Reload
- **DNS**: Zone reloads, resolver configuration updates
- **DHCP**: Pool configuration changes, lease updates
- **Firewall**: Rule updates without connection loss
- **IDS**: Rule reloads, configuration changes
- **Network**: Interface configuration changes

#### 3. Configuration Validation
- Pre-reload configuration validation
- Rollback mechanisms for failed reloads
- Atomic configuration updates
- Service-specific validation rules

#### 4. Reload Management
- Reload scheduling and coordination
- Dependency-aware reload ordering
- Status tracking and reporting
- Integration with health checks

## Implementation Details

### Files to Create
- `lib/config-reload.nix` - Reload framework
- `modules/config-manager.nix` - Configuration management service

### Reload Capabilities
```nix
reloadCapabilities = {
  dns = {
    supportsReload = true;
    reloadCommand = "systemctl reload knot";
    validationCommand = "knotc conf-check";
  };
  dhcp = {
    supportsReload = true;
    reloadCommand = "systemctl reload kea-dhcp4-server";
    validationCommand = "kea-dhcp4 -t /etc/kea/dhcp4-server.conf";
  };
  firewall = {
    supportsReload = true;
    reloadCommand = "nft -f /etc/nftables.conf";
    validationCommand = "nft -c /etc/nftables.conf";
  };
};
```

### Integration Points
- Configuration file watching
- systemd integration for reloads
- Management UI for configuration changes
- Audit logging for configuration changes

## Testing Requirements
- Reload functionality tests for each service
- Configuration validation tests
- Rollback mechanism tests
- Service availability during reloads

## Dependencies
- 03-service-health-checks

## Estimated Effort
- High (complex reload orchestration)
- 3 weeks implementation
- 2 weeks testing

## Success Criteria
- Configuration changes applied without service downtime
- Failed reloads automatically rolled back
- Clear reload status reporting
- No data loss during reloads
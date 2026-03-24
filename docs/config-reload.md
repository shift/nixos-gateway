# Dynamic Configuration Reload

This document describes the dynamic configuration reload capabilities of the NixOS Gateway Configuration Framework.

## Overview

The dynamic configuration reload system allows runtime configuration changes to gateway services without requiring full system rebuilds and reboots. This feature provides:

- **Hot Reload Support**: Configuration changes applied without service downtime
- **Change Detection**: Automatic detection of configuration file modifications
- **Validation**: Pre-reload configuration validation with rollback on failure
- **Coordination**: Dependency-aware reload ordering for service consistency
- **Backup**: Automatic configuration backups with rollback capabilities

## Supported Services

### DNS (Knot)
- **Reload Support**: ✅ Full support
- **Config Files**: `/var/lib/knot/knotd.conf`, `/var/lib/knot/zones/*`
- **Validation**: `knotc conf-check`
- **Reload Command**: `systemctl reload knot`
- **Dependencies**: None

### DHCP (Kea)
- **Reload Support**: ✅ Full support
- **Config Files**: `/etc/kea/dhcp4-server.conf`, `/etc/kea/dhcp6-server.conf`
- **Validation**: `kea-dhcp4 -t /etc/kea/dhcp4-server.conf`
- **Reload Command**: `systemctl reload kea-dhcp4-server kea-dhcp6-server`
- **Dependencies**: DNS

### Firewall (nftables)
- **Reload Support**: ✅ Full support
- **Config Files**: `/etc/nftables.conf`
- **Validation**: `nft -c /etc/nftables.conf`
- **Reload Command**: `nft -f /etc/nftables.conf`
- **Dependencies**: None

### IDS (Suricata)
- **Reload Support**: ✅ Full support
- **Config Files**: `/etc/suricata/suricata.yaml`
- **Validation**: `suricata -T -c /etc/suricata/suricata.yaml`
- **Reload Command**: `systemctl reload suricata`
- **Dependencies**: None

### Network
- **Reload Support**: ❌ Not supported
- **Reason**: Network changes require interface restart
- **Alternative**: Use `systemctl restart network-interface.service`

## Configuration

### Basic Configuration

```nix
{
  services.gateway.configReload = {
    services = [ "dns" "dhcp" "firewall" "ids" ];
    enableAutoReload = true;
    enableChangeDetection = true;
    enableRollback = true;
    backupRetention = "7d";
    reloadTimeout = 300;
    healthCheckDelay = 10;
  };
}
```

### Advanced Configuration

```nix
{
  services.gateway.configReload = {
    services = [ "dns" "dhcp" "firewall" ];
    enableAutoReload = true;
    enableChangeDetection = true;
    enableRollback = true;
    backupRetention = "14d";
    reloadTimeout = 600;
    healthCheckDelay = 15;
    reloadSchedule = "0 2 * * *";  # Daily at 2 AM
  };
}
```

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `services` | list of strings | `[ "dns" "dhcp" "firewall" "ids" ]` | Services to enable dynamic reload for |
| `enableAutoReload` | bool | `true` | Enable automatic reload on file changes |
| `enableChangeDetection` | bool | `true` | Enable configuration change detection |
| `enableRollback` | bool | `true` | Enable automatic rollback on reload failures |
| `backupRetention` | string | `"7d"` | Backup retention period (systemd time format) |
| `reloadTimeout` | int | `300` | Timeout for reload operations in seconds |
| `healthCheckDelay` | int | `10` | Delay after reload before health checks |
| `reloadSchedule` | string or null | `null` | Cron schedule for periodic reload checks |

## Management CLI

The `gateway-reload` command provides comprehensive management of configuration reloads.

### Basic Commands

```bash
# Show help
gateway-reload --help

# List available services
gateway-reload list

# Show current status
gateway-reload status
```

### Reload Operations

```bash
# Reload all services
gateway-reload reload

# Reload specific services
gateway-reload reload dns dhcp

# Dry run (show what would be done)
gateway-reload --dry-run reload

# Force reload without validation
gateway-reload --force reload dns
```

### Validation and Backup

```bash
# Validate configuration
gateway-reload validate dns dhcp

# Create manual backup
gateway-reload backup

# Validate all services
gateway-reload validate
```

### Rollback Operations

```bash
# Rollback specific service
gateway-reload rollback dns

# Dry run rollback
gateway-reload --dry-run rollback dns
```

### Advanced Options

```bash
# Set custom timeout
gateway-reload --timeout 600 reload dns

# Force operation
gateway-reload --force reload
```

## Reload Process

### 1. Change Detection

The system monitors configuration files for changes:

```bash
# Manual change detection
systemctl start gateway-config-change-detection.service

# Automatic detection (runs every minute)
systemctl status gateway-config-change-detection.timer
```

### 2. Validation

Before reload, configurations are validated:

```bash
# DNS validation
knotc conf-check

# DHCP validation
kea-dhcp4 -t /etc/kea/dhcp4-server.conf
kea-dhcp6 -t /etc/kea/dhcp6-server.conf

# Firewall validation
nft -c /etc/nftables.conf

# IDS validation
suricata -T -c /etc/suricata/suricata.yaml
```

### 3. Backup Creation

Automatic backups are created before reload:

```bash
# Backup location
/var/lib/gateway-config-backup/
├── dns/
│   ├── 20241014_143022/
│   └── 20241014_150315/
├── dhcp/
│   ├── 20241014_143022/
│   └── 20241014_150315/
└── manual/
    └── 20241014_160000/
```

### 4. Reload Execution

Services are reloaded in dependency order:

1. DNS (no dependencies)
2. DHCP (depends on DNS)
3. Firewall (no dependencies)
4. IDS (no dependencies)

### 5. Health Check

Post-reload health verification:

```bash
# Service status check
systemctl is-active --quiet dns

# Health check integration
systemctl status gateway-health-check-dns.service
```

## File Watching

Automatic reload on file changes:

```bash
# DNS config file watching
systemctl status gateway-config-watch-dns.path

# DHCP config file watching
systemctl status gateway-config-watch-dhcp.path

# Firewall config file watching
systemctl status gateway-config-watch-firewall.path
```

## Scheduled Operations

### Periodic Reload Checks

```nix
{
  services.gateway.configReload = {
    reloadSchedule = "0 2 * * *";  # Daily at 2 AM
  };
}
```

### Backup Cleanup

```bash
# Automatic cleanup (runs daily)
systemctl status gateway-config-cleanup.service

# Manual cleanup
find /var/lib/gateway-config-backup -type d -mtime +7 -exec rm -rf {} \;
```

## Integration with Health Checks

The reload system integrates with the health check framework:

```nix
{
  services.gateway.healthChecks = {
    config-reload = {
      checks = [
        {
          type = "process";
          name = "config-reload-process";
          description = "Config reload process health";
          config = {
            processName = "gateway-config-reload";
            maxMemoryMB = 100;
            maxCpuPercent = 50;
          };
        }
        {
          type = "filesystem";
          name = "config-backup-filesystem";
          description = "Config backup filesystem health";
          config = {
            path = "/var/lib/gateway-config-backup";
            minFreeSpaceMB = 100;
            maxUsagePercent = 80;
          };
        }
      ];
    };
  };
}
```

## Troubleshooting

### Common Issues

#### Reload Fails

```bash
# Check service status
gateway-reload status

# Validate configuration
gateway-reload validate

# Check logs
journalctl -u gateway-config-reload-coordinated.service

# Rollback if needed
gateway-reload rollback <service>
```

#### Change Detection Not Working

```bash
# Check timer status
systemctl status gateway-config-change-detection.timer

# Run manually
systemctl start gateway-config-change-detection.service

# Check hash files
ls -la /var/lib/gateway-config-hashes/
```

#### Backup Issues

```bash
# Check backup directory
ls -la /var/lib/gateway-config-backup/

# Check permissions
ls -ld /var/lib/gateway-config-backup/

# Manual backup test
gateway-reload backup
```

### Debug Mode

Enable debug logging:

```bash
# Check reload script
cat /run/gateway-config-reload/reload-dns.sh

# Run with debug
bash -x /run/gateway-config-reload/reload-dns.sh
```

### Log Analysis

```bash
# Reload logs
journalctl -u gateway-config-reload-*

# Change detection logs
journalctl -u gateway-config-change-detection

# File watcher logs
journalctl -u gateway-config-watch-*
```

## Security Considerations

### File Permissions

Configuration files have appropriate permissions:

```bash
# DNS configs
/var/lib/knot/knotd.conf          - knot:knot 640
/var/lib/knot/zones/*              - knot:knot 644

# DHCP configs
/etc/kea/dhcp4-server.conf        - kea:kea 640
/etc/kea/dhcp6-server.conf        - kea:kea 640

# Firewall config
/etc/nftables.conf                 - root:root 644
```

### Service Isolation

Reload services run with restricted permissions:

```bash
# PrivateTmp=true
# ProtectSystem=strict
# ReadWritePaths limited to backup directories
```

### Audit Trail

All configuration changes are logged:

```bash
# Systemd logs
journalctl -u gateway-config-reload-*

# Backup timestamps
ls -la /var/lib/gateway-config-backup/
```

## Performance Impact

### Resource Usage

- **Memory**: Minimal (< 100MB for reload processes)
- **CPU**: Brief spikes during reload operations
- **Storage**: Config backups (typically < 10MB per backup)
- **Network**: No impact during reload operations

### Optimization Tips

1. **Selective Reload**: Only reload services that need changes
2. **Validation**: Use validation before reload to avoid failed attempts
3. **Backup Retention**: Adjust retention based on storage capacity
4. **Change Detection**: Disable if not using automatic reload

## Best Practices

### Configuration Management

1. **Test Changes**: Always validate before applying
2. **Backup Strategy**: Regular manual backups before major changes
3. **Rollback Planning**: Know rollback procedures for each service
4. **Monitoring**: Use health checks to verify reload success

### Operational Procedures

1. **Staged Rollouts**: Apply changes to non-critical services first
2. **Maintenance Windows**: Schedule major changes during low-traffic periods
3. **Documentation**: Record all configuration changes
4. **Testing**: Use dry-run mode to verify reload plans

### Recovery Planning

1. **Backup Verification**: Regularly test backup restoration
2. **Rollback Testing**: Practice rollback procedures
3. **Service Dependencies**: Understand reload order requirements
4. **Monitoring Setup**: Configure alerts for reload failures

## API Reference

### Library Functions

```nix
# Main orchestration function
configReload.orchestrateReload { 
  services = [ "dns" "dhcp" ]; 
  allServices = false; 
  dryRun = false; 
}

# Get service capabilities
configReload.getReloadCapabilities "dns"

# Check if service supports reload
configReload.supportsReload "dns"

# Get dependent services
configReload.getDependentServices "dns"

# Generate reload order
configReload.generateReloadOrder [ "dns" "dhcp" ]
```

### Systemd Services

- `gateway-config-reload-<service>.service` - Individual service reload
- `gateway-config-reload-coordinated.service` - Coordinated reload
- `gateway-config-change-detection.service` - Change detection
- `gateway-config-change-detection.timer` - Change detection timer
- `gateway-config-watch-<service>.path` - File watching
- `gateway-config-rollback-<service>.service` - Service rollback
- `gateway-config-cleanup.service` - Backup cleanup

### Directories

- `/run/gateway-config-reload/` - Runtime scripts
- `/var/lib/gateway-config-backup/` - Configuration backups
- `/var/lib/gateway-config-hashes/` - Change detection hashes
- `/var/lib/gateway-config-current/` - Current configuration copies

## Examples

### Example 1: DNS Zone Update

```bash
# Update DNS zone file
vim /var/lib/knot/zones/lan.local.zone

# Validate configuration
gateway-reload validate dns

# Reload DNS service
gateway-reload reload dns

# Verify reload
gateway-reload status
```

### Example 2: DHCP Pool Configuration

```bash
# Update DHCP configuration
vim /etc/kea/dhcp4-server.conf

# Validate configuration
gateway-reload validate dhcp

# Reload DHCP service (will also reload DNS if needed)
gateway-reload reload dhcp

# Check service status
systemctl status kea-dhcp4-server
```

### Example 3: Firewall Rule Update

```bash
# Update firewall rules
vim /etc/nftables.conf

# Validate configuration
gateway-reload validate firewall

# Test rules (dry run)
nft -c /etc/nftables.conf

# Apply rules
gateway-reload reload firewall

# Verify rules
nft list ruleset
```

### Example 4: Coordinated Service Update

```bash
# Update multiple service configurations
vim /var/lib/knot/knotd.conf
vim /etc/kea/dhcp4-server.conf
vim /etc/nftables.conf

# Validate all configurations
gateway-reload validate dns dhcp firewall

# Perform coordinated reload
gateway-reload reload dns dhcp firewall

# Check all services
gateway-reload status
```

### Example 5: Rollback Scenario

```bash
# Apply problematic configuration
vim /etc/kea/dhcp4-server.conf

# Reload fails
gateway-reload reload dhcp  # This will fail

# Rollback to previous configuration
gateway-reload rollback dhcp

# Verify rollback
gateway-reload status
```

This comprehensive dynamic configuration reload system provides safe, reliable runtime configuration management for gateway services while maintaining high availability and data integrity.
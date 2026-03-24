# Service Health Checks

The NixOS Gateway Configuration Framework includes comprehensive health checking for all gateway services with automatic recovery mechanisms and monitoring integration.

## Overview

Health checks provide:
- Real-time service monitoring
- Automatic failure detection
- Integration with Prometheus metrics
- Alert management integration
- Service dependency tracking
- Configurable check intervals and timeouts

## Configuration

Health checks are configured through the `services.gateway.healthChecks` option:

```nix
services.gateway = {
  enable = true;
  
  healthChecks = {
    dns = {
      checks = [
        { type = "query"; target = "localhost"; query = "example.com"; }
        { type = "port"; port = 53; protocol = "tcp"; }
        { type = "port"; port = 53; protocol = "udp"; }
      ];
      interval = "30s";
      timeout = "5s";
    };
    
    dhcp = {
      checks = [
        { type = "port"; port = 67; protocol = "udp"; }
        { type = "database"; path = "/var/lib/kea/dhcp4.leases"; }
        { type = "process"; name = "kea-dhcp4"; }
      ];
      interval = "60s";
      timeout = "10s";
    };
  };
};
```

## Health Check Types

### Query Check
Tests DNS query resolution:
```nix
{ type = "query"; target = "localhost"; query = "example.com"; }
```

**Fields:**
- `target` (required): DNS server to query
- `query` (required): Domain name to resolve
- `expectedResult` (optional): Expected result
- `timeout` (optional): Query timeout
- `retries` (optional): Number of retries

### Port Check
Tests port connectivity:
```nix
{ type = "port"; port = 53; protocol = "tcp"; host = "localhost"; }
```

**Fields:**
- `port` (required): Port number to check
- `protocol` (optional): Protocol (tcp/udp, default: tcp)
- `host` (optional): Host to check (default: localhost)
- `timeout` (optional): Connection timeout
- `retries` (optional): Number of retries

### Zone Check
Tests DNS zone integrity:
```nix
{ type = "zone"; zone = "lan.local"; }
```

**Fields:**
- `zone` (required): DNS zone to check
- `serialCheck` (optional): Check zone serial
- `soaCheck` (optional): Check SOA record
- `timeout` (optional): Check timeout

### Database Check
Tests database integrity:
```nix
{ type = "database"; path = "/var/lib/kea/dhcp4.leases"; }
```

**Fields:**
- `path` (required): Database file path
- `checkType` (optional): Type of check (integrity, existence)
- `timeout` (optional): Check timeout

### Interface Check
Tests network interface status:
```nix
{ type = "interface"; interface = "eth0"; expectedState = "UP"; }
```

**Fields:**
- `interface` (required): Network interface name
- `checkType` (optional): Type of check (status, config)
- `expectedState` (optional): Expected state (UP/DOWN)

### Routing Check
Tests routing table:
```nix
{ type = "routing"; route = "default"; }
```

**Fields:**
- `route` (required): Route to check
- `checkType` (optional): Type of check (existence, gateway)
- `gateway` (optional): Expected gateway
- `metric` (optional): Expected metric

### Process Check
Tests process availability:
```nix
{ type = "process"; name = "kea-dhcp4"; }
```

**Fields:**
- `name` (required): Process name or pattern
- `user` (optional): Expected process user
- `memoryLimit` (optional): Memory usage limit
- `cpuLimit` (optional): CPU usage limit

### Filesystem Check
Tests filesystem accessibility:
```nix
{ type = "filesystem"; path = "/var/lib/kea"; }
```

**Fields:**
- `path` (required): Filesystem path
- `checkType` (optional): Type of check (existence, permissions, space)
- `minFreeSpace` (optional): Minimum free space
- `permissions` (optional): Expected permissions

## Default Health Checks

The framework provides default health checks for common services:

### DNS Service
- DNS query resolution test
- TCP port 53 connectivity
- UDP port 53 connectivity

### DHCP Service
- UDP port 67 connectivity
- DHCP lease database integrity
- Kea DHCP process availability

### Network Service
- Interface status checks
- Default route availability
- Basic connectivity tests

### IDS Service
- Suricata process availability
- Redis connectivity (for EVE logging)

### Monitoring Service
- Node exporter availability
- Prometheus server availability

## Monitoring Integration

### Prometheus Metrics

Health check metrics are exported to Prometheus:

```prometheus
# Health check status (1 = healthy, 0 = unhealthy)
gateway_health_check_status{service="dns"} 1

# Last successful health check timestamp
gateway_health_check_last_success_timestamp{service="dns"} 1694678400

# Number of health checks for service
gateway_health_check_check_count{service="dns"} 3

# Last health check run timestamp
gateway_health_check_last_run_timestamp 1694678460
```

### Alert Rules

Default alert rules are configured:

- **GatewayServiceUnhealthy**: Triggered when a service is unhealthy for >2 minutes
- **GatewayMultipleServicesUnhealthy**: Triggered when multiple services are unhealthy
- **GatewayHealthCheckStale**: Triggered when health check data is stale (>5 minutes)

### Log Monitoring

Health check logs are written to `/var/log/gateway/health-monitor.log`:

```
[2024-09-14 10:30:00] Running health checks for dns...
[2024-09-14 10:30:00] All health checks passed for dns
[2024-09-14 10:30:00] ✓ dns health check passed
[2024-09-14 10:30:00] Health check summary: 4/4 services healthy
```

## Service Management

### Systemd Services

Each health check creates:
- `gateway-health-check-{service}.service`: Individual health check service
- `gateway-health-check-{service}.timer`: Timer for periodic execution
- `gateway-health-monitor.service`: Main monitoring service
- `gateway-health-monitor.timer`: Timer for main monitoring

### State Management

Health check state is maintained in `/run/gateway-health-state/`:
- `{service}.status`: Current health status (healthy/unhealthy)
- `{service}.last_success`: Timestamp of last successful check

### Script Deployment

Health check scripts are deployed to `/run/gateway-health-checks/`:
- `{service}-check.sh`: Executable health check script

## Configuration Examples

### Basic Configuration
```nix
services.gateway = {
  enable = true;
  
  healthChecks = {
    dns = {
      interval = "30s";
      timeout = "5s";
    };
    
    dhcp = {
      interval = "60s";
      timeout = "10s";
    };
  };
};
```

### Custom Health Checks
```nix
services.gateway = {
  enable = true;
  
  healthChecks = {
    web-server = {
      checks = [
        { type = "port"; port = 80; protocol = "tcp"; }
        { type = "port"; port = 443; protocol = "tcp"; }
        { type = "query"; target = "localhost"; query = "web-server.local"; }
      ];
      interval = "15s";
      timeout = "3s";
    };
    
    database = {
      checks = [
        { type = "port"; port = 5432; protocol = "tcp"; }
        { type = "database"; path = "/var/lib/postgresql/data"; }
        { type = "process"; name = "postgres"; }
      ];
      interval = "30s";
      timeout = "8s";
    };
  };
};
```

### Advanced Configuration
```nix
services.gateway = {
  enable = true;
  
  healthChecks = {
    critical-service = {
      checks = [
        { 
          type = "port"; 
          port = 8080; 
          protocol = "tcp"; 
          host = "service.local";
          timeout = "2s";
          retries = 5;
        }
        { 
          type = "query"; 
          target = "service.local"; 
          query = "health.service.local";
          expectedResult = "ok";
          timeout = "3s";
        }
      ];
      interval = "10s";
      timeout = "5s";
    };
  };
};
```

## Troubleshooting

### Common Issues

1. **Health Check Failures**
   - Check service logs: `journalctl -u gateway-health-check-{service}.service`
   - Verify health check script: `/run/gateway-health-checks/{service}-check.sh`
   - Check health status: `cat /run/gateway-health-state/{service}.status`

2. **Missing Metrics**
   - Verify Prometheus configuration includes textfile collector
   - Check metrics file: `/run/prometheus/gateway-health-checks.prom`
   - Verify Prometheus service is running

3. **Timer Issues**
   - Check timer status: `systemctl status gateway-health-check-{service}.timer`
   - Verify timer is enabled: `systemctl is-enabled gateway-health-check-{service}.timer`
   - Check timer schedule: `systemctl list-timers gateway-health-check-*`

### Manual Testing

Run individual health checks manually:
```bash
# Run DNS health check
/run/gateway-health-checks/dns-check.sh

# Run all health checks
systemctl start gateway-health-monitor.service

# Check health status
cat /run/gateway-health-state/dns.status
```

### Debug Mode

Enable debug logging:
```nix
systemd.services.gateway-health-monitor.serviceConfig.Environment = [
  "RUST_LOG=debug"
];
```

## Performance Considerations

- Health checks run with minimal overhead
- Default intervals balance responsiveness and resource usage
- Failed checks are retried with exponential backoff
- Metrics generation is optimized for Prometheus scraping

## Security Considerations

- Health check scripts run as root by default
- Network checks are limited to local services
- Database checks use read-only operations
- Filesystem checks respect file permissions

## Integration with Other Modules

Health checks integrate with:
- **Monitoring Module**: Prometheus metrics and alerting
- **Security Module**: Service status monitoring
- **Network Module**: Interface and routing checks
- **DNS Module**: DNS resolution and zone checks
- **DHCP Module**: Lease database and service checks
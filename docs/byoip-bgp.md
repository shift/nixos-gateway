# BYOIP BGP Peering Module

## Overview

The BYOIP (Bring Your Own IP) BGP Peering module enables advertisement of custom IP ranges through BGP sessions with cloud providers and internet exchanges. This module provides full BGP peering capabilities for AWS, Azure, GCP, and other cloud providers, with comprehensive route filtering, monitoring, and security features.

## Features

### Cloud Provider Support
- **AWS Direct Connect**: Public and Transit Virtual Interfaces
- **Azure ExpressRoute**: Microsoft and Private peering
- **Google Cloud Interconnect**: Partner and Dedicated interconnects
- **Cloudflare Magic Transit**: Direct BGP peering
- **Extensible**: Support for additional providers

### Route Management
- Custom IP prefix advertisement
- Route Origin Validation (ROV) with RPKI
- AS path prepending for traffic engineering
- Community-based route control
- Selective prefix advertisement

### Security & Filtering
- Provider-specific route filters
- BGP community filtering
- AS path manipulation and filtering
- Route leak prevention
- Prefix hijacking detection

### Monitoring & Alerting
- BGP session health monitoring
- Route advertisement verification
- Prometheus metrics export
- Alert rules for critical events
- SLA monitoring per provider

### High Availability
- Multi-provider redundancy
- Automatic failover
- Load balancing across providers
- BGP anycast support

## Configuration

### Basic Setup

```nix
services.gateway.byoip = {
  enable = true;
  localASN = 65000;
  routerId = "192.168.1.1";

  providers = {
    aws = {
      asn = 16509;
      neighborIP = "169.254.0.1";
      localASN = 65001;

      prefixes = [
        {
          prefix = "203.0.113.0/24";
          communities = ["65001:100"];
          description = "Production network";
        }
      ];
    };
  };
};
```

### Advanced Configuration

```nix
services.gateway.byoip = {
  enable = true;
  localASN = 65000;
  routerId = "192.168.1.1";

  providers = {
    aws = {
      asn = 16509;
      neighborIP = "169.254.0.1";
      localASN = 65001;

      prefixes = [
        {
          prefix = "203.0.113.0/24";
          communities = ["65001:100" "16509:200"];
          asPath = "65001";
          localPref = 200;
          description = "Primary production network";
        }
        {
          prefix = "198.51.100.0/24";
          communities = ["65001:200"];
          description = "Secondary network";
        }
      ];

      filters = {
        inbound = {
          allowCommunities = ["16509:*"];
          maxPrefixLength = 24;
          rejectLongerPrefixes = true;
        };
        outbound = {
          prependAS = 2;
          noExport = true;
        };
      };

      capabilities = {
        multipath = true;
        extendedNexthop = true;
        addPath = "both";
      };

      timers = {
        keepalive = 30;
        hold = 90;
      };

      monitoring = {
        enable = true;
        checkInterval = "30s";
        alertThreshold = 300;
      };
    };

    azure = {
      asn = 12076;
      neighborIP = "169.254.1.1";
      localASN = 65002;

      prefixes = ["20.0.0.0/16"];

      # Azure-specific settings
      serviceTags = ["AzureCloud" "AzureTrafficManager"];
    };
  };

  monitoring = {
    enable = true;
    prometheusPort = 9093;
    alertRules = [
      "bgp_session_down"
      "prefix_hijacking_detected"
      "route_leak_detected"
    ];
  };

  security = {
    rov = {
      enable = true;
      strict = false;  # Allow unknown origins initially
    };
  };
};
```

## Provider Templates

The module includes pre-configured templates for major cloud providers:

### AWS Direct Connect

```nix
providers.aws = {
  asn = 16509;
  neighborIP = "169.254.255.1";  # Public VIF
  localASN = 65001;
  prefixes = ["203.0.113.0/24"];
};
```

### Azure ExpressRoute

```nix
providers.azure = {
  asn = 12076;
  neighborIP = "169.254.0.1";  # Microsoft Peering
  localASN = 65002;
  prefixes = ["20.0.0.0/16"];
};
```

### Google Cloud Interconnect

```nix
providers.gcp = {
  asn = 15169;
  neighborIP = "169.254.0.1";  # Partner Interconnect
  localASN = 65003;
  prefixes = ["192.0.2.0/24"];
};
```

## Route Filtering

### Inbound Filtering

Control which routes are accepted from providers:

```nix
filters.inbound = {
  allowCommunities = ["16509:*"];     # Only AWS routes
  maxPrefixLength = 24;              # Reject /25 and longer
  rejectLongerPrefixes = true;       # Strict prefix length enforcement
};
```

### Outbound Filtering

Control how your routes are advertised:

```nix
filters.outbound = {
  prependAS = 2;        # Prepend local ASN twice
  noExport = true;      # Don't export to other providers
  aggregateOnly = false; # Allow more specific routes
};
```

## Monitoring

### Health Checks

Automatic health monitoring every 30 seconds:

```bash
# Check BGP session status
cat /run/gateway-health-state/byoip-aws.status
# Output: healthy

# View health logs
tail /var/log/gateway/byoip-health.log
```

### Prometheus Metrics

Exported metrics include:

- `gateway_bgp_neighbor_state`: Session state (0=down, 1=up)
- `gateway_bgp_neighbor_uptime`: Session uptime in seconds
- `gateway_bgp_neighbor_routes_received`: Routes received from peer
- `gateway_bgp_neighbor_routes_advertised`: Routes advertised to peer
- `gateway_byoip_total_prefixes`: Total BYOIP prefixes configured
- `gateway_byoip_rov_prefixes`: RPKI ROAs loaded

### Alert Rules

Built-in alerts for:

- BGP session down (>5 minutes)
- Prefix hijacking detected
- Route leak detected
- ROV validation failures

## Security

### Route Origin Validation (ROV)

Enable RPKI-based route validation:

```nix
security.rov = {
  enable = true;
  strict = false;  # Allow unknown origins during migration
};
```

### Route Leak Prevention

Automatic detection and prevention of route leaks through:

- Community filtering
- AS path validation
- Prefix origin verification
- Provider-specific policies

## Operations

### BGP Session Management

```bash
# Check BGP sessions
vtysh -c "show bgp summary"

# View advertised routes
vtysh -c "show bgp neighbors 169.254.0.1 advertised-routes"

# View received routes
vtysh -c "show bgp neighbors 169.254.0.1 routes"
```

### Route Filtering Verification

```bash
# Check prefix lists
vtysh -c "show ip prefix-list"

# Check route maps
vtysh -c "show route-map"

# Check community lists
vtysh -c "show ip community-list"
```

### Troubleshooting

```bash
# View BGP logs
vtysh -c "show logging"

# Debug BGP sessions
vtysh -c "debug bgp neighbor 169.254.0.1"

# Check RPKI status
vtysh -c "show rpki"
```

## Migration Guide

### From Cloud-Managed BYOIP

1. **Obtain IP Ranges and ASN**
   - Register with RIR (ARIN, RIPE, APNIC)
   - Obtain provider-independent IP space
   - Get your own ASN

2. **Configure BGP Peering**
   ```nix
   services.gateway.byoip = {
     enable = true;
     localASN = 65000;  # Your ASN
     routerId = "192.168.1.1";

     providers.aws = {
       asn = 16509;
       neighborIP = "169.254.0.1";
       localASN = 65000;
       prefixes = ["203.0.113.0/24"];  # Your IP range
     };
   };
   ```

3. **Set Up Route Filtering**
   - Configure inbound filters to only accept provider routes
   - Configure outbound filters for traffic engineering
   - Enable ROV for security

4. **Test Advertisement**
   - Verify BGP sessions establish
   - Confirm routes are advertised correctly
   - Test connectivity to advertised prefixes

5. **Coordinate Cutover**
   - Announce routes from new BGP sessions
   - Withdraw routes from cloud-managed BYOIP
   - Monitor traffic patterns during transition

### Best Practices

- **Use unique ASNs** per provider for traffic engineering
- **Enable ROV** for route security
- **Monitor session health** continuously
- **Test failover scenarios** regularly
- **Keep prefix documentation** current

## Performance Considerations

- **BGP Convergence**: Sub-second convergence times
- **Route Scale**: Support for 100k+ routes
- **Memory Usage**: ~50MB per 10k routes
- **CPU Usage**: Minimal impact on modern hardware

## Troubleshooting

### Common Issues

1. **BGP Session Not Establishing**
   - Check IP connectivity to neighbor
   - Verify ASN configuration
   - Check MD5 password if configured

2. **Routes Not Advertising**
   - Verify prefix is in routing table
   - Check outbound route maps
   - Confirm network statement in BGP config

3. **Routes Not Received**
   - Check inbound route maps
   - Verify community filters
   - Confirm neighbor capabilities

4. **ROV Issues**
   - Check RPKI cache status
   - Verify ROA coverage
   - Review strict vs. loose validation

### Debug Commands

```bash
# Enable BGP debugging
vtysh -c "debug bgp neighbor <IP>"

# View detailed session info
vtysh -c "show bgp neighbors <IP>"

# Check route processing
vtysh -c "debug bgp updates"
```

## API Reference

### Configuration Options

#### `services.gateway.byoip`
- `enable`: Enable BYOIP functionality (boolean)
- `localASN`: Local ASN for BYOIP (integer)
- `routerId`: BGP router ID (string)
- `providers`: Provider configurations (attribute set)

#### Provider Configuration
- `asn`: Provider ASN (integer)
- `neighborIP`: Neighbor IP address (string)
- `localASN`: Local ASN for this peering (integer)
- `prefixes`: List of prefixes to advertise (list)
- `filters`: Route filtering configuration (attribute set)
- `capabilities`: BGP capabilities (attribute set)
- `timers`: BGP timers (attribute set)
- `monitoring`: Provider monitoring config (attribute set)

### Exported Metrics

All metrics are prefixed with `gateway_bgp_` or `gateway_byoip_`:

- `neighbor_state`: Session state per neighbor
- `neighbor_uptime`: Session uptime per neighbor
- `neighbor_routes_received`: Routes received per neighbor
- `neighbor_routes_advertised`: Routes advertised per neighbor
- `total_prefixes`: Total configured BYOIP prefixes
- `rov_prefixes`: RPKI ROAs loaded

### Systemd Services

- `gateway-byoip-health-check.service`: Health monitoring
- `gateway-byoip-metrics.service`: Metrics collection
- `gateway-byoip-health-check.timer`: Health check timer
- `gateway-byoip-metrics.timer`: Metrics timer

## Examples

See `examples/byoip-bgp-example.nix` for complete configuration examples.

## Testing

Run the BYOIP BGP test suite:

```bash
nix build .#checks.x86_64-linux.byoip-bgp-test
```

## Contributing

When adding new providers:

1. Add provider configuration to `lib/provider-peering.nix`
2. Update `lib/byoip-config.nix` with provider-specific settings
3. Add test cases to `tests/byoip-bgp-test.nix`
4. Update documentation

## License

This module is part of the NixOS Gateway Configuration Framework and follows the same license terms.
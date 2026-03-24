# NAT Gateway Implementation

## Overview

The NAT Gateway module provides a drop-in replacement for AWS NAT Gateway functionality, implementing Source Network Address Translation (SNAT) for private subnet internet access with enterprise-grade features.

## Features

- **SNAT Implementation**: Source Network Address Translation for outbound traffic
- **Connection Tracking**: Advanced state management with configurable timeouts
- **Load Balancing**: Multiple public IPs with automatic distribution
- **Port Forwarding**: DNAT rules for inbound service access
- **Security Integration**: Firewall rule coordination and DDoS protection
- **Monitoring**: Comprehensive metrics and alerting
- **High Availability**: Multiple NAT instances with failover support

## Configuration

### Basic Configuration

```nix
services.gateway.natGateway = {
  enable = true;

  instances = [
    {
      name = "primary-nat";
      publicInterface = "eth0";
      privateSubnets = [ "192.168.1.0/24" "10.0.0.0/16" ];
      publicIPs = [ "203.0.113.10" "203.0.113.11" ];
    }
  ];

  monitoring = {
    enable = true;
    prometheusPort = 9092;
  };
};
```

### Advanced Configuration

```nix
services.gateway.natGateway = {
  enable = true;

  instances = [
    {
      name = "enterprise-nat";
      publicInterface = "bond0";
      privateSubnets = [ "10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16" ];

      # Multiple public IPs for load balancing
      publicIPs = [
        "203.0.113.10"
        "203.0.113.11"
        "203.0.113.12"
        "203.0.113.13"
      ];

      # Performance tuning
      maxConnections = 500000;
      timeout = {
        tcp = "24h";
        udp = "300s";
      };

      # Security settings
      allowInbound = false;

      # Port forwarding for specific services
      portForwarding = [
        {
          protocol = "tcp";
          port = 80;
          targetIP = "10.0.1.100";
          targetPort = 8080;
        }
        {
          protocol = "tcp";
          port = 443;
          targetIP = "10.0.1.101";
          targetPort = 8443;
        }
        {
          protocol = "udp";
          port = 53;
          targetIP = "10.0.1.10";
          targetPort = 53;
        }
      ];
    }
  ];

  monitoring = {
    enable = true;
    prometheusPort = 9092;
  };
};
```

## Configuration Options

### Instance Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `name` | string | - | Unique identifier for the NAT instance |
| `publicInterface` | string | - | Network interface with public connectivity |
| `privateSubnets` | list | [] | CIDR blocks to NAT for outbound access |
| `publicIPs` | list | [] | Public IP addresses for SNAT |
| `maxConnections` | int | 100000 | Maximum concurrent connections |
| `timeout.tcp` | string | "24h" | TCP connection timeout |
| `timeout.udp` | string | "300s" | UDP connection timeout |
| `allowInbound` | bool | false | Allow inbound connections |
| `portForwarding` | list | [] | Port forwarding rules |

### Monitoring Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | false | Enable NAT monitoring |
| `prometheusPort` | int | 9092 | Port for Prometheus metrics |

## Integration with Other Modules

### Firewall Integration

The NAT Gateway automatically coordinates with the firewall module:

```nix
# NAT rules are automatically added to firewall chains
networking.firewall = {
  enable = true;
  # NAT rules are inserted before filter rules
};
```

### Routing Integration

Private subnets are automatically routed through NAT instances:

```nix
# Routes are added to custom routing tables
networking.interfaces."eth0" = {
  # NAT routing rules are applied automatically
};
```

### Security Integration

NAT Gateway integrates with security modules for threat protection:

```nix
services.gateway.security = {
  # NAT participates in security policy enforcement
};
```

## Monitoring and Observability

### Metrics

The following Prometheus metrics are exposed:

- `nat_gateway_connections_active`: Number of active NAT connections
- `nat_gateway_connections_total`: Total connections since startup
- `nat_gateway_bandwidth_rx_bytes`: Received bandwidth
- `nat_gateway_bandwidth_tx_bytes`: Transmitted bandwidth
- `nat_gateway_errors_total`: NAT operation errors
- `nat_gateway_cpu_usage`: CPU utilization percentage
- `nat_gateway_memory_usage`: Memory usage in bytes

### Grafana Dashboard

A pre-configured Grafana dashboard is available showing:

- Active connection counts
- Bandwidth utilization graphs
- Error rates and trends
- Resource usage monitoring

### Alerting

Built-in alerting rules for:

- High connection counts (>80% of limit)
- Elevated error rates
- Resource usage thresholds

## Performance Tuning

### Connection Limits

```nix
# Increase kernel connection tracking limits
boot.kernel.sysctl = {
  "net.netfilter.nf_conntrack_max" = 2000000;
  "net.nf_conntrack_max" = 2000000;
};
```

### CPU Optimization

```nix
# Enable RPS/RFS for multi-core NAT processing
networking.interfaces."eth0" = {
  # RPS configuration for NAT interfaces
};
```

### Memory Tuning

```nix
# Optimize conntrack hash table size
boot.kernel.sysctl = {
  "net.netfilter.nf_conntrack_buckets" = 262144;
};
```

## Security Considerations

### Inbound Protection

By default, NAT Gateway blocks all inbound connections:

```nix
# Only explicitly forwarded ports are accessible
allowInbound = false;
```

### DDoS Protection

NAT Gateway includes built-in DDoS protection:

- Connection rate limiting
- SYN flood protection
- Invalid packet filtering

### Audit Logging

NAT operations can be logged for security auditing:

```nix
# Enable NAT logging (may impact performance)
services.gateway.natGateway = {
  # Logging configuration
};
```

## Migration from AWS NAT Gateway

### Step-by-Step Migration

1. **Assess Current Usage**
   ```bash
   # Identify NAT Gateway dependencies
   aws ec2 describe-nat-gateways
   aws ec2 describe-route-tables --filters Name=route.gateway-id,Values=nat-*
   ```

2. **Configure Equivalent NAT Instances**
   ```nix
   services.gateway.natGateway.instances = [
     {
       name = "aws-nat-replacement";
       publicInterface = "eth0";
       privateSubnets = [ "10.0.0.0/16" ];  # Your private subnets
       publicIPs = [ "YOUR_ELASTIC_IP" ];   # Your Elastic IPs
     }
   ];
   ```

3. **Update Route Tables**
   ```bash
   # Remove AWS NAT Gateway routes
   aws ec2 delete-route --route-table-id rtb-12345678 --destination-cidr-block 0.0.0.0/0

   # Routes are automatically configured by NixOS
   ```

4. **Test Connectivity**
   ```bash
   # Test outbound connectivity from private instances
   ping 8.8.8.8
   curl https://httpbin.org/ip
   ```

5. **Cutover**
   ```bash
   # Deploy NixOS configuration
   nixos-rebuild switch

   # Monitor for issues
   journalctl -f -u nat-gateway-*
   ```

### Cost Comparison

| Component | AWS NAT Gateway | NixOS NAT Gateway |
|-----------|----------------|-------------------|
| Hourly Cost | $0.045 | $0.00 |
| Data Processing | $0.045/GB | $0.00 |
| Setup Fee | None | None |
| Maintenance | AWS Managed | Self-Managed |

### Feature Comparison

| Feature | AWS NAT Gateway | NixOS NAT Gateway |
|---------|----------------|-------------------|
| SNAT | ✓ | ✓ |
| Multiple IPs | Limited | ✓ |
| Port Forwarding | Limited | ✓ |
| Monitoring | Basic | Comprehensive |
| Customization | None | Full |
| Cost | High | Free |

## Troubleshooting

### Common Issues

#### No Outbound Connectivity

**Symptoms**: Private instances cannot reach internet

**Solutions**:
1. Verify public interface configuration
2. Check iptables rules: `iptables -t nat -L`
3. Ensure IP forwarding is enabled: `sysctl net.ipv4.ip_forward`

#### High CPU Usage

**Symptoms**: NAT process consuming excessive CPU

**Solutions**:
1. Reduce connection tracking timeouts
2. Enable RPS/RFS for multi-core distribution
3. Consider XDP/eBPF offloading

#### Connection Limits Exceeded

**Symptoms**: New connections failing

**Solutions**:
1. Increase `maxConnections` limit
2. Tune kernel conntrack parameters
3. Add additional NAT instances

### Diagnostic Commands

```bash
# Check NAT rules
iptables -t nat -L -n -v

# Monitor connection tracking
conntrack -L | wc -l

# Check interface statistics
ip -s link show eth0

# View NAT logs
journalctl -u nat-gateway-*

# Test connectivity
ping -I eth0 8.8.8.8
```

## Examples

### Simple Home Network

```nix
services.gateway.natGateway = {
  enable = true;
  instances = [
    {
      name = "home-nat";
      publicInterface = "wan0";
      privateSubnets = [ "192.168.1.0/24" ];
      publicIPs = [ "auto" ];  # Use interface IP
    }
  ];
};
```

### Enterprise Multi-Zone

```nix
services.gateway.natGateway = {
  enable = true;
  instances = [
    {
      name = "zone-a-nat";
      publicInterface = "eth0";
      privateSubnets = [ "10.0.0.0/16" ];
      publicIPs = [ "203.0.113.10" "203.0.113.11" ];
      maxConnections = 100000;
    }
    {
      name = "zone-b-nat";
      publicInterface = "eth1";
      privateSubnets = [ "10.1.0.0/16" ];
      publicIPs = [ "203.0.113.20" "203.0.113.21" ];
      maxConnections = 100000;
    }
  ];
  monitoring.enable = true;
};
```

### High-Performance Setup

```nix
services.gateway.natGateway = {
  enable = true;
  instances = [
    {
      name = "perf-nat";
      publicInterface = "bond0";
      privateSubnets = [ "10.0.0.0/8" ];
      publicIPs = [ "203.0.113.10" "203.0.113.11" "203.0.113.12" "203.0.113.13" ];
      maxConnections = 1000000;
      timeout.tcp = "12h";
      timeout.udp = "60s";
    }
  ];
  monitoring.enable = true;
};
```

## API Reference

### Functions

#### `natConfig.mkNatRules instance`

Generates iptables rules for NAT configuration.

**Parameters:**
- `instance`: NAT instance configuration

**Returns:** Shell script string

#### `natConfig.mkNatCleanup instance`

Generates cleanup commands for NAT rules.

**Parameters:**
- `instance`: NAT instance configuration

**Returns:** Shell script string

#### `natMonitoring.mkMonitoringScript instances`

Creates monitoring script for NAT metrics collection.

**Parameters:**
- `instances`: List of NAT instance configurations

**Returns:** Package with monitoring script

#### `natMonitoring.mkPrometheusMetrics instances`

Generates Prometheus metrics configuration.

**Parameters:**
- `instances`: List of NAT instance configurations

**Returns:** Metrics configuration string

## Contributing

When contributing to the NAT Gateway module:

1. Update tests in `tests/nat-gateway-test.nix`
2. Add documentation for new features
3. Ensure backward compatibility
4. Test with multiple network configurations
5. Update performance benchmarks

## License

This module is part of the NixOS Gateway Configuration Framework and follows the same licensing terms.</content>
<parameter name="filePath">docs/nat-gateway.md
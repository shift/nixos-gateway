# Policy-Based Routing Implementation

## Overview

This implementation provides comprehensive policy-based routing (PBR) capabilities for the NixOS Gateway Configuration Framework. It allows traffic to be routed based on source address, protocol, application type, and other criteria beyond just destination-based routing.

## Features

### 1. Traffic Classification
- **Source-based routing**: Route traffic based on source IP addresses or networks
- **Protocol-specific routing**: Different routing for TCP, UDP, ICMP protocols
- **Application-aware routing**: Route based on destination ports (VoIP, gaming, web, etc.)
- **Interface-based routing**: Route based on input/output interfaces

### 2. Routing Policies
- **Multiple routing tables**: Support for up to 252 custom routing tables
- **Rule-based traffic selection**: Flexible matching criteria
- **Priority-based rule processing**: Lower priority numbers have higher precedence
- **Multiple actions**: Route, blackhole, unreachable, prohibit, multipath

### 3. Advanced Features
- **Load balancing**: Weighted multipath routing across multiple paths
- **Failover support**: Automatic failover between routing tables
- **Traffic engineering**: Optimize routing for specific applications
- **Dynamic policy updates**: Runtime policy modification support

### 4. Monitoring and Analytics
- **Policy hit counters**: Track how often each policy is used
- **Traffic volume monitoring**: Monitor traffic by policy
- **Table utilization**: Track routing table usage
- **Performance metrics**: Monitor policy processing performance

## Configuration

### Basic Configuration

```nix
services.gateway.policyRouting = {
  enable = true;
  
  routingTables = {
    table100 = { 
      name = "ISP1"; 
      priority = 100; 
      id = 100;
    };
    table200 = { 
      name = "ISP2"; 
      priority = 200; 
      id = 200;
    };
  };
  
  policies = {
    "voip-traffic" = {
      priority = 1000;
      rules = [
        {
          match = {
            protocol = "udp";
            destinationPort = 5060;
          };
          action = "route";
          table = "table100";
        }
      ];
    };
  };
};
```

### Advanced Configuration

```nix
services.gateway.policyRouting = {
  enable = true;
  
  routingTables = {
    table100 = { name = "Primary-ISP"; priority = 100; id = 100; };
    table200 = { name = "Backup-ISP"; priority = 200; id = 200; };
    table300 = { name = "VPN-Tunnel"; priority = 300; id = 300; };
  };
  
  policies = {
    "load-balance" = {
      priority = 1000;
      rules = [
        {
          match = {
            sourceAddress = "192.168.1.0/24";
          };
          action = "multipath";
          tables = [ "table100" "table200" ];
          weights = { table100 = 70; table200 = 30; };
        }
      ];
    };
    
    "vpn-traffic" = {
      priority = 2000;
      rules = [
        {
          match = {
            destinationNetwork = "10.0.0.0/8";
          };
          action = "route";
          table = "table300";
        }
      ];
    };
  };
  
  monitoring = {
    enable = true;
    metrics = {
      policyHits = true;
      trafficByPolicy = true;
      tableUtilization = true;
    };
  };
};
```

## Configuration Options

### Routing Tables

- `name`: Human-readable name for the routing table
- `priority`: Priority for table selection (lower = higher priority)
- `id`: Table ID (1-252, auto-generated if not specified)

### Policy Rules

#### Match Criteria
- `sourceAddress`: Source IP address or CIDR network
- `destinationAddress`: Destination IP address or CIDR network
- `sourceNetwork`: Source network (CIDR notation)
- `destinationNetwork`: Destination network (CIDR notation)
- `protocol`: IP protocol (tcp, udp, icmp, all)
- `sourcePort`: Source port number
- `destinationPort`: Destination port number
- `inputInterface`: Input interface name
- `outputInterface`: Output interface name
- `fwmark`: Firewall mark value

#### Actions
- `route`: Route to specified routing table
- `blackhole`: Silently drop packets
- `unreachable`: Return ICMP unreachable
- `prohibit`: Return ICMP prohibited
- `multipath`: Load balance across multiple tables

### Monitoring Options

- `policyHits`: Track policy rule usage
- `trafficByPolicy`: Monitor traffic volume per policy
- `tableUtilization`: Track routing table utilization

## Integration

### Network Module Integration

The policy routing module integrates seamlessly with the existing network module:

- Automatic interface configuration
- DHCP client integration
- IPv6 support
- Network manager compatibility

### Firewall Integration

Policy routing works with both iptables and nftables:

- Automatic packet marking for policy routing
- Integration with existing firewall rules
- Support for complex firewall policies

### Monitoring Integration

Monitoring data can be exported to:

- Prometheus metrics
- Syslog logging
- Custom monitoring systems
- Real-time dashboards

## Use Cases

### 1. Multi-ISP Load Balancing

```nix
policies = {
  "isp-load-balance" = {
    priority = 1000;
    rules = [
      {
        match = { sourceAddress = "192.168.1.0/24"; };
        action = "multipath";
        tables = [ "table100" "table200" ];
        weights = { table100 = 60; table200 = 40; };
      }
    ];
  };
};
```

### 2. Application-Aware Routing

```nix
policies = {
  "voip-priority" = {
    priority = 100;
    rules = [
      {
        match = {
          protocol = "udp";
          destinationPort = 5060;  # SIP
        };
        action = "route";
        table = "table100";  # Low-latency ISP
      }
    ];
  };
  
  "gaming-traffic" = {
    priority = 200;
    rules = [
      {
        match = {
          protocol = "udp";
          destinationPort = 27000;  # Steam
        };
        action = "route";
        table = "table100";
      }
    ];
  };
};
```

### 3. Site-to-Site VPN Routing

```nix
policies = {
  "vpn-traffic" = {
    priority = 1000;
    rules = [
      {
        match = {
          destinationNetwork = "10.0.0.0/8";
        };
        action = "route";
        table = "table300";  # VPN table
      }
    ];
  };
};
```

### 4. Traffic Segregation

```nix
policies = {
  "guest-traffic" = {
    priority = 2000;
    rules = [
      {
        match = {
          sourceAddress = "192.168.100.0/24";  # Guest network
        };
        action = "route";
        table = "table200";  # Limited ISP
      }
    ];
  };
  
  "corporate-traffic" = {
    priority = 1000;
    rules = [
      {
        match = {
          sourceAddress = "192.168.1.0/24";  # Corporate network
        };
        action = "route";
        table = "table100";  # Premium ISP
      }
    ];
  };
};
```

## Performance Considerations

### Rule Processing

- Rules are processed in priority order (lower numbers first)
- Complex match criteria may impact performance
- Use specific criteria to minimize processing overhead

### Table Management

- Limit the number of routing tables to avoid kernel overhead
- Use table priorities effectively
- Monitor table utilization regularly

### Monitoring Impact

- Monitoring adds minimal overhead
- Can be disabled for performance-critical deployments
- Consider sampling for high-traffic environments

## Troubleshooting

### Common Issues

1. **Rules not matching**: Check match criteria and rule priorities
2. **Traffic not routing**: Verify routing table configuration
3. **Performance issues**: Review rule complexity and monitoring settings
4. **Policy conflicts**: Check for overlapping rules and priorities

### Debug Commands

```bash
# Show current policy rules
ip rule list

# Show routing tables
ip route show table all

# Check iptables marks
iptables -t mangle -L -v

# Monitor policy hits
watch -n 1 'iptables -t mangle -L -v | grep POLICY'
```

### Log Analysis

Policy routing logs are available in:

- Systemd journal: `journalctl -u policy-routing`
- Kernel logs: `dmesg | grep -i policy`
- Network logs: `journalctl -u systemd-networkd`

## Security Considerations

### Rule Validation

- All policy rules are validated before application
- Invalid configurations are rejected
- Security best practices are enforced

### Traffic Isolation

- Policy routing respects firewall rules
- Traffic segregation is maintained
- Unauthorized routing is prevented

### Monitoring Privacy

- Monitoring data can be anonymized
- Sensitive traffic patterns can be excluded
- Audit trails are maintained

## Migration Guide

### From Static Routing

1. Define routing tables for each existing route
2. Create policies to replicate static routing behavior
3. Gradually migrate to policy-based rules
4. Remove static routing configuration

### From Multiple Gateways

1. Consolidate routing tables
2. Define policies for traffic segregation
3. Implement load balancing where appropriate
4. Update monitoring and alerting

## Best Practices

### Rule Design

1. Use specific match criteria to avoid conflicts
2. Order rules by priority and specificity
3. Test rules in non-production environments
4. Document rule purposes and dependencies

### Performance Optimization

1. Minimize complex match criteria
2. Use efficient table structures
3. Monitor rule processing performance
4. Optimize for common traffic patterns

### Monitoring and Maintenance

1. Enable comprehensive monitoring
2. Set up alerts for policy failures
3. Regular policy review and optimization
4. Maintain documentation for troubleshooting

## Future Enhancements

### Planned Features

1. **Dynamic policy updates**: Runtime policy modification
2. **Machine learning**: Intelligent traffic classification
3. **API integration**: External policy management
4. **Advanced analytics**: Traffic pattern analysis

### Integration Opportunities

1. **SDN controllers**: Software-defined networking integration
2. **Cloud platforms**: Hybrid cloud routing
3. **Container networking**: Kubernetes integration
4. **IoT devices**: Specialized IoT routing policies

## Conclusion

This policy-based routing implementation provides a comprehensive, flexible, and performant solution for advanced traffic routing requirements. It integrates seamlessly with the existing NixOS Gateway Configuration Framework while maintaining security, reliability, and ease of use.

The modular design allows for easy customization and extension, while the comprehensive monitoring and validation features ensure reliable operation in production environments.
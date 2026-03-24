# Direct Connect BGP Peering

This module implements Direct Connect BGP peering functionality for NixOS Gateway, enabling high-bandwidth, low-latency connectivity with BGP route advertisements between on-premises networks and cloud providers.

## Overview

Direct Connect provides dedicated physical connections to cloud providers, offering:
- High-bandwidth connectivity (50Mbps to 100Gbps)
- Low-latency connections
- Dedicated circuits with SLA guarantees
- BGP peering for dynamic routing
- Multi-cloud connectivity support

## Supported Providers

- **AWS Direct Connect**: Full support with dedicated/hosted connections
- **Azure ExpressRoute**: Complete ExpressRoute integration
- **Google Cloud Dedicated Interconnect**: Partner and dedicated interconnect
- **Oracle FastConnect**: FastConnect integration
- **IBM Cloud Direct Link**: Direct Link support

## Configuration

### Basic Configuration

```nix
networking.directConnect = {
  enable = true;

  connections = {
    "dc-aws-primary" = {
      provider = "aws";
      location = "us-east-1";
      bandwidth = "10Gbps";
      connectionType = "dedicated";

      bgp = {
        localASN = 65000;
        peerASN = 7224;  # AWS ASN

        ipv4 = {
          localIP = "169.254.1.1/30";
          peerIP = "169.254.1.2/30";
          advertisePrefixes = [
            "10.0.0.0/16"
            "192.168.0.0/24"
          ];
        };
      };
    };
  };
};
```

### Advanced Configuration with IPv6 and Policies

```nix
networking.directConnect = {
  enable = true;

  connections = {
    "dc-aws-primary" = {
      provider = "aws";
      location = "us-east-1";
      bandwidth = "10Gbps";

      bgp = {
        localASN = 65000;
        peerASN = 7224;

        ipv4 = {
          localIP = "169.254.1.1/30";
          peerIP = "169.254.1.2/30";
          advertisePrefixes = [ "10.0.0.0/16" ];
        };

        ipv6 = {
          enable = true;
          localIP = "2001:db8::1/126";
          peerIP = "2001:db8::2/126";
          advertisePrefixes = [ "2001:db8:1000::/48" ];
        };

        authentication = "tcp-ao";
        tcpAOPassword = "secure-password";

        policies = {
          inbound = {
            allowCommunities = ["7224:*"];
            maxPrefixLength = 24;
          };
          outbound = {
            prependAS = 1;
            setCommunities = ["65000:100"];
          };
        };
      };

      monitoring = {
        enable = true;
        healthChecks = {
          icmp = true;
          bgp = true;
          latency = true;
        };
        alerts = {
          connectionDown = true;
          bgpSessionDown = true;
          highLatency = "50ms";
        };
      };
    };
  };

  monitoring = {
    prometheus = {
      enable = true;
      port = 9094;
    };
  };

  security = {
    bgpAuthentication = "tcp-ao";
    routeFiltering = {
      enable = true;
      strictMode = false;
    };
  };
};
```

## BGP Configuration Options

### Authentication

- `none`: No authentication
- `tcp-md5`: MD5 authentication (deprecated)
- `tcp-ao`: TCP Authentication Option (recommended)

### Route Policies

#### Inbound Policies
- `allowCommunities`: List of allowed BGP communities
- `maxPrefixLength`: Maximum prefix length to accept
- `rejectLongerPrefixes`: Reject prefixes longer than maxPrefixLength

#### Outbound Policies
- `prependAS`: Number of AS prepending
- `setCommunities`: Communities to set on advertised routes
- `noExport`: Set no-export community
- `aggregateOnly`: Only advertise aggregate routes

## Monitoring and Alerting

### Health Checks
- **ICMP**: Connectivity testing
- **BGP**: Session state monitoring
- **Latency**: Round-trip time measurement
- **Throughput**: Bandwidth utilization

### Metrics
- BGP session state and uptime
- Routes received/advertised
- Latency and packet loss
- Connection health status

### Alerts
- Connection down
- BGP session down
- High latency
- Route leaks
- Prefix hijacking

## Security Features

### BGP Authentication
- TCP-AO (recommended)
- TCP-MD5 (legacy support)
- Configurable per connection

### Route Filtering
- Prefix length filtering
- Community-based filtering
- AS path filtering
- RPKI validation (optional)

### Traffic Isolation
- VRF support for segmentation
- Provider-specific isolation
- Traffic engineering controls

## Multi-Cloud Support

### AWS Direct Connect
```nix
connections."dc-aws" = {
  provider = "aws";
  location = "us-east-1";
  bandwidth = "10Gbps";
  bgp.peerASN = 7224;
};
```

### Azure ExpressRoute
```nix
connections."dc-azure" = {
  provider = "azure";
  location = "East US 2";
  bandwidth = "1Gbps";
  bgp.peerASN = 12076;
};
```

### Google Cloud Interconnect
```nix
connections."dc-gcp" = {
  provider = "gcp";
  location = "us-central1";
  bandwidth = "10Gbps";
  bgp.peerASN = 15169;
};
```

## High Availability

### Redundancy
- Multiple connections per provider
- BGP multipath load balancing
- Automatic failover
- Connection aggregation (LAG)

### Monitoring
- Real-time connection health
- SLA monitoring
- Performance metrics
- Automated alerting

## Integration with Existing Modules

### FRR BGP Integration
The Direct Connect module integrates with the existing FRR BGP module:
- Shared BGP configuration
- Unified monitoring
- Consistent security policies

### Network Module Integration
- Interface management
- Routing table integration
- Firewall configuration

### Monitoring Module Integration
- Prometheus metrics collection
- Alertmanager integration
- Grafana dashboard support

## Testing

Run the Direct Connect tests:

```bash
nix-build -A tests.direct-connect-test
```

## Troubleshooting

### Common Issues

1. **BGP Session Not Establishing**
   - Check IP addresses and ASN configuration
   - Verify authentication settings
   - Check firewall rules

2. **Routes Not Advertising**
   - Verify prefix configuration
   - Check outbound policies
   - Validate route filters

3. **High Latency**
   - Check connection bandwidth
   - Verify provider status
   - Monitor for congestion

### Debugging Commands

```bash
# Check BGP sessions
vtysh -c "show bgp summary"

# View advertised routes
vtysh -c "show bgp neighbors <peer> advertised-routes"

# Check interface status
ip link show dx-<connection>

# View Prometheus metrics
curl http://localhost:9094/metrics
```

## Migration Guide

### From VPN to Direct Connect

1. **Assessment**
   - Evaluate bandwidth requirements
   - Identify critical applications
   - Plan migration timeline

2. **Provider Selection**
   - Choose cloud provider
   - Select connection location
   - Determine bandwidth needs

3. **Circuit Provisioning**
   - Order dedicated circuits
   - Coordinate with provider
   - Schedule installation

4. **Configuration**
   - Set up BGP peering
   - Configure route policies
   - Enable monitoring

5. **Testing**
   - Validate connectivity
   - Test failover scenarios
   - Performance verification

6. **Cutover**
   - Migrate traffic gradually
   - Monitor during transition
   - Rollback plan ready

## Performance Optimization

### Bandwidth Management
- Monitor utilization
- Implement QoS policies
- Plan capacity upgrades

### Route Optimization
- AS path prepending
- Community tagging
- Traffic engineering

### Monitoring Best Practices
- Set appropriate thresholds
- Configure alerting
- Regular performance reviews

## Security Considerations

### BGP Security
- Use TCP-AO authentication
- Implement route filtering
- Enable RPKI validation

### Network Security
- Traffic isolation
- Access control lists
- DDoS protection

### Compliance
- Audit logging
- Configuration backups
- Change management

## Support and Resources

### Documentation
- [AWS Direct Connect Documentation](https://docs.aws.amazon.com/directconnect/)
- [Azure ExpressRoute Documentation](https://docs.microsoft.com/en-us/azure/expressroute/)
- [Google Cloud Interconnect Documentation](https://cloud.google.com/interconnect/docs)

### Community Resources
- NixOS BGP mailing list
- FRR documentation
- Cloud provider forums

## Contributing

Contributions to the Direct Connect module are welcome. Please:
1. Test changes thoroughly
2. Update documentation
3. Follow NixOS coding standards
4. Submit pull requests with detailed descriptions
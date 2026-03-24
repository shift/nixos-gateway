# Direct Connect BGP Peering

**Status: Pending**

## Description
Implement Direct Connect BGP peering functionality for dedicated physical connections, enabling high-bandwidth, low-latency connectivity with BGP route advertisements between on-premises networks and cloud providers, equivalent to AWS Direct Connect BGP functionality.

## Requirements

### Current State
- Basic BGP support exists via FRR module
- VPN-based connectivity options available (WireGuard, Tailscale)
- No dedicated physical connection support
- Limited bandwidth and latency options for cloud connectivity

### Improvements Needed

#### 1. Direct Connect Infrastructure
- Dedicated physical connection provisioning and management
- Support for various connection types (fiber, wavelength, etc.)
- Connection bandwidth options (50Mbps to 100Gbps)
- Multiple connection aggregation (Link Aggregation Groups)
- Connection health monitoring and failover

#### 2. BGP Peering Configuration
- BGP session establishment over dedicated connections
- Support for both IPv4 and IPv6 BGP peering
- Multiple BGP peers per connection (redundancy)
- BGP authentication and security (MD5/TCP-AO)
- Route advertisement and filtering policies

#### 3. Route Advertisement Management
- Automatic route advertisement from cloud to on-premises
- On-premises route injection to cloud routing tables
- Prefix filtering and route policies
- AS path manipulation and community tagging
- Route prioritization and traffic engineering

#### 4. Cloud Provider Integration
- AWS Direct Connect equivalent functionality
- Azure ExpressRoute integration
- GCP Dedicated Interconnect support
- Multi-cloud direct connect management
- Provider-specific configuration templates

#### 5. High Availability and Redundancy
- Multiple direct connect circuits for redundancy
- BGP multipath and load balancing
- Automatic failover between connections
- Connection health monitoring and alerting
- SLA monitoring and reporting

#### 6. Security and Compliance
- Encrypted BGP sessions (TCP-AO preferred over MD5)
- Route leak prevention mechanisms
- Traffic isolation and segmentation
- Compliance with cloud provider security requirements
- Audit logging for BGP session changes

## Implementation Details

### Files to Create
- `modules/direct-connect.nix` - Direct connect connection management
- `lib/direct-connect-config.nix` - Connection configuration utilities
- `lib/bgp-direct-connect.nix` - BGP peering for direct connect
- `lib/cloud-provider-direct-connect.nix` - Provider-specific templates

### Direct Connect Configuration Structure
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
        enable = true;
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

        ipv6 = {
          enable = true;
          localIP = "2001:db8::1/126";
          peerIP = "2001:db8::2/126";
          advertisePrefixes = [
            "2001:db8:1000::/48"
          ];
        };

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

    "dc-azure-secondary" = {
      provider = "azure";
      location = "East US 2";
      bandwidth = "1Gbps";

      bgp = {
        localASN = 65001;
        peerASN = 12076;  # Azure ASN

        ipv4 = {
          localIP = "169.254.2.1/30";
          peerIP = "169.254.2.2/30";
        };
      };
    };
  };

  # Global settings
  monitoring = {
    prometheus = {
      enable = true;
      port = 9094;
    };

    alerts = {
      rules = [
        "direct_connect_connection_down"
        "direct_connect_bgp_session_down"
        "direct_connect_high_latency"
      ];
    };
  };

  security = {
    bgpAuthentication = "tcp-ao";  # tcp-md5, tcp-ao, or none
    routeFiltering = {
      enable = true;
      strictMode = false;
    };
  };
};

# Route table integration
networking.directConnectRoutes = {
  "rtb-main" = {
    connection = "dc-aws-primary";
    advertiseLocal = true;
    redistribute = {
      ospf = true;
      static = true;
      connected = false;
    };
  };
};
```

### Technical Specifications
- **Connection Types**: Dedicated physical circuits (fiber, wavelength)
- **Bandwidth Options**: 50Mbps, 100Mbps, 200Mbps, 300Mbps, 400Mbps, 500Mbps, 1Gbps, 2Gbps, 5Gbps, 10Gbps, 100Gbps
- **BGP Support**: BGP-4 with IPv4/IPv6, multiprotocol extensions
- **Security**: TCP-AO authentication, route filtering, RPKI validation
- **Redundancy**: Multiple circuits, BGP multipath, fast convergence
- **Monitoring**: Real-time connection health, BGP session monitoring, SLA tracking

### Integration Points
- FRR BGP module for peering sessions
- Network module for interface and routing configuration
- Monitoring module for health checks and alerting
- Security module for BGP authentication and filtering
- Cloud provider APIs for connection provisioning

## Testing Requirements
- Direct connect circuit provisioning and activation
- BGP session establishment and route exchange
- Failover scenarios between multiple connections
- Route advertisement and filtering validation
- Performance testing with various bandwidth options
- Security testing for BGP authentication and filtering
- Multi-cloud provider integration testing

## Dependencies
- FRR BGP module (Task 09)
- Network interface management
- Cloud provider SDKs/APIs
- Monitoring and alerting infrastructure
- Security modules for BGP authentication

## Estimated Effort
- High (complex hardware and cloud integration)
- 6-8 weeks implementation
- 3 weeks testing and provider validation
- Requires coordination with cloud providers for circuit provisioning

## Success Criteria
- Successful establishment of dedicated connections with cloud providers
- Reliable BGP peering with route advertisement and filtering
- Automatic failover between redundant connections
- Sub-second convergence times for network changes
- Comprehensive monitoring and alerting for connection health
- Security compliance with cloud provider requirements
- Support for multiple cloud providers and connection types

## Business Value
- **Performance**: High-bandwidth, low-latency connectivity to cloud
- **Cost Efficiency**: Reduced data transfer costs vs internet connectivity
- **Reliability**: Dedicated circuits with SLA guarantees
- **Security**: Private connectivity without internet exposure
- **Scalability**: Support for growing bandwidth requirements
- **Multi-Cloud**: Consistent connectivity across cloud providers

## Migration Guide
Transition from VPN-based to Direct Connect connectivity:

1. **Assessment**: Evaluate current connectivity requirements and bandwidth needs
2. **Provider Selection**: Choose cloud provider and connection location
3. **Circuit Ordering**: Provision dedicated circuits with cloud provider
4. **Configuration**: Set up BGP peering and route policies
5. **Testing**: Validate connectivity and route advertisement
6. **Cutover**: Migrate traffic from VPN to Direct Connect
7. **Optimization**: Fine-tune route policies and monitoring
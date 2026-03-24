# BYOIP BGP Peering

**Status: Completed**

## Description
Implement BGP peering capabilities for Bring Your Own IP (BYOIP) functionality, enabling advertisement of custom IP ranges through BGP sessions with cloud providers and internet exchanges.

## Requirements

### Current State
- Basic BGP support exists via FRR module
- Route policies and filtering implemented
- No specific BYOIP or cloud provider peering features

### Improvements Needed

#### 1. Cloud Provider BGP Peering
- Direct BGP sessions with AWS, Azure, GCP
- Provider-specific configuration templates
- Automatic ASN and IP validation
- Secure peering establishment

#### 2. IP Range Advertisement
- Custom IP prefix advertisement
- Route origin validation (ROV)
- AS path prepending for traffic engineering
- Selective prefix advertisement

#### 3. Route Filtering and Policies
- Provider-specific route filters
- Community-based route control
- AS path filtering and manipulation
- Route leak prevention

#### 4. Multi-Provider Support
- Simultaneous peering with multiple providers
- Provider failover and load balancing
- Cross-provider route optimization
- BGP anycast support

#### 5. Monitoring and Health Checks
- BGP session health monitoring
- Route advertisement verification
- Prefix hijacking detection
- SLA monitoring per provider

## Implementation Details

### Files to Create/Modify
- `modules/byoip-bgp.nix` - BYOIP BGP peering module
- `lib/byoip-config.nix` - BYOIP configuration utilities
- `lib/provider-peering.nix` - Cloud provider peering templates

### BYOIP BGP Configuration Structure
```nix
services.gateway.byoip = {
  enable = true;
  
  providers = {
    aws = {
      asn = 16509;
      neighborIP = "169.254.0.1";
      localASN = 65000;
      
      prefixes = [
        {
          prefix = "203.0.113.0/24";
          communities = ["65000:100"];
          asPath = "65000";
        }
        {
          prefix = "198.51.100.0/24";
          communities = ["65000:200"];
          localPref = 200;
        }
      ];
      
      # Route filtering
      filters = {
        inbound = {
          allowCommunities = ["16509:*"];
          maxPrefixLength = 24;
        };
        outbound = {
          prependAS = 2;
          noExport = true;
        };
      };
      
      # Health monitoring
      monitoring = {
        enable = true;
        checkInterval = "30s";
        alertThreshold = 300; # seconds
      };
    };
    
    azure = {
      asn = 12076;
      neighborIP = "169.254.1.1";
      localASN = 65001;
      
      prefixes = ["20.0.0.0/16"];
      
      # Azure-specific settings
      serviceTags = ["AzureCloud" "AzureTrafficManager"];
    };
  };
  
  # Global BYOIP settings
  monitoring = {
    enable = true;
    prometheusPort = 9093;
    alertRules = [
      "bgp_session_down"
      "prefix_hijacking_detected"
    ];
  };
  
  security = {
    rov = {
      enable = true;
      strict = false; # Allow unknown origins initially
    };
  };
};
```

### Technical Specifications
- **BGP Version**: BGP-4 (RFC 4271) with extensions
- **Route Validation**: RPKI and ROA support
- **Security**: BGPsec integration (optional)
- **Scalability**: Support for 100k+ routes
- **Performance**: Sub-second convergence times

### Testing Requirements
- BGP session establishment and maintenance
- Route advertisement and withdrawal
- Provider failover scenarios
- Route filtering accuracy
- Security validation (no route leaks)

### Success Criteria
- Successful BGP peering with major cloud providers
- Reliable IP range advertisement
- <30 second convergence times
- Comprehensive monitoring and alerting
- Zero route leaks in production

### Business Value
- **Cost Optimization**: Avoid cloud provider IP advertisement fees
- **Control**: Full control over IP routing and traffic engineering
- **Flexibility**: Custom routing policies not available in managed services
- **Multi-Cloud**: Seamless operation across cloud providers

### Dependencies
- Requires FRR BGP module
- Integrates with routing and monitoring
- Uses existing security infrastructure

### Effort Estimate
- **Complexity**: High (BGP protocol expertise required)
- **Timeline**: 6-8 weeks
- **Team**: 2 developers (BGP expert + NixOS specialist)
- **Risk**: High (production network impact)

### Migration Guide
Detailed migration from cloud-managed BYOIP:
1. Obtain IP ranges and ASN from RIR
2. Configure BGP peering sessions
3. Set up route filtering and policies
4. Test advertisement and connectivity
5. Coordinate cutover with cloud provider
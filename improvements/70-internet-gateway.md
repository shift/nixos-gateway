# Internet Gateway Module

**Status: Pending**

## Description
Create an Internet Gateway module providing basic internet connectivity for virtual networks, equivalent to AWS Internet Gateway with integrated security and monitoring features.

## Requirements

### Current State
- Basic network interface management exists
- Firewall and routing modules available
- No dedicated Internet Gateway abstraction

### Improvements Needed

#### 1. Internet Gateway Core
- Default route management for internet access
- IGW attachment to virtual networks
- Route table integration
- Internet connectivity health checks

#### 2. Security Integration
- Security Groups equivalent (host-based rules)
- Network ACLs equivalent (subnet-based rules)
- Stateful packet inspection
- DDoS protection integration

#### 3. Traffic Management
- Inbound/outbound traffic separation
- Bandwidth monitoring and throttling
- Traffic prioritization
- Quality of Service (QoS) integration

#### 4. High Availability
- Multiple IGW instances for redundancy
- Automatic failover
- Load balancing across IGWs
- BGP-based failover (if applicable)

#### 5. Monitoring and Compliance
- Traffic analytics and reporting
- Security event logging
- Compliance monitoring (PCI DSS, etc.)
- Integration with SIEM systems

## Implementation Details

### Files to Create/Modify
- `modules/internet-gateway.nix` - Internet Gateway module
- `lib/igw-config.nix` - IGW configuration utilities
- `lib/security-groups.nix` - Security Groups implementation

### Internet Gateway Configuration Structure
```nix
services.gateway.internetGateway = {
  enable = true;
  
  gateways = [
    {
      name = "igw-primary";
      interface = "eth0";
      publicIP = "203.0.113.1";
      
      # Attached networks
      attachments = [
        {
          network = "vpc-main";
          subnets = ["10.0.1.0/24" "10.0.2.0/24"];
        }
      ];
      
      # Security
      securityGroups = [
        {
          name = "web-servers";
          rules = [
            {
              type = "ingress";
              protocol = "tcp";
              portRange = { from = 80; to = 80; };
              sources = ["0.0.0.0/0"];
            }
            {
              type = "ingress";
              protocol = "tcp";
              portRange = { from = 443; to = 443; };
              sources = ["0.0.0.0/0"];
            }
          ];
        }
      ];
      
      networkACLs = [
        {
          name = "public-subnet-acl";
          rules = [
            {
              ruleNumber = 100;
              type = "allow";
              protocol = "tcp";
              portRange = { from = 80; to = 80; };
              sources = ["0.0.0.0/0"];
            }
          ];
        }
      ];
    }
  ];
  
  # Global settings
  monitoring = {
    enable = true;
    trafficAnalytics = true;
    securityEvents = true;
  };
  
  ddosProtection = {
    enable = true;
    threshold = "10Gbps";
    actions = ["rate-limit" "block"];
  };
};
```

### Technical Specifications
- **Protocols**: IPv4/IPv6 routing, TCP/UDP/ICMP
- **Performance**: 10Gbps+ throughput
- **Security**: State-aware firewall with connection tracking
- **Scalability**: Support for 1000+ security group rules

### Testing Requirements
- Internet connectivity tests
- Security group rule enforcement
- Network ACL functionality
- High availability failover
- DDoS protection validation

### Success Criteria
- Full AWS Internet Gateway feature parity
- <5 second failover times
- 99.99% uptime for internet connectivity
- Comprehensive security logging
- Easy migration from AWS IGW

### Business Value
- **Cost Savings**: No AWS IGW charges (VPC attachment fees)
- **Security**: Advanced security features beyond AWS defaults
- **Monitoring**: Detailed traffic and security analytics
- **Flexibility**: Custom routing and security policies

### Dependencies
- Requires network and firewall modules
- Integrates with monitoring infrastructure
- Uses existing routing capabilities

### Effort Estimate
- **Complexity**: Medium (integration of existing components)
- **Timeline**: 3-4 weeks
- **Team**: 1-2 developers
- **Risk**: Low (leverages existing modules)

### Migration Guide
Step-by-step migration from AWS Internet Gateway:
1. Analyze current IGW configuration
2. Map security groups to equivalent rules
3. Configure IGW with proper attachments
4. Test connectivity and security
5. Update DNS and application configurations
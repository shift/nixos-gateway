# Transit Gateway Module

**Status: Pending**

## Description
Implement a Transit Gateway module providing centralized routing hub functionality for connecting multiple virtual networks (VPCs), equivalent to AWS Transit Gateway with advanced routing, attachment management, and route propagation features.

## Requirements

### Current State
- Basic routing and network modules exist
- VRF support implemented (Task 64)
- BGP routing enhancements available (Task 09)
- No centralized transit routing abstraction

### Improvements Needed

#### 1. Transit Gateway Core
- Centralized routing hub for multiple networks
- Attachment management (VPC, VPN, Direct Connect)
- Route table management and propagation
- Transit Gateway route domain isolation
- Multi-VPC connectivity through single gateway

#### 2. Attachment Management
- VPC attachment with subnet associations
- VPN attachment with tunnel management
- Direct Connect gateway attachment
- Attachment state management and monitoring
- Dynamic attachment lifecycle management

#### 3. Route Propagation and Tables
- Transit Gateway route tables
- Automatic route propagation from attachments
- Static route configuration
- Route filtering and blackhole routes
- Cross-attachment route advertisement

#### 4. Advanced Routing Features
- Transit Gateway peering for inter-region connectivity
- Route domain separation (similar to AWS route tables)
- BGP route propagation control
- Route priority and preference management
- Route health monitoring and failover

#### 5. Security and Compliance
- Attachment-level security policies
- Route-based access controls
- Traffic isolation between attachments
- Audit logging for route changes
- Compliance monitoring for network segmentation

#### 6. Monitoring and Observability
- Attachment health monitoring
- Route propagation analytics
- Traffic flow visibility
- Performance metrics collection
- Integration with existing monitoring stack

## Implementation Details

### Files to Create/Modify
- `modules/transit-gateway.nix` - Transit Gateway module
- `lib/transit-gateway-config.nix` - TGW configuration utilities
- `lib/attachment-manager.nix` - Attachment lifecycle management
- `lib/route-propagation.nix` - Route propagation logic

### Transit Gateway Configuration Structure
```nix
services.gateway.transitGateway = {
  enable = true;

  gateways = [
    {
      name = "tgw-central";
      asn = 64512;

      # Route tables
      routeTables = [
        {
          name = "spoke-routes";
          routes = [
            {
              destination = "10.0.0.0/8";
              type = "propagated";
              attachments = ["vpc-spoke-1" "vpc-spoke-2"];
            }
            {
              destination = "0.0.0.0/0";
              type = "static";
              nextHop = "igw-main";
            }
          ];
        }
      ];

      # Attachments
      attachments = {
        vpc = [
          {
            name = "vpc-hub";
            vpcId = "vpc-hub";
            subnetIds = ["subnet-hub-1" "subnet-hub-2"];
            routeTableId = "hub-routes";
            applianceMode = false;
            dnsSupport = true;
          }
          {
            name = "vpc-spoke-1";
            vpcId = "vpc-spoke-1";
            subnetIds = ["subnet-spoke-1a" "subnet-spoke-1b"];
            routeTableId = "spoke-routes";
            applianceMode = false;
            dnsSupport = true;
          }
        ];

        vpn = [
          {
            name = "vpn-branch-office";
            type = "ipsec";
            customerGatewayId = "cgw-branch";
            tunnelOptions = [
              {
                outsideIpAddress = "203.0.113.1";
                tunnelInsideCidr = "169.254.1.0/30";
                preSharedKey = "secret-key";
              }
            ];
            routeTableId = "spoke-routes";
          }
        ];

        directConnect = [
          {
            name = "dx-gateway-office";
            dxGatewayId = "dxgw-office";
            allowedPrefixes = ["192.168.0.0/16"];
            routeTableId = "spoke-routes";
          }
        ];
      };

      # Peering connections
      peerings = [
        {
          name = "tgw-peer-us-east";
          peerTransitGatewayId = "tgw-us-east-12345";
          peerRegion = "us-east-1";
          routeTableId = "inter-region-routes";
        }
      ];

      # Route propagation settings
      propagation = {
        enable = true;
        autoPropagate = true;
        filters = [
          {
            attachmentType = "vpc";
            routeFilter = "10.0.0.0/8";
          }
        ];
      };
    }
  ];

  # Global settings
  monitoring = {
    enable = true;
    routeAnalytics = true;
    attachmentHealth = true;
    flowLogs = true;
  };

  security = {
    enable = true;
    attachmentIsolation = true;
    routeValidation = true;
  };
};
```

### Technical Specifications
- **Protocols**: BGP, OSPF, static routing
- **Performance**: 10Gbps+ aggregate throughput
- **Attachments**: Support for 1000+ VPC attachments
- **Routes**: 10,000+ routes per route table
- **HA**: Active-active gateway instances

### Testing Requirements
- Multi-VPC connectivity tests
- Route propagation validation
- Attachment lifecycle management
- VPN tunnel establishment and failover
- Direct Connect integration
- Cross-region peering functionality
- Route filtering and security policies

### Success Criteria
- Full AWS Transit Gateway feature parity
- <30 second attachment provisioning
- 99.99% route propagation reliability
- Seamless VPN and Direct Connect integration
- Comprehensive route analytics and monitoring

### Business Value
- **Cost Optimization**: Eliminate AWS TGW hourly charges
- **Simplified Architecture**: Centralized routing management
- **Enhanced Security**: Advanced route filtering and isolation
- **Scalability**: Support for thousands of network attachments
- **Monitoring**: Detailed routing and traffic analytics

### Dependencies
- Requires VRF support (Task 64)
- Integrates with BGP routing (Task 09)
- Uses existing network and routing modules
- Depends on VPN and Direct Connect modules

### Effort Estimate
- **Complexity**: High (centralized routing system)
- **Timeline**: 6-8 weeks
- **Team**: 2-3 developers
- **Risk**: Medium (complex routing interactions)

### Migration Guide
Step-by-step migration from AWS Transit Gateway:
1. Analyze current TGW topology and attachments
2. Map VPC, VPN, and DX attachments to Nix configuration
3. Configure route tables and propagation rules
4. Set up monitoring and security policies
5. Test connectivity and route propagation
6. Update DNS and application routing configurations
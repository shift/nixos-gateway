# Transit Gateway Module

The Transit Gateway module provides centralized routing hub functionality for connecting multiple virtual networks (VPCs), equivalent to AWS Transit Gateway with advanced routing, attachment management, and route propagation features.

## Overview

The Transit Gateway acts as a central hub for routing traffic between multiple network segments, supporting:

- **Multi-VPC connectivity** through a single gateway
- **Attachment management** for VPC, VPN, and Direct Connect connections
- **Route propagation** and filtering
- **Route domain isolation** for security
- **BGP routing** with advanced policies

## Configuration

### Basic Setup

```nix
services.gateway.transitGateway = {
  enable = true;

  gateways = [
    {
      name = "tgw-central";
      asn = 64512;

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

      attachments = {
        vpc = [
          {
            name = "vpc-hub";
            vpcId = "vpc-hub";
            subnetIds = ["subnet-hub-1"];
            routeTableId = "spoke-routes";
          }
        ];
      };

      propagation = {
        enable = true;
        autoPropagate = true;
      };
    }
  ];

  monitoring = {
    enable = true;
    routeAnalytics = true;
    attachmentHealth = true;
  };

  security = {
    enable = true;
    attachmentIsolation = true;
  };
};
```

### Attachment Types

#### VPC Attachments

```nix
attachments.vpc = [
  {
    name = "vpc-spoke-1";
    vpcId = "vpc-spoke-1";
    subnetIds = ["subnet-spoke-1a" "subnet-spoke-1b"];
    routeTableId = "spoke-routes";
    applianceMode = false;
    dnsSupport = true;
  }
];
```

#### VPN Attachments

```nix
attachments.vpn = [
  {
    name = "vpn-branch";
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
```

#### Direct Connect Attachments

```nix
attachments.directConnect = [
  {
    name = "dx-office";
    dxGatewayId = "dxgw-office";
    allowedPrefixes = ["192.168.0.0/16"];
    routeTableId = "spoke-routes";
  }
];
```

## Route Propagation

Routes can be:

- **Static**: Manually configured routes
- **Propagated**: Automatically learned from attachments
- **Blackhole**: Routes that drop traffic

Propagation rules control how routes are shared between attachments.

## Security Features

- **Attachment isolation**: Traffic between attachments is isolated by default
- **Route validation**: Ensures route consistency and prevents conflicts
- **Access controls**: Fine-grained control over route advertisement

## Monitoring

The module provides comprehensive monitoring:

- **Route analytics**: Track route changes and propagation
- **Attachment health**: Monitor connection status
- **Flow logs**: Capture traffic patterns
- **Performance metrics**: Route propagation latency and success rates

## Integration

The Transit Gateway integrates with:

- **VRF**: Uses VRFs for route domain isolation
- **FRR**: BGP routing protocol support
- **Firewall**: Attachment-level traffic filtering
- **Monitoring**: Centralized logging and alerting

## Files

- `modules/transit-gateway.nix`: Main module
- `lib/tgw-config.nix`: Configuration utilities
- `lib/tgw-routing.nix`: Routing logic
- `tests/transit-gateway-test.nix`: Test suite

## Dependencies

- VRF support (Task 64)
- BGP routing (Task 09)
- FRR routing daemon
- Network modules</content>
<parameter name="filePath">docs/transit-gateway.md
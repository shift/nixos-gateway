# VPC Endpoint Gateway Support

**Status: Pending**

## Description
Implement VPC Endpoint Gateway functionality for private connectivity to cloud services without internet exposure, providing secure, private access to cloud provider services equivalent to AWS VPC Endpoints.

## Requirements

### Current State
- All cloud service traffic routed through internet gateways
- No private connectivity options for cloud services
- Public IP exposure for cloud service access
- Security concerns with internet-based cloud service communication

### Improvements Needed

#### 1. VPC Endpoint Gateway Creation
- Automated VPC endpoint gateway device creation
- Support for Gateway Endpoints (S3, DynamoDB style)
- Support for Interface Endpoints (EC2, Lambda style)
- Endpoint service configuration management

#### 2. Private DNS Resolution
- Private DNS zone integration for endpoint services
- DNS resolution override for cloud service domains
- Split-horizon DNS for private vs public access
- Custom DNS resolver configuration for endpoints

#### 3. Routing and Security
- Automatic route table updates for endpoint traffic
- VPC endpoint security groups and policies
- Traffic flow isolation to prevent internet exposure
- Endpoint-specific firewall rules and access controls

#### 4. Cloud Service Integration
- AWS service endpoint support (S3, EC2, Lambda, etc.)
- Azure service endpoint equivalents
- GCP Private Service Connect integration
- Multi-cloud endpoint management

#### 5. Monitoring and Management
- Endpoint health monitoring and status tracking
- Traffic flow analytics for endpoint usage
- Cost optimization through private connectivity
- Endpoint lifecycle management

## Implementation Details

### Files to Create
- `modules/vpc-endpoints.nix` - VPC endpoint management module
- `lib/vpc-endpoint-config.nix` - Endpoint configuration functions
- `lib/cloud-service-endpoints.nix` - Cloud service endpoint definitions

### New Configuration Options
```nix
networking.vpcEndpoints = lib.mkOption {
  type = lib.types.attrsOf (lib.types.submodule {
    options = {
      enable = lib.mkEnableOption "VPC Endpoint";
      
      type = lib.mkOption {
        type = lib.types.enum ["gateway" "interface"];
        description = "Endpoint type: gateway or interface";
      };
      
      service = lib.mkOption {
        type = lib.types.str;
        description = "Cloud service name (e.g., s3, ec2, lambda)";
      };
      
      provider = lib.mkOption {
        type = lib.types.enum ["aws" "azure" "gcp"];
        description = "Cloud provider";
      };
      
      region = lib.mkOption {
        type = lib.types.str;
        description = "Cloud region for the endpoint";
      };
      
      vpcId = lib.mkOption {
        type = lib.types.str;
        description = "VPC identifier for endpoint attachment";
      };
      
      subnets = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = "Subnets for interface endpoints";
        default = [];
      };
      
      securityGroups = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = "Security groups for interface endpoints";
        default = [];
      };
      
      privateDns = {
        enable = lib.mkEnableOption "Private DNS for endpoint";
        hostname = lib.mkOption {
          type = lib.types.str;
          description = "Custom hostname for private DNS";
        };
      };
      
      policy = lib.mkOption {
        type = lib.types.str;
        description = "IAM policy document for endpoint access control";
        default = "";
      };
      
      tags = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        description = "Tags for endpoint resource";
        default = {};
      };
    };
  });
  description = "VPC Endpoint configurations for private cloud service access";
};

networking.vpcEndpointRoutes = lib.mkOption {
  type = lib.types.attrsOf (lib.types.submodule {
    options = {
      routeTableId = lib.mkOption {
        type = lib.types.str;
        description = "Route table to update with endpoint routes";
      };
      
      endpoints = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = "List of VPC endpoint IDs to add routes for";
      };
    };
  });
  description = "Route table configurations for VPC endpoint traffic";
};
```

### Integration Points
- Network module for route table management
- DNS module for private DNS resolution
- Firewall module for endpoint security policies
- Monitoring module for endpoint health tracking
- Cloud provider APIs for endpoint lifecycle management

## Testing Requirements
- Endpoint creation and deletion lifecycle
- Private DNS resolution testing
- Traffic routing verification (no internet exposure)
- Multi-cloud endpoint configuration
- Security policy enforcement
- High availability endpoint scenarios

## Dependencies
- Cloud provider SDKs/APIs (awscli, azure-cli, gcloud)
- DNS resolution capabilities
- Route table management
- Network interface creation for interface endpoints

## Estimated Effort
- High (complex cloud integration)
- 4-5 weeks implementation
- 2 weeks testing and cloud provider validation

## Success Criteria
- Private connectivity to cloud services without internet exposure
- Automatic DNS resolution for service endpoints
- Proper routing table updates for endpoint traffic
- Security policies correctly applied to endpoints
- Multi-cloud provider support functional
- Monitoring and alerting for endpoint status
{ lib }:

# VPC Endpoint Configuration Library
# Provides functions for managing VPC endpoint configurations

rec {
  # Cloud service endpoint definitions
  cloudServices = {
    aws = {
      s3 = {
        serviceName = "s3";
        gatewayEndpoint = true;
        interfaceEndpoint = false;
        regions = {
          "us-east-1" = "com.amazonaws.us-east-1.s3";
          "us-west-2" = "com.amazonaws.us-west-2.s3";
          "eu-west-1" = "com.amazonaws.eu-west-1.s3";
        };
      };
      dynamodb = {
        serviceName = "dynamodb";
        gatewayEndpoint = true;
        interfaceEndpoint = false;
        regions = {
          "us-east-1" = "com.amazonaws.us-east-1.dynamodb";
          "us-west-2" = "com.amazonaws.us-west-2.dynamodb";
          "eu-west-1" = "com.amazonaws.eu-west-1.dynamodb";
        };
      };
      ec2 = {
        serviceName = "ec2";
        gatewayEndpoint = false;
        interfaceEndpoint = true;
        regions = {
          "us-east-1" = "com.amazonaws.us-east-1.ec2";
          "us-west-2" = "com.amazonaws.us-west-2.ec2";
          "eu-west-1" = "com.amazonaws.eu-west-1.ec2";
        };
      };
      lambda = {
        serviceName = "lambda";
        gatewayEndpoint = false;
        interfaceEndpoint = true;
        regions = {
          "us-east-1" = "com.amazonaws.us-east-1.lambda";
          "us-west-2" = "com.amazonaws.us-west-2.lambda";
          "eu-west-1" = "com.amazonaws.eu-west-1.lambda";
        };
      };
    };
    azure = {
      storage = {
        serviceName = "storage";
        gatewayEndpoint = true;
        interfaceEndpoint = false;
        regions = {
          "eastus" = "blob.core.windows.net";
          "westus2" = "blob.core.windows.net";
          "westeurope" = "blob.core.windows.net";
        };
      };
    };
    gcp = {
      storage = {
        serviceName = "storage";
        gatewayEndpoint = true;
        interfaceEndpoint = false;
        regions = {
          "us-central1" = "storage.googleapis.com";
          "europe-west1" = "storage.googleapis.com";
        };
      };
    };
  };

  # Get service endpoint for provider, service, and region
  getServiceEndpoint =
    provider: service: region:
    let
      providerServices = cloudServices.${provider} or { };
      serviceConfig = providerServices.${service} or { };
      regionEndpoints = serviceConfig.regions or { };
    in
    regionEndpoints.${region} or null;

  # Check if service supports gateway endpoints
  supportsGatewayEndpoint =
    provider: service:
    let
      providerServices = cloudServices.${provider} or { };
      serviceConfig = providerServices.${service} or { };
    in
    serviceConfig.gatewayEndpoint or false;

  # Check if service supports interface endpoints
  supportsInterfaceEndpoint =
    provider: service:
    let
      providerServices = cloudServices.${provider} or { };
      serviceConfig = providerServices.${service} or { };
    in
    serviceConfig.interfaceEndpoint or false;

  # Generate endpoint configuration
  mkEndpointConfig =
    {
      name,
      type,
      service,
      provider,
      region,
      vpcId,
      subnets ? [ ],
      securityGroups ? [ ],
      privateDns ? {
        enable = false;
        hostname = null;
      },
      policy ? "",
      tags ? { },
    }:
    let
      # Validate configuration
      validation = {
        validType = lib.elem type [
          "gateway"
          "interface"
        ];
        validProvider = lib.elem provider [
          "aws"
          "azure"
          "gcp"
        ];
        hasVpcId = vpcId != null && vpcId != "";
        hasSubnetsForInterface = type == "gateway" || (type == "interface" && subnets != [ ]);
        hasSecurityGroupsForInterface = type == "gateway" || (type == "interface" && securityGroups != [ ]);
        supportsEndpointType =
          if type == "gateway" then
            supportsGatewayEndpoint provider service
          else
            supportsInterfaceEndpoint provider service;
      };
    in
    {
      inherit
        name
        type
        service
        provider
        region
        vpcId
        subnets
        securityGroups
        privateDns
        policy
        tags
        ;

      # Generate service name
      serviceName = getServiceEndpoint provider service region;

      # Check if configuration is valid
      isValid =
        validation.validType
        && validation.validProvider
        && validation.hasVpcId
        && validation.hasSubnetsForInterface
        && validation.hasSecurityGroupsForInterface
        && validation.supportsEndpointType;
    };

  # Generate route table entries for gateway endpoints
  mkGatewayRoutes =
    endpointConfig: routeTableId:
    if endpointConfig.type == "gateway" then
      [
        {
          routeTableId = routeTableId;
          destinationCidrBlock = "0.0.0.0/0";
          vpcEndpointId = endpointConfig.name;
        }
      ]
    else
      [ ];

  # Generate security group rules for interface endpoints
  mkInterfaceSecurityRules =
    endpointConfig:
    if endpointConfig.type == "interface" then
      lib.concatMap (sg: [
        {
          securityGroupId = sg;
          type = "ingress";
          fromPort = 443;
          toPort = 443;
          protocol = "tcp";
          cidrBlocks = [ "0.0.0.0/0" ];
          description = "HTTPS for VPC endpoint ${endpointConfig.name}";
        }
        {
          securityGroupId = sg;
          type = "ingress";
          fromPort = 80;
          toPort = 80;
          protocol = "tcp";
          cidrBlocks = [ "0.0.0.0/0" ];
          description = "HTTP for VPC endpoint ${endpointConfig.name}";
        }
      ]) endpointConfig.securityGroups
    else
      [ ];

  # Generate endpoint policy
  mkEndpointPolicy =
    endpointConfig:
    if endpointConfig.policy != "" then
      endpointConfig.policy
    else
      builtins.toJSON {
        Version = "2012-10-17";
        Statement = [
          {
            Effect = "Allow";
            Principal = "*";
            Action = "*";
            Resource = "*";
          }
        ];
      };
}

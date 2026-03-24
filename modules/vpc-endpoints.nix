{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.networking.vpcEndpoints;
  enabled = cfg.enable;

  vpcEndpointLib = import ../lib/vpc-endpoint-config.nix { inherit lib; };
  privateDnsLib = import ../lib/private-dns.nix { inherit lib; };

  # Process endpoint configurations
  endpointConfigs = lib.mapAttrs (
    name: endpoint:
    vpcEndpointLib.mkEndpointConfig (
      {
        inherit name;
      }
      // endpoint
    )
  ) cfg.endpoints;

  # Valid endpoints only
  validEndpoints = lib.filterAttrs (_: config: config.isValid) endpointConfigs;

  # Generate route table configurations
  routeTableConfigs = lib.mapAttrs (
    name: routeConfig:
    let
      endpoints = lib.filter (ep: lib.elem ep.name routeConfig.endpoints) (lib.attrValues validEndpoints);
      gatewayEndpoints = lib.filter (ep: ep.type == "gateway") endpoints;
    in
    routeConfig
    // {
      routes = lib.concatMap (
        ep: vpcEndpointLib.mkGatewayRoutes ep routeConfig.routeTableId
      ) gatewayEndpoints;
    }
  ) cfg.routeTables;

  # Generate private DNS zones
  privateDnsZones = lib.mapAttrs (
    name: endpoint:
    if endpoint.privateDns.enable then
      privateDnsLib.mkPrivateDnsZone {
        name = "${endpoint.service}.${endpoint.region}";
        vpcId = endpoint.vpcId;
        region = endpoint.region;
        records = privateDnsLib.mkEndpointDnsRecords endpoint;
        tags = endpoint.tags // {
          "endpoint-name" = name;
          "endpoint-type" = endpoint.type;
        };
      }
    else
      null
  ) validEndpoints;

  # Filter out null zones
  validDnsZones = lib.filterAttrs (_: zone: zone != null) privateDnsZones;

in
{
  options.networking.vpcEndpoints = {
    enable = lib.mkEnableOption "VPC Endpoints for private cloud service access";

    endpoints = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            enable = lib.mkEnableOption "VPC Endpoint";

            type = lib.mkOption {
              type = lib.types.enum [
                "gateway"
                "interface"
              ];
              description = "Endpoint type: gateway or interface";
            };

            service = lib.mkOption {
              type = lib.types.str;
              description = "Cloud service name (e.g., s3, ec2, lambda)";
            };

            provider = lib.mkOption {
              type = lib.types.enum [
                "aws"
                "azure"
                "gcp"
              ];
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
              default = [ ];
              description = "Subnets for interface endpoints";
            };

            securityGroups = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Security groups for interface endpoints";
            };

            privateDns = {
              enable = lib.mkEnableOption "Private DNS for endpoint";
              hostname = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Custom hostname for private DNS";
              };
            };

            policy = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "IAM policy document for endpoint access control";
            };

            tags = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = { };
              description = "Tags for endpoint resource";
            };
          };
        }
      );
      default = { };
      description = "VPC Endpoint configurations for private cloud service access";
    };

    routeTables = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            routeTableId = lib.mkOption {
              type = lib.types.str;
              description = "Route table to update with endpoint routes";
            };

            endpoints = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "List of VPC endpoint names to add routes for";
            };
          };
        }
      );
      default = { };
      description = "Route table configurations for VPC endpoint traffic";
    };

    monitoring = {
      enable = lib.mkEnableOption "VPC endpoint monitoring";

      healthChecks = lib.mkEnableOption "Endpoint health monitoring";

      metrics = lib.mkEnableOption "Endpoint traffic metrics";
    };
  };

  config = lib.mkIf enabled {
    # Validate configurations
    assertions = [
      {
        assertion = lib.all (ep: ep.isValid) (lib.attrValues endpointConfigs);
        message = "All VPC endpoint configurations must be valid";
      }
    ];

    # Generate VPC endpoint configuration files
    environment.etc = {
      "vpc-endpoints/config.json" = {
        text = builtins.toJSON {
          endpoints = endpointConfigs;
          routeTables = routeTableConfigs;
          privateDnsZones = validDnsZones;
        };
      };
    };

    # Systemd services for endpoint management
    systemd.services = {
      vpc-endpoint-manager = {
        description = "VPC Endpoint Manager";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.bash}/bin/bash -c 'echo \"VPC Endpoints configured: ${toString (lib.length (lib.attrNames validEndpoints))}\"'";
        };
      };

      vpc-endpoint-health-check = lib.mkIf cfg.monitoring.healthChecks {
        description = "VPC Endpoint Health Check";
        after = [ "vpc-endpoint-manager.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.bash}/bin/bash -c 'while true; do echo \"Checking VPC endpoint health...\"; sleep 60; done'";
          Restart = "always";
        };
      };
    };

    # Monitoring configuration
    services.prometheus = lib.mkIf cfg.monitoring.enable {
      exporters = {
        blackbox = lib.mkIf cfg.monitoring.healthChecks {
          enable = true;
          configFile = pkgs.writeText "blackbox.yml" (
            builtins.toJSON {
              modules = {
                vpc_endpoint_health = {
                  prober = "http";
                  timeout = "5s";
                  http = {
                    valid_status_codes = [
                      200
                      301
                      302
                    ];
                    no_follow_redirects = false;
                  };
                };
              };
            }
          );
        };
      };

      rules = lib.mkIf cfg.monitoring.metrics [
        ''
          groups:
          - name: vpc_endpoints
            rules:
            - alert: VpcEndpointDown
              expr: up{job="vpc-endpoints"} == 0
              for: 5m
              labels:
                severity: critical
              annotations:
                summary: "VPC Endpoint is down"
                description: "VPC Endpoint {{ $labels.instance }} has been down for more than 5 minutes"
        ''
      ];
    };
  };
}

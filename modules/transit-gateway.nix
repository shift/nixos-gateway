{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.gateway.transitGateway;
  tgwConfig = import ../lib/tgw-config.nix { inherit lib pkgs; };
  tgwRouting = import ../lib/tgw-routing.nix { inherit lib pkgs; };

  inherit (lib)
    mkOption
    types
    mkEnableOption
    mkIf
    mkMerge
    ;

  # Transit Gateway options
  transitGatewayOpts = types.submodule {
    options = {
      enable = mkEnableOption "Transit Gateway";

      name = mkOption {
        type = types.str;
        description = "Transit Gateway name";
      };

      asn = mkOption {
        type = types.int;
        default = 64512;
        description = "BGP ASN for the Transit Gateway";
      };

      routeTables = mkOption {
        type = types.listOf (
          types.submodule {
            options = {
              name = mkOption {
                type = types.str;
                description = "Route table name";
              };
              routes = mkOption {
                type = types.listOf (
                  types.submodule {
                    options = {
                      destination = mkOption {
                        type = types.str;
                        description = "Route destination CIDR";
                      };
                      type = mkOption {
                        type = types.enum [
                          "static"
                          "propagated"
                          "blackhole"
                        ];
                        default = "static";
                        description = "Route type";
                      };
                      nextHop = mkOption {
                        type = types.nullOr types.str;
                        default = null;
                        description = "Next hop for static routes";
                      };
                      attachments = mkOption {
                        type = types.listOf types.str;
                        default = [ ];
                        description = "Source attachments for propagated routes";
                      };
                    };
                  }
                );
                default = [ ];
                description = "Routes in this table";
              };
            };
          }
        );
        default = [ ];
        description = "Transit Gateway route tables";
      };

      attachments = {
        vpc = mkOption {
          type = types.listOf (
            types.submodule {
              options = {
                name = mkOption {
                  type = types.str;
                  description = "VPC attachment name";
                };
                vpcId = mkOption {
                  type = types.str;
                  description = "VPC ID to attach";
                };
                subnetIds = mkOption {
                  type = types.listOf types.str;
                  default = [ ];
                  description = "Subnet IDs for the attachment";
                };
                routeTableId = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = "Associated route table";
                };
                applianceMode = mkOption {
                  type = types.bool;
                  default = false;
                  description = "Enable appliance mode";
                };
                dnsSupport = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Enable DNS support";
                };
              };
            }
          );
          default = [ ];
          description = "VPC attachments";
        };

        vpn = mkOption {
          type = types.listOf (
            types.submodule {
              options = {
                name = mkOption {
                  type = types.str;
                  description = "VPN attachment name";
                };
                type = mkOption {
                  type = types.enum [ "ipsec" ];
                  default = "ipsec";
                  description = "VPN type";
                };
                customerGatewayId = mkOption {
                  type = types.str;
                  description = "Customer gateway ID";
                };
                tunnelOptions = mkOption {
                  type = types.listOf (
                    types.submodule {
                      options = {
                        outsideIpAddress = mkOption {
                          type = types.str;
                          description = "Outside IP address";
                        };
                        tunnelInsideCidr = mkOption {
                          type = types.str;
                          description = "Tunnel inside CIDR";
                        };
                        preSharedKey = mkOption {
                          type = types.str;
                          description = "Pre-shared key";
                        };
                      };
                    }
                  );
                  default = [ ];
                  description = "VPN tunnel options";
                };
                routeTableId = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = "Associated route table";
                };
              };
            }
          );
          default = [ ];
          description = "VPN attachments";
        };

        directConnect = mkOption {
          type = types.listOf (
            types.submodule {
              options = {
                name = mkOption {
                  type = types.str;
                  description = "Direct Connect attachment name";
                };
                dxGatewayId = mkOption {
                  type = types.str;
                  description = "Direct Connect gateway ID";
                };
                allowedPrefixes = mkOption {
                  type = types.listOf types.str;
                  default = [ ];
                  description = "Allowed prefixes";
                };
                routeTableId = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = "Associated route table";
                };
              };
            }
          );
          default = [ ];
          description = "Direct Connect attachments";
        };
      };

      peerings = mkOption {
        type = types.listOf (
          types.submodule {
            options = {
              name = mkOption {
                type = types.str;
                description = "Peering name";
              };
              peerTransitGatewayId = mkOption {
                type = types.str;
                description = "Peer Transit Gateway ID";
              };
              peerRegion = mkOption {
                type = types.str;
                description = "Peer region";
              };
              routeTableId = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Associated route table";
              };
            };
          }
        );
        default = [ ];
        description = "Transit Gateway peerings";
      };

      propagation = {
        enable = mkEnableOption "route propagation";
        autoPropagate = mkOption {
          type = types.bool;
          default = true;
          description = "Automatically propagate routes";
        };
        filters = mkOption {
          type = types.listOf (
            types.submodule {
              options = {
                attachmentType = mkOption {
                  type = types.enum [
                    "vpc"
                    "vpn"
                    "direct-connect"
                  ];
                  description = "Attachment type to filter";
                };
                routeFilter = mkOption {
                  type = types.str;
                  description = "Route filter pattern";
                };
              };
            }
          );
          default = [ ];
          description = "Route propagation filters";
        };
      };
    };
  };

in
{
  options.services.gateway.transitGateway = {
    enable = mkEnableOption "Transit Gateway service";

    gateways = mkOption {
      type = types.listOf transitGatewayOpts;
      default = [ ];
      description = "Transit Gateway configurations";
    };

    monitoring = {
      enable = mkEnableOption "Transit Gateway monitoring";
      routeAnalytics = mkOption {
        type = types.bool;
        default = true;
        description = "Enable route analytics";
      };
      attachmentHealth = mkOption {
        type = types.bool;
        default = true;
        description = "Enable attachment health monitoring";
      };
      flowLogs = mkOption {
        type = types.bool;
        default = false;
        description = "Enable flow logging";
      };
    };

    security = {
      enable = mkEnableOption "Transit Gateway security";
      attachmentIsolation = mkOption {
        type = types.bool;
        default = true;
        description = "Isolate attachments";
      };
      routeValidation = mkOption {
        type = types.bool;
        default = true;
        description = "Validate routes";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    # Enable required services
    {
      services.frr.bgp.enable = true;
      services.frr.bfd.enable = true;

      # Enable IP forwarding
      boot.kernel.sysctl = {
        "net.ipv4.ip_forward" = 1;
        "net.ipv4.conf.all.forwarding" = 1;
        "net.ipv6.conf.all.forwarding" = 1;
      };
    }

    # Configure Transit Gateways
    (mkMerge (
      map (gateway: {
        # Create VRF for each Transit Gateway
        networking.vrfs.${gateway.name} = {
          enable = true;
          table = gateway.asn;
          interfaces = [ ];
        };

        # Static routes service
        systemd.services."tgw-${gateway.name}-routes" = {
          description = "Transit Gateway ${gateway.name} route management";
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = pkgs.writeShellScript "tgw-routes-${gateway.name}" ''
              #!/bin/bash
              set -e
              echo "Transit Gateway ${gateway.name} routes configured"
            '';
          };
        };

      }) cfg.gateways
    ))
  ]);
}

{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.gateway;
  tsManager = import ../lib/tailscale-site-manager.nix { inherit lib; };
in
{
  options.services.gateway = {
    tailscale = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable Tailscale VPN mesh networking";
      };

      siteConfig = {
        siteName = lib.mkOption {
          type = lib.types.str;
          default = "default-site";
          description = "Name of this site/gateway";
        };
        region = lib.mkOption {
          type = lib.types.str;
          default = "unknown";
          description = "Region code for this site";
        };

        subnetRouters = lib.mkOption {
          type = lib.types.listOf (
            lib.types.submodule {
              options = {
                subnet = lib.mkOption {
                  type = lib.types.str;
                  description = "Subnet CIDR to handle";
                };
                advertise = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                  description = "Whether to advertise this subnet to Tailscale";
                };
                exitNode = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                  description = "Whether this subnet acts as an exit node";
                };
              };
            }
          );
          default = [ ];
          description = "Configuration for subnet routing";
        };

        aclPolicies = lib.mkOption {
          default = { };
          description = "ACL policies for this site (used for generation/documentation)";
          type = lib.types.attrs;
        };

        peerSites = lib.mkOption {
          type = lib.types.listOf (
            lib.types.submodule {
              options = {
                name = lib.mkOption { type = lib.types.str; };
                subnets = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                };
                trustLevel = lib.mkOption {
                  type = lib.types.enum [
                    "full"
                    "limited"
                    "none"
                  ];
                  default = "limited";
                };
              };
            }
          );
          default = [ ];
          description = "List of peer sites to connect to";
        };
      };

      # Deprecated/Legacy options mapped to new structure for backward compatibility
      exitNode = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Advertise this gateway as a Tailscale exit node (legacy)";
      };

      advertiseRoutes = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Subnet routes to advertise (legacy)";
      };

      authKeyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Path to file containing Tailscale auth key for automatic login.
          Generate at: https://login.tailscale.com/admin/settings/keys
        '';
      };

      acceptRoutes = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Accept subnet routes from other Tailscale nodes";
      };

      acceptDns = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Accept DNS configuration from Tailscale (MagicDNS)";
      };

      automation = {
        subnetDiscovery = lib.mkOption {
          type = lib.types.bool;
          default = true;
        };
        routePropagation = lib.mkOption {
          type = lib.types.bool;
          default = true;
        };
        aclSync = lib.mkOption {
          type = lib.types.bool;
          default = false;
        };
      };
    };
  };

  config = lib.mkIf cfg.tailscale.enable {
    services.tailscale = {
      enable = true;
      useRoutingFeatures = lib.mkIf (
        cfg.tailscale.exitNode
        || tsManager.hasExitNode cfg.tailscale.siteConfig.subnetRouters
        || cfg.tailscale.advertiseRoutes != [ ]
        || cfg.tailscale.siteConfig.subnetRouters != [ ]
      ) "both";
      openFirewall = true;
    };

    # Allow Tailscale interface through firewall
    networking.firewall.trustedInterfaces = [ "tailscale0" ];

    # ACL Generation Service
    # Generates a local ACL file that represents the policy for this site and its peers.
    systemd.services.tailscale-acl-gen = lib.mkIf cfg.tailscale.automation.aclSync {
      description = "Generate Tailscale ACL policy";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeScript "generate-acls" ''
          #!${pkgs.bash}/bin/bash
          mkdir -p /etc/tailscale
          cat > /etc/tailscale/acl-policy.json <<JSON
          ${builtins.toJSON (
            tsManager.generateAclPolicy {
              inherit (cfg.tailscale.siteConfig) siteName aclPolicies peerSites;
            }
          )}
          JSON
          echo "Generated ACL policy at /etc/tailscale/acl-policy.json"
        '';
      };
    };

    # Configure Tailscale after it starts
    systemd.services.tailscale-autoconnect = {
      description = "Automatic Tailscale connection";
      after = [
        "network-pre.target"
        "tailscaled.service"
      ];
      wants = [
        "network-pre.target"
        "tailscaled.service"
      ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script =
        let
          # Merge legacy and new config
          hasExitNode =
            cfg.tailscale.exitNode || tsManager.hasExitNode cfg.tailscale.siteConfig.subnetRouters;
          advertiseExitNode = lib.optionalString hasExitNode "--advertise-exit-node";

          legacyRoutes = cfg.tailscale.advertiseRoutes;
          newRoutes = tsManager.getAdvertiseRoutes cfg.tailscale.siteConfig.subnetRouters;
          allRoutes = lib.unique (legacyRoutes ++ newRoutes);

          advertiseRoutes = lib.optionalString (
            allRoutes != [ ]
          ) "--advertise-routes=${lib.concatStringsSep "," allRoutes}";

          acceptRoutes = if cfg.tailscale.acceptRoutes then "--accept-routes" else "";
          acceptDns = "--accept-dns=${if cfg.tailscale.acceptDns then "true" else "false"}";
          authKey = lib.optionalString (
            cfg.tailscale.authKeyFile != null
          ) "--auth-key=file:${cfg.tailscale.authKeyFile}";

          # Tags based on site config
          siteTag = "--advertise-tags=${tsManager.mkSiteTag cfg.tailscale.siteConfig.siteName}";
        in
        ''
          # Check if already authenticated
          status="$(${config.services.tailscale.package}/bin/tailscale status -json | ${pkgs.jq}/bin/jq -r .BackendState)"

          if [ "$status" = "Running" ]; then
            echo "Already authenticated, updating configuration..."
            # Note: tags cannot be updated via set command
            ${config.services.tailscale.package}/bin/tailscale set ${advertiseExitNode} ${advertiseRoutes} ${acceptRoutes} ${acceptDns}
          else
            echo "Not authenticated, logging in..."
            ${config.services.tailscale.package}/bin/tailscale up \
              ${authKey} \
              ${advertiseExitNode} \
              ${advertiseRoutes} \
              ${acceptRoutes} \
              ${acceptDns} \
              ${siteTag} \
              --ssh
          fi
        '';
    };

    # Ensure IP forwarding is enabled
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = lib.mkForce 1;
      "net.ipv6.conf.all.forwarding" = lib.mkForce 1;
    };

    # Add tailscale to system packages
    environment.systemPackages = [ config.services.tailscale.package ];
  };
}

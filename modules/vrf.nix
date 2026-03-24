{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.networking.vrfs;
  vrfConfig = import ../lib/vrf-config.nix { inherit lib pkgs; };
  vrfRouting = import ../lib/vrf-routing.nix { inherit lib pkgs; };
  inherit (lib)
    mkOption
    types
    mkEnableOption
    mkIf
    mkMerge
    ;

  vrfOpts = types.submodule {
    options = {
      enable = mkEnableOption "VRF";

      interfaces = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Interfaces assigned to this VRF";
      };

      table = mkOption {
        type = types.int;
        description = "Routing table number for this VRF";
      };

      routing = {
        enable = mkEnableOption "VRF routing protocols";

        bgp = {
          enable = mkEnableOption "VRF BGP";
          asn = mkOption {
            type = types.int;
            default = 65000;
          };
          routerId = mkOption {
            type = types.str;
            default = "1.1.1.1";
          };
          neighbors = mkOption {
            type = types.attrsOf (
              types.submodule {
                options = {
                  remoteAs = mkOption { type = types.int; };
                };
              }
            );
            default = { };
          };
        };

        static = mkOption {
          type = types.listOf (
            types.submodule {
              options = {
                destination = mkOption { type = types.str; };
                gateway = mkOption { type = types.str; };
                metric = mkOption {
                  type = types.int;
                  default = 100;
                };
              };
            }
          );
          default = [ ];
        };
      };

      firewall = {
        enable = mkEnableOption "VRF firewall";
        rules = mkOption {
          type = types.listOf types.str;
          default = [ ];
        };
      };
    };
  };

in
{
  options.networking.vrfs = mkOption {
    type = types.attrsOf vrfOpts;
    default = { };
    description = "Virtual Routing and Forwarding instances";
  };

  config = mkIf (cfg != { }) {
    # Validate configuration
    assertions = [
      {
        assertion = vrfConfig.validateVrfConfig cfg;
        message = "VRF routing table IDs must be unique";
      }
    ];

    # Enable IP forwarding
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
      "net.ipv4.conf.all.forwarding" = 1;
      "net.ipv4.conf.default.forwarding" = 1;
      "net.ipv6.conf.all.forwarding" = 1;

      # Enable VRF strict mode
      "net.vrf.strict_mode" = 1;
    };

    # Configure network devices
    systemd.network.netdevs =
      let
        enabledVrfs = lib.filterAttrs (n: v: v.enable) cfg;
      in
      lib.mapAttrs' (
        name: vrf: lib.nameValuePair "10-vrf-${name}" (vrfConfig.mkVrfDevice name vrf.table)
      ) enabledVrfs;

    # Configure interface memberships (this interacts with existing networkd config)
    # In a real implementation we would need to merge this carefully
    systemd.network.networks = lib.mkMerge (
      lib.flatten (
        lib.mapAttrsToList (
          vrfName: vrf:
          if vrf.enable then
            map (iface: {
              "30-${iface}-vrf" = {
                matchConfig.Name = iface;
                networkConfig.VRF = vrfName;
              };
            }) vrf.interfaces
          else
            [ ]
        ) cfg
      )
    );

    # Create setup service for routing rules
    systemd.services.vrf-setup = {
      description = "VRF Routing Setup";
      after = [
        "network.target"
        "systemd-networkd-wait-online.service"
      ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script =
        let
          enabledVrfs = lib.filterAttrs (n: v: v.enable) cfg;
        in
        ''
          echo "Setting up VRFs..."
          ${lib.concatStringsSep "\n" (
            lib.mapAttrsToList (name: vrf: ''
              # Setup rules for ${name} (table ${toString vrf.table})
              ip rule add l3mdev-table ${toString vrf.table} || true

              # Static routes
              ${lib.concatMapStringsSep "\n" (
                route:
                "ip route add ${route.destination} via ${route.gateway} table ${toString vrf.table} metric ${toString route.metric} || true"
              ) vrf.routing.static}
            '') enabledVrfs
          )}
          echo "VRF setup completed"
        '';
    };
  };
}

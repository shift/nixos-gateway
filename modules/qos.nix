{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.gateway.qos;
  gatewayCfg = config.services.gateway;
  trafficClassifier = import ../lib/traffic-classifier.nix { inherit lib; };

  redIfaces = gatewayCfg.redInterfaces;
  # greenIfaces = gatewayCfg.greenInterfaces; # Not currently used for advanced shaping, focusing on WAN egress/ingress
  wwanIface = if gatewayCfg.interfaces ? wwan then gatewayCfg.interfaces.wwan else null;

  getInterfaceSpeed =
    iface:
    if cfg.interfaceSpeeds ? ${iface} then
      cfg.interfaceSpeeds.${iface}
    else if wwanIface != null && iface == wwanIface then
      {
        download = "10Mbit";
        upload = "1500Kbit";
      }
    else
      {
        download = "1Gbit";
        upload = "1Gbit";
      };

  getOverhead =
    iface: if wwanIface != null && iface == wwanIface then "overhead 64 atm" else "overhead 38";

  # Setup HTB root with CAKE leaves
  setupWanQoS = iface: speeds: ''
    if ${pkgs.iproute2}/bin/ip link show ${iface} >/dev/null 2>&1; then
      echo "Setting up Advanced QoS on ${iface}..."
      
      # Clear existing Qdiscs
      ${pkgs.iproute2}/bin/tc qdisc del dev ${iface} root 2>/dev/null || true
      ${pkgs.iproute2}/bin/tc qdisc del dev ${iface} ingress 2>/dev/null || true
      ${pkgs.iproute2}/bin/ip link del ifb-${iface} 2>/dev/null || true

      # --- Egress (Upload) Setup ---
      # Root HTB qdisc
      ${pkgs.iproute2}/bin/tc qdisc replace dev ${iface} root handle 1: htb default 30

      # Root class (Total Bandwidth)
      ${pkgs.iproute2}/bin/tc class replace dev ${iface} parent 1: classid 1:1 htb rate ${speeds.upload} ceil ${speeds.upload}

      # Child Classes (defined from config)
      ${lib.concatMapStrings (
        classInfo:
        trafficClassifier.generateHtbClass "${pkgs.iproute2}/bin/tc" iface "1:1"
          "1:${toString classInfo.id}"
          classInfo.id
          classInfo.guaranteed
          classInfo.max
          classInfo.prio
      ) (lib.attrValues cfg.trafficClasses)}

      # --- Ingress (Download) Setup using IFB ---
      ${pkgs.iproute2}/bin/ip link add ifb-${iface} type ifb 2>/dev/null || true
      ${pkgs.iproute2}/bin/ip link set ifb-${iface} up

      # Redirect ingress to IFB
      ${pkgs.iproute2}/bin/tc qdisc replace dev ${iface} handle ffff: ingress
      ${pkgs.iproute2}/bin/tc filter replace dev ${iface} parent ffff: matchall action mirred egress redirect dev ifb-${iface}

      # Root HTB on IFB
      ${pkgs.iproute2}/bin/tc qdisc replace dev ifb-${iface} root handle 1: htb default 30

      # Root class (Total Bandwidth)
      ${pkgs.iproute2}/bin/tc class replace dev ifb-${iface} parent 1: classid 1:1 htb rate ${speeds.download} ceil ${speeds.download}

      # Child Classes on IFB (mirroring egress structure for simplicity, but could be distinct)
      ${lib.concatMapStrings (
        classInfo:
        trafficClassifier.generateHtbClass "${pkgs.iproute2}/bin/tc" "ifb-${iface}" "1:1"
          "1:${toString classInfo.id}"
          classInfo.id
          classInfo.guaranteed
          classInfo.max
          classInfo.prio
      ) (lib.attrValues cfg.trafficClasses)}

      # --- Filters (Using fwmark) ---
      # TC filters to map fwmarks to classes
      # We iterate through classes and add a filter for each
      ${lib.concatMapStrings (classInfo: ''
        ${pkgs.iproute2}/bin/tc filter replace dev ${iface} parent 1: protocol ip prio 1 handle ${toString classInfo.id} fw flowid 1:${toString classInfo.id}
        ${pkgs.iproute2}/bin/tc filter replace dev ifb-${iface} parent 1: protocol ip prio 1 handle ${toString classInfo.id} fw flowid 1:${toString classInfo.id}
      '') (lib.attrValues cfg.trafficClasses)}

      echo "QoS setup complete for ${iface}"
    else
      echo "Interface ${iface} not found, skipping QoS setup"
    fi
  '';

  cleanupWanQoS = iface: ''
    ${pkgs.iproute2}/bin/tc qdisc del dev ${iface} root 2>/dev/null || true
    ${pkgs.iproute2}/bin/tc qdisc del dev ${iface} ingress 2>/dev/null || true
    ${pkgs.iproute2}/bin/tc qdisc del dev ifb-${iface} root 2>/dev/null || true
    ${pkgs.iproute2}/bin/ip link del ifb-${iface} 2>/dev/null || true
  '';

in
{
  options.services.gateway.qos = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Advanced QoS";
    };

    interfaceSpeeds = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            download = lib.mkOption { type = lib.types.str; };
            upload = lib.mkOption { type = lib.types.str; };
          };
        }
      );
      default = { };
      description = "Per-interface bandwidth limits";
    };

    trafficClasses = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, config, ... }:
          {
            options = {
              id = lib.mkOption { type = lib.types.int; }; # Unique ID for fwmark (10, 20, 30...)
              priority = lib.mkOption {
                type = lib.types.int;
                default = 5;
              }; # HTB prio (lower is better)
              maxBandwidth = lib.mkOption { type = lib.types.str; };
              guaranteedBandwidth = lib.mkOption { type = lib.types.str; };
              protocols = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
              };
              applications = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "Applications to match using deep packet inspection";
              };
              dscp = lib.mkOption {
                type = lib.types.nullOr (lib.types.either lib.types.int lib.types.str);
                default = null;
              };
              dpi = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Enable deep packet inspection for this class";
              };

              # Internal fields for easy access
              prio = lib.mkOption {
                type = lib.types.int;
                internal = true;
                default = 5;
              };
              max = lib.mkOption {
                type = lib.types.str;
                internal = true;
              };
              guaranteed = lib.mkOption {
                type = lib.types.str;
                internal = true;
              };
            };
            config = {
              prio = config.priority;
              max = config.maxBandwidth;
              guaranteed = config.guaranteedBandwidth;
            };
          }
        )
      );
      default = { };
      description = "Traffic class definitions with application-aware classification";
    };

    policies = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            schedule = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Time schedule (e.g. 'Mon-Fri 09:00-17:00')";
            };
            rules = lib.mkOption {
              type = lib.types.listOf (
                lib.types.submodule {
                  options = {
                    match = lib.mkOption {
                      type = lib.types.submodule {
                        options = {
                          user = lib.mkOption {
                            type = lib.types.nullOr lib.types.str;
                            default = null;
                          };
                          application = lib.mkOption {
                            type = lib.types.nullOr lib.types.str;
                            default = null;
                          };
                        };
                      };
                      default = { };
                    };
                    action = lib.mkOption {
                      type = lib.types.submodule {
                        options = {
                          class = lib.mkOption {
                            type = lib.types.str;
                            description = "Target traffic class name";
                          };
                        };
                      };
                    };
                  };
                }
              );
              default = [ ];
            };
          };
        }
      );
      default = { };
      description = "Traffic policies based on time, user, or application";
    };

    extraForwardRules = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Extra rules to inject into the QoS forward chain";
    };
  };

  config = lib.mkIf cfg.enable {
    # Default Traffic Classes with application-aware classification
    services.gateway.qos.trafficClasses = {
      "voip" = {
        id = lib.mkDefault 10;
        priority = lib.mkDefault 1;
        maxBandwidth = lib.mkDefault "2Mbit";
        guaranteedBandwidth = lib.mkDefault "1Mbit";
        protocols = lib.mkDefault [
          "sip"
          "rtp"
        ];
        applications = lib.mkDefault [];
        dscp = lib.mkDefault 46;
        dpi = lib.mkDefault true;
      };
      "video" = {
        id = lib.mkDefault 20;
        priority = lib.mkDefault 2;
        maxBandwidth = lib.mkDefault "10Mbit";
        guaranteedBandwidth = lib.mkDefault "5Mbit";
        protocols = lib.mkDefault [ "https" ];
        applications = lib.mkDefault [ "zoom" "teams" "webex" ];
        dscp = lib.mkDefault 34;
        dpi = lib.mkDefault true;
      };
      "gaming" = {
        id = lib.mkDefault 25;
        priority = lib.mkDefault 3;
        maxBandwidth = lib.mkDefault "5Mbit";
        guaranteedBandwidth = lib.mkDefault "2Mbit";
        applications = lib.mkDefault [ "steam" "epic-games" "xbox-live" ];
        dscp = lib.mkDefault 26;
        dpi = lib.mkDefault true;
      };
      "bulk" = {
        id = lib.mkDefault 40;
        priority = lib.mkDefault 7;
        maxBandwidth = lib.mkDefault "50Mbit";
        guaranteedBandwidth = lib.mkDefault "1Mbit";
        applications = lib.mkDefault [ "torrents" "backups" ];
        dscp = lib.mkDefault 8;
        dpi = lib.mkDefault true;
      };
      "default" = {
        id = lib.mkDefault 30;
        priority = lib.mkDefault 5;
        maxBandwidth = lib.mkDefault "900Mbit";
        guaranteedBandwidth = lib.mkDefault "10Mbit";
        protocols = lib.mkDefault [];
        applications = lib.mkDefault [];
        dpi = lib.mkDefault false;
      };
    };

    boot.kernelModules = [
      "sch_htb"
      "sch_cake"
      "ifb"
      "act_mirred"
    ];

    # Firewall rules to mark packets based on traffic classes
    networking.nftables.enable = true;
    networking.nftables.tables."qos-mangle" = {
      family = "inet";
      content = ''
        chain forward {
          type filter hook forward priority mangle; policy accept;

          # Deep packet inspection rules (highest priority)
          ${lib.concatStringsSep "\n          " (
            lib.flatten (
              lib.mapAttrsToList (
                name: classConf:
                if classConf.dpi then
                  trafficClassifier.generateDpiRules name classConf classConf.id
                else
                  []
              ) cfg.trafficClasses
            )
          )}

          # Application-aware rules
          ${lib.concatStringsSep "\n          " (
            lib.flatten (
              lib.mapAttrsToList (
                name: classConf: trafficClassifier.generateApplicationRules name classConf classConf.id
              ) cfg.trafficClasses
            )
          )}

          # Protocol-based rules
          ${lib.concatStringsSep "\n          " (
            lib.flatten (
              lib.mapAttrsToList (
                name: classConf: trafficClassifier.generateProtocolRules name classConf classConf.id
              ) cfg.trafficClasses
            )
          )}

          # Extra Forward Rules (injected by other modules)
          ${cfg.extraForwardRules}

          # Policy-based rules
          ${lib.concatStringsSep "\n          " (
            lib.flatten (
              lib.mapAttrsToList (
                name: policy: trafficClassifier.generatePolicyRules name policy cfg.trafficClasses
              ) cfg.policies
            )
          )}
        }

        chain output {
           type route hook output priority mangle; policy accept;
           # Local traffic marking if needed
        }
      '';
    };

    systemd.services.qos-setup = {
      description = "Configure Advanced QoS (HTB + CAKE)";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -x
        ${lib.concatMapStringsSep "\n" (
          iface:
          let
            speeds = getInterfaceSpeed iface;
          in
          setupWanQoS iface speeds
        ) redIfaces}
      '';
      preStop = ''
        ${lib.concatMapStringsSep "\n" cleanupWanQoS redIfaces}
      '';
    };
  };
}

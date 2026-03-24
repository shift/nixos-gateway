{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.gateway;
  qosMangle = cfg.qosMangle;

  filterByType =
    type:
    builtins.map (h: h.ipAddress) (
      builtins.filter (h: h.type or null == type) (cfg.data.hosts.staticDHCPv4Assignments or [ ])
    );

  iotIPs = filterByType "iot";
  mediaIPs = filterByType "media";
  serverIPs = filterByType "server";

  wgPort = if cfg.wireguard.enable then cfg.wireguard.port else 51820;

  mkSet =
    name: ips:
    lib.optionalString (ips != [ ]) ''
      set ${name}_devices {
        type ipv4_addr
        elements = { ${lib.concatStringsSep ", " ips} }
      }
    '';

  mkSaddrRule =
    name: ips: dscp:
    lib.optionalString (ips != [ ]) ''
      ip saddr @${name}_devices ip dscp set ${dscp}
    '';

in
{
  options.services.gateway.qosMangle = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable QoS DSCP marking based on device types and services";
    };
  };

  config = lib.mkIf (cfg.enable && qosMangle.enable) {
    networking.nftables.ruleset = lib.mkAfter ''
      table inet mangle {
        ${mkSet "iot" iotIPs}
        ${mkSet "media" mediaIPs}
        ${mkSet "server" serverIPs}

        chain postrouting {
          type route hook output priority mangle; policy accept;

          meta l4proto 89 ip dscp set cs7
          tcp dport 179 ip dscp set cs7
          
          udp dport ${toString wgPort} meta length < 200 ip dscp set cs7

          udp dport { 53, 67, 68, 123, 546, 547 } ip dscp set cs6
          tcp dport { 53, 853 } ip dscp set cs6
          
          meta l4proto icmp ip dscp set cs6
          meta l4proto ipv6-icmp ip6 dscp set cs6

          tcp dport 22 meta length < 500 ip dscp set ef
          
          udp dport { 3074, 27015-27050 } ip dscp set cs4

          ${mkSaddrRule "iot" iotIPs "cs1"}
          
          ${lib.optionalString (serverIPs != [ ]) ''
            ip saddr @server_devices tcp dport { 443, 80 } meta length > 1000 ip dscp set cs1
          ''}

          udp dport 41641 meta length < 200 ip dscp set cs6
        }
      }
    '';
  };
}

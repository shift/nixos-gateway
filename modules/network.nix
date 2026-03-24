{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.gateway;
  enabled = cfg.enable or true;
  firewallData = cfg.data.firewall or { };

  # Import schema normalization
  schemaNormalization = import ../lib/schema-normalization.nix { inherit lib; };

  networkData = schemaNormalization.normalizeNetworkData (cfg.data.network or { });

  # Use normalized schema functions
  gatewayIpv4 = schemaNormalization.getSubnetGateway networkData "lan";
  subnet = schemaNormalization.getSubnetNetwork networkData "lan";
  mgmtAddr = networkData.mgmtAddress or gatewayIpv4;
  domain = cfg.domain or "lan.local";
in
{
  options.services.gateway = {
    # options moved to default.nix
    # redInterfaces = lib.mkOption { ... };
    # greenInterfaces = lib.mkOption { ... };
    # mgmtInterfaces = lib.mkOption { ... };

    network = {
      enable = lib.mkEnableOption "Core Networking";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (enabled && cfg.network.enable) {
      boot.kernelModules = [
        "iTCO_wdt"
      ];

      boot.kernel.sysctl."net.ipv4.conf.all.forwarding" = true;
      boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = true;

      boot.kernel.sysctl."net.ipv6.conf.all.accept_ra" = 0;
      boot.kernel.sysctl."net.ipv6.conf.all.autoconf" = 0;
      boot.kernel.sysctl."net.ipv6.conf.all.use_tempaddr" = 0;

      boot.kernel.sysctl."net.ipv6.conf.${cfg.interfaces.wan}.accept_ra" = 2;
      boot.kernel.sysctl."net.ipv6.conf.${cfg.interfaces.wan}.autoconf" = 1;
      # systemd.watchdog.runtimeTime = "30s";
      # systemd.watchdog.rebootTime = "30s";
      # systemd.watchdog.kexecTime = "30s";
      # boot.kernelParams = [ "panic=10" ];

      networking.hostName = "gw";
      networking.enableIPv6 = true;
      networking.useDHCP = false;
      networking.useNetworkd = true;
      networking.networkmanager.enable = false;
      systemd.network.enable = true;

      # Use systemd-resolved for local DNS resolution
      services.resolved = {
        enable = true;
        dnssec = "false";
        fallbackDns = [
          "1.1.1.1"
          "8.8.8.8"
          "2606:4700:4700::1111"
        ];
        domains = [ "~." ];
        extraConfig = ''
          DNS=127.0.0.1 ::1
          Domains=~${domain}
        '';
      };

      # WAN Interface (Primary - 10Gb)
      systemd.network.networks."10-wan" = {
        matchConfig.Name = cfg.interfaces.wan;
        networkConfig = {
          DHCP = "yes";
          IPv6AcceptRA = true;
        };
        dhcpV4Config.RouteMetric = 10;
        dhcpV6Config.RouteMetric = 10;
      };

      # WiFi Interface (Secondary uplink)
      systemd.network.networks."20-wifi" = lib.mkIf (cfg.interfaces ? "wifi") {
        matchConfig.Name = cfg.interfaces.wifi;
        networkConfig.DHCP = "yes";
        linkConfig.MACAddress = "1a:10:ff:fc:86:6f";
        dhcpV4Config.RouteMetric = 50;
        dhcpV6Config.RouteMetric = 50;
      };

      # WWAN Interface (Cellular fallback)
      systemd.network.networks."30-wwan" = lib.mkIf (cfg.interfaces ? "wwan") {
        matchConfig.Name = cfg.interfaces.wwan;
        networkConfig = {
          DHCP = "yes";
          IgnoreCarrierLoss = "3s";
        };
        dhcpV4Config.RouteMetric = 100;
        dhcpV6Config.RouteMetric = 100;
      };

      # LAN Interface
      systemd.network.networks."50-lan" = {
        matchConfig.Name = cfg.interfaces.lan;
        address = [ "${gatewayIpv4}/${lib.last (lib.splitString "/" subnet)}" ];
        networkConfig = {
          ConfigureWithoutCarrier = true;
          IPv6AcceptRA = false;
        };
      };

      # Zone-based firewall
      networking.firewall = {
        enable = true;
        rejectPackets = true;
        connectionTrackingModules = [
          "ftp"
          "irc"
          "sane"
          "sip"
          "tftp"
          "amanda"
          "h323"
          "netbios_sn"
          "pptp"
          "snmp"
        ];

        interfaces =
          let
            # Use safe access to lists as they are defined in default.nix
            green = cfg.greenInterfaces or [ ];
            mgmt = cfg.mgmtInterfaces or [ ];
            red = cfg.redInterfaces or [ ];

            uniqueInterfaces = lib.unique (green ++ mgmt ++ red);

            interfaceZones =
              iface:
              (lib.optional (lib.elem iface green) "green")
              ++ (lib.optional (lib.elem iface mgmt) "mgmt")
              ++ (lib.optional (lib.elem iface red) "red");

            interfaceConfig =
              iface:
              let
                zones = interfaceZones iface;
                tcpPorts = lib.unique (
                  lib.flatten (map (zone: firewallData.zones.${zone}.allowedTCPPorts or [ ]) zones)
                );
                udpPorts = lib.unique (
                  lib.flatten (map (zone: firewallData.zones.${zone}.allowedUDPPorts or [ ]) zones)
                );
              in
              {
                allowedTCPPorts = tcpPorts;
                allowedUDPPorts = udpPorts;
              };
          in
          lib.genAttrs uniqueInterfaces interfaceConfig;
      };

      networking.nftables = {
        enable = true;
        ruleset = ''
          table inet filter {
            chain forward {
              counter queue num 0
            }
          }

          table inet mangle {
            chain postrouting {
              type route hook output priority mangle; policy accept;

              udp dport { 53, 123, 546, 547 } ip dscp set cs6
              tcp dport { 53 } ip dscp set cs6

              tcp dport 22 meta length < 500 ip dscp set ef
              
              udp dport 27000-27100 ip dscp set cs4
              
              udp dport 3478 ip dscp set cs4
            }
          }

          table ip nat {
            chain postrouting {
              type nat hook postrouting priority srcnat; policy accept;
              oifname "${cfg.interfaces.wan}" masquerade
              ${lib.optionalString (cfg.interfaces ? "wifi") "oifname \"${cfg.interfaces.wifi}\" masquerade"}
              ${lib.optionalString (cfg.interfaces ? "wwan") "oifname \"${cfg.interfaces.wwan}\" masquerade"}
            }
          }
        '';
      };

      networking.nat = {
        enable = true;
        internalInterfaces = [ cfg.interfaces.lan ];
        internalIPs = [ subnet ];
        externalInterface = cfg.interfaces.wan;
      };

      services.irqbalance.enable = true;
    })

    # Management Interface (only configure if different from LAN)
    (lib.mkIf
      (
        enabled && cfg.network.enable && cfg.interfaces ? mgmt && cfg.interfaces.mgmt != cfg.interfaces.lan
      )
      {
        systemd.network.networks."99-mgmt" = {
          matchConfig.Name = cfg.interfaces.mgmt;
          address = [ "${mgmtAddr}/${lib.last (lib.splitString "/" subnet)}" ];
          networkConfig = {
            ConfigureWithoutCarrier = true;
            IPv6AcceptRA = false;
          };
        };
      }
    )
  ];
}

{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.gateway;

  schemaNormalization = import ../lib/schema-normalization.nix { inherit lib; };
  networkData = schemaNormalization.normalizeNetworkData (cfg.data.network or { });
  gatewayIpv4 = schemaNormalization.getSubnetGateway networkData "lan";
  subnet = schemaNormalization.getSubnetNetwork networkData "lan";
  subnetPrefixLen = lib.last (lib.splitString "/" subnet);
in
{
  options.services.gateway.wifi = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          band = lib.mkOption {
            type = lib.types.enum [ "2.4" "5" ];
            default = "2.4";
            description = "Radio band";
          };
          channel = lib.mkOption {
            type = lib.types.int;
            description = "WiFi channel number";
          };
          ssid = lib.mkOption {
            type = lib.types.str;
            description = "Network name (SSID)";
          };
          passphrase = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "WPA2 passphrase (null for open network)";
          };
          hidden = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Hide SSID from broadcast";
          };
          zone = lib.mkOption {
            type = lib.types.str;
            default = "green";
            description = "Firewall zone for this interface (green=LAN, red=WAN)";
          };
        };
      }
    );
    default = { };
    description = "WiFi radio configurations. Each attribute name is the interface (e.g. wlan0, wlan1).";
  };

  config = lib.mkIf (cfg.enable && cfg ? wifi && builtins.attrNames cfg.wifi != []) {

    # Create a hostapd service for each radio
    systemd.services = lib.mapAttrs' (
      iface: radioCfg:
      let
        configFile = pkgs.writeText "hostapd-${iface}.conf" ''
          interface=${iface}
          driver=nl80211
          ssid=${radioCfg.ssid}
          channel=${toString radioCfg.channel}
          hw_mode=${
            if radioCfg.band == "5" then "a"
            else "g"
          }
          ieee80211n=0
          ${lib.optionalString radioCfg.hidden "ignore_broadcast_ssid=1"}

          ${lib.optionalString (radioCfg.passphrase != null) ''
            wpa=2
            wpa_passphrase=${radioCfg.passphrase}
            wpa_key_mgmt=WPA-PSK
            rsn_pairwise=CCMP
          ''}
        '';
      in
      lib.nameValuePair "hostapd-${iface}" {
        description = "hostapd WiFi AP on ${iface}";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" "sys-subsystem-net-devices-${iface}.device" ];
        requires = [ "sys-subsystem-net-devices-${iface}.device" ];
        serviceConfig = {
          ExecStart = "${pkgs.hostapd}/bin/hostapd ${configFile}";
          Restart = "on-failure";
          RestartSec = "5s";

          # Hardening
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          AmbientCapabilities = [ "CAP_NET_ADMIN" "CAP_NET_RAW" ];
          CapabilityBoundingSet = [ "CAP_NET_ADMIN" "CAP_NET_RAW" ];
        };
      }
    ) cfg.wifi;

    # WiFi interfaces get a systemd-networkd config but no IP of their own
    # They should be bridged to LAN or act as AP-only interfaces
    # For ALIX: use a simple bridge or let hostapd manage the interface
    systemd.network.networks = lib.mapAttrs' (
      iface: radioCfg:
      lib.nameValuePair "60-wifi-${iface}" {
        matchConfig.Name = iface;
        # No address on WiFi interfaces - they act as AP only
        # Clients get IPs from the LAN DHCP server via the bridge
        networkConfig = {
          ConfigureWithoutCarrier = true;
          IPv6AcceptRA = false;
        };
        linkConfig = {
          RequiredForOnline = false;
        };
      }
    ) cfg.wifi;
  };
}

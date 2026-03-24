{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.gateway;
  wgManager = import ../lib/wireguard-manager.nix { inherit lib; };

  # Helper to create a reload script for dynamic peers
  reloadScript = pkgs.writeShellScriptBin "wg-dynamic-reload" ''
    INTERFACE="''${1:-wg0}"
    WATCH_DIR="''${2:-/etc/wireguard/peers.d}"

    echo "Scanning $WATCH_DIR for new peers..."

    if [ ! -d "$WATCH_DIR" ]; then
      echo "Directory $WATCH_DIR does not exist."
      exit 0
    fi

    # Iterate over peer files
    for peer_file in "$WATCH_DIR"/*.conf; do
        [ -e "$peer_file" ] || continue
        
        echo "Adding peer from $peer_file"
        # We use addconf to append without removing existing peers
        ${pkgs.wireguard-tools}/bin/wg addconf "$INTERFACE" "$peer_file" || echo "Failed to add $peer_file"
    done

    echo "Dynamic peer reload complete."
  '';

in
{
  options.services.gateway = {
    wireguard = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable WireGuard VPN server";
      };

      server = {
        interface = lib.mkOption {
          type = lib.types.str;
          default = "wg0";
          description = "WireGuard interface name";
        };
        listenPort = lib.mkOption {
          type = lib.types.port;
          default = 51820;
          description = "WireGuard listen port";
        };
        address = lib.mkOption {
          type = lib.types.str;
          default = "10.100.0.1/24";
          description = "WireGuard server IPv4 address with CIDR";
        };
        addressV6 = lib.mkOption {
          type = lib.types.str;
          default = "fd00:100::1/64";
          description = "WireGuard server IPv6 address with CIDR";
        };
        privateKeyFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Path to server private key file";
        };

        peers = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                publicKey = lib.mkOption {
                  type = lib.types.str;
                  description = "Peer public key";
                };
                allowedIPs = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                  description = "Allowed IPs for this peer";
                };
                endpoint = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  description = "Endpoint address:port";
                };
                persistentKeepalive = lib.mkOption {
                  type = lib.types.nullOr lib.types.int;
                  default = 25;
                  description = "Persistent keepalive interval";
                };
                routing = lib.mkOption {
                  default = { };
                  description = "Routing configuration for this peer";
                  type = lib.types.submodule {
                    options = {
                      advertiseRoutes = lib.mkOption {
                        type = lib.types.listOf lib.types.str;
                        default = [ ];
                        description = "Routes to advertise to this peer";
                      };
                      acceptRoutes = lib.mkOption {
                        type = lib.types.listOf lib.types.str;
                        default = [ ];
                        description = "Routes to accept from this peer";
                      };
                    };
                  };
                };
              };
            }
          );
          default = { };
          description = "Defined peers keyed by name";
        };
      };

      automation = {
        keyRotation = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable automatic key rotation";
          };
          interval = lib.mkOption {
            type = lib.types.str;
            default = "90";
            description = "Key rotation interval in days";
          };
          notifyBefore = lib.mkOption {
            type = lib.types.str;
            default = "7";
            description = "Notify days before rotation";
          };
        };
        peerManagement = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable automated peer management";
          };
          watchDirectory = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Directory to watch for dynamic peer configurations";
          };
        };
      };

      monitoring = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable WireGuard monitoring tools";
        };
      };
    };
  };

  config = lib.mkIf cfg.wireguard.enable {
    networking.firewall.allowedUDPPorts = [ cfg.wireguard.server.listenPort ];

    environment.systemPackages = [
      pkgs.wireguard-tools
      pkgs.iptables
    ]
    ++ (lib.optional cfg.wireguard.monitoring.enable (
      pkgs.writeScriptBin "wg-monitor-${cfg.wireguard.server.interface}" (
        wgManager.mkMonitoringScript {
          interface = cfg.wireguard.server.interface;
          peers = cfg.wireguard.server.peers;
        }
      )
    ));

    # Key Rotation Service
    systemd.services."wireguard-${cfg.wireguard.server.interface}-key-rotation" =
      lib.mkIf cfg.wireguard.automation.keyRotation.enable
        {
          description = "Rotate WireGuard keys for ${cfg.wireguard.server.interface}";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = pkgs.writeShellScript "wg-rotate-keys" (
              wgManager.mkKeyRotationScript {
                interface = cfg.wireguard.server.interface;
                interval = cfg.wireguard.automation.keyRotation.interval;
                notifyBefore = cfg.wireguard.automation.keyRotation.notifyBefore;
              }
            );
          };
        };

    systemd.timers."wireguard-${cfg.wireguard.server.interface}-key-rotation" =
      lib.mkIf cfg.wireguard.automation.keyRotation.enable
        {
          description = "Timer for WireGuard key rotation";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "daily";
            Persistent = true;
          };
        };

    # Dynamic Peer Watcher
    systemd.services."wireguard-${cfg.wireguard.server.interface}-watcher" =
      lib.mkIf
        (
          cfg.wireguard.automation.peerManagement.enable
          && cfg.wireguard.automation.peerManagement.watchDirectory != null
        )
        {
          description = "Watch for dynamic WireGuard peers";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${reloadScript}/bin/wg-dynamic-reload ${cfg.wireguard.server.interface} ${cfg.wireguard.automation.peerManagement.watchDirectory}";
          };
        };

    systemd.paths."wireguard-${cfg.wireguard.server.interface}-watcher" =
      lib.mkIf
        (
          cfg.wireguard.automation.peerManagement.enable
          && cfg.wireguard.automation.peerManagement.watchDirectory != null
        )
        {
          description = "Path watcher for WireGuard peers";
          wantedBy = [ "multi-user.target" ];
          pathConfig = {
            PathChanged = cfg.wireguard.automation.peerManagement.watchDirectory;
          };
        };

    networking.wireguard.interfaces.${cfg.wireguard.server.interface} =
      lib.mkIf (!config.networking.useNetworkd)
        {
          ips = [
            cfg.wireguard.server.address
            cfg.wireguard.server.addressV6
          ];

          listenPort = cfg.wireguard.server.listenPort;

          privateKeyFile =
            if cfg.wireguard.server.privateKeyFile != null then
              cfg.wireguard.server.privateKeyFile
            else
              "/var/lib/wireguard/${cfg.wireguard.server.interface}.key";

          peers = wgManager.peersToList cfg.wireguard.server.peers;
        };

    systemd.network.netdevs."90-${cfg.wireguard.server.interface}" =
      lib.mkIf (config.networking.useNetworkd)
        {
          netdevConfig = {
            Name = cfg.wireguard.server.interface;
            Kind = "wireguard";
          };
          wireguardConfig = {
            PrivateKeyFile =
              if cfg.wireguard.server.privateKeyFile != null then
                cfg.wireguard.server.privateKeyFile
              else
                "/var/lib/wireguard/${cfg.wireguard.server.interface}.key";
            ListenPort = cfg.wireguard.server.listenPort;
          };
          wireguardPeers = wgManager.peersToNetdev cfg.wireguard.server.peers;
        };

    # Explicitly configure systemd-networkd for the WireGuard interface
    systemd.network.networks."90-${cfg.wireguard.server.interface}" =
      lib.mkIf config.networking.useNetworkd
        {
          matchConfig.Name = cfg.wireguard.server.interface;
          address = [
            cfg.wireguard.server.address
            cfg.wireguard.server.addressV6
          ];
          networkConfig = {
            IPMasquerade = "ipv4";
          };
        };

    systemd.services."wireguard-${cfg.wireguard.server.interface}-nat" = {
      description = "NAT rules for WireGuard interface ${cfg.wireguard.server.interface}";
      wantedBy = [ "multi-user.target" ];
      wants = lib.mkIf config.networking.useNetworkd [ "network-online.target" ];
      after =
        if config.networking.useNetworkd then
          [ "network-online.target" ]
        else
          [ "wireguard-${cfg.wireguard.server.interface}.service" ];
      bindsTo =
        if config.networking.useNetworkd then
          [ ]
        else
          [ "wireguard-${cfg.wireguard.server.interface}.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "wg-nat-up" (
          wgManager.generatePostSetup {
            interface = cfg.wireguard.server.interface;
            wanInterface = cfg.interfaces.wan;
            peers = cfg.wireguard.server.peers;
            ipv4Cidr = "10.100.0.0/24";
            ipv6Cidr = "fd00:100::/64";
            iptablesBin = "${pkgs.iptables}/bin/iptables";
            ip6tablesBin = "${pkgs.iptables}/bin/ip6tables";
          }
        );
        ExecStop = pkgs.writeShellScript "wg-nat-down" (
          wgManager.generatePostShutdown {
            interface = cfg.wireguard.server.interface;
            wanInterface = cfg.interfaces.wan;
            ipv4Cidr = "10.100.0.0/24";
            ipv6Cidr = "fd00:100::/64";
            iptablesBin = "${pkgs.iptables}/bin/iptables";
            ip6tablesBin = "${pkgs.iptables}/bin/ip6tables";
          }
        );
      };
    };

    # DNS for VPN clients (assumes binding to VPN IP)
    services.kresd.listenPlain = lib.mkAfter [
      "${builtins.head (lib.splitString "/" cfg.wireguard.server.address)}:53"
    ];

    # Allow VPN traffic through firewall
    networking.firewall.trustedInterfaces = [ cfg.wireguard.server.interface ];

    # Generate server keys if they don't exist
    system.activationScripts."wireguard-${cfg.wireguard.server.interface}-keys" =
      lib.mkIf (cfg.wireguard.server.privateKeyFile == null)
        {
          text = ''
            mkdir -p /var/lib/wireguard
            KEY_FILE="/var/lib/wireguard/${cfg.wireguard.server.interface}.key"
            PUB_FILE="/var/lib/wireguard/${cfg.wireguard.server.interface}.pub"

            if [ ! -f "$KEY_FILE" ]; then
              ${pkgs.wireguard-tools}/bin/wg genkey > "$KEY_FILE"
              ${pkgs.wireguard-tools}/bin/wg pubkey < "$KEY_FILE" > "$PUB_FILE"
              echo "Generated new WireGuard keys for ${cfg.wireguard.server.interface}:"
              echo "Public key: $(cat "$PUB_FILE")"
            fi

            # Ensure permissions are correct
            if getent group systemd-network >/dev/null; then
              chown root:systemd-network "$KEY_FILE"
              chmod 640 "$KEY_FILE"
            else
              chmod 600 "$KEY_FILE"
            fi
          '';
          deps = [
            "users"
            "groups"
          ];
        };
  };
}

{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.gateway.topologyDiscovery;
  networkMapperLib = import ../lib/network-mapper.nix { inherit lib; };

  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    ;

in
{
  options.services.gateway.topologyDiscovery = {
    enable = mkEnableOption "Automatic network topology discovery";

    discovery = {
      methods = {
        arp = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Enable ARP table analysis";
          };
          interval = mkOption {
            type = types.str;
            default = "5m";
            description = "Interval for ARP scanning";
          };
        };

        lldp = {
          enable = mkOption {
            type = types.bool;
            default = false;
            description = "Enable LLDP neighbor discovery";
          };
          interval = mkOption {
            type = types.str;
            default = "2m";
            description = "Interval for LLDP scanning";
          };
        };

        # Extended methods (placeholders for full implementation)
        snmp = {
          enable = mkEnableOption "SNMP discovery";
        };
        dhcp = {
          enable = mkEnableOption "DHCP lease analysis";
        };
        dns = {
          enable = mkEnableOption "DNS record analysis";
        };
        passive = {
          enable = mkEnableOption "Passive packet capture analysis";
        };
      };
    };

    visualization = {
      enable = mkEnableOption "Topology visualization dashboard";
      port = mkOption {
        type = types.int;
        default = 8081;
        description = "Port for the topology visualization dashboard";
      };
    };

    # Internal option to pass pkgs to the library
    pkgs = mkOption {
      type = types.attrs;
      default = pkgs;
      internal = true;
      visible = false;
    };
  };

  config = mkIf cfg.enable {
    # Enable LLDP daemon if LLDP discovery is enabled
    services.lldpd.enable = cfg.discovery.methods.lldp.enable;

    # Ensure working directories exist
    systemd.tmpfiles.rules = [
      "d /run/gateway-topology 0755 root root - -"
      "d /var/lib/gateway-topology 0755 root root - -"
    ];

    # Topology Discovery Service
    systemd.services.gateway-topology-discovery = {
      description = "Network Topology Discovery Service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      path =
        with pkgs;
        [
          iproute2
          jq
          coreutils
          gnused
        ]
        ++ (if cfg.discovery.methods.lldp.enable then [ pkgs.lldpd ] else [ ]);

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeScript "topology-discovery.sh" ''
          #!/bin/sh
          set -e

          TOPOLOGY_DIR="/run/gateway-topology"
          PERSISTENT_DIR="/var/lib/gateway-topology"
          mkdir -p "$TOPOLOGY_DIR" "$PERSISTENT_DIR"

          # Run Discovery Methods
          ${networkMapperLib.generateArpDiscoveryScript { inherit (cfg) discovery pkgs; }}
          ${networkMapperLib.generateLldpDiscoveryScript { inherit (cfg) discovery pkgs; }}

          # Merge Data
          ${networkMapperLib.generateTopologyMergeScript}

          # Persist latest topology
          cp "$TOPOLOGY_DIR/topology.json" "$PERSISTENT_DIR/topology.json"

          echo "Topology discovery completed."
        '';
      };
    };

    # Timer for periodic discovery
    systemd.timers.gateway-topology-discovery = {
      description = "Periodic Network Topology Discovery";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "1m";
        OnUnitActiveSec = cfg.discovery.methods.arp.interval; # Use ARP interval as main driver for now
        Persistent = true;
      };
    };

    # Visualization Dashboard (Simple static server for now)
    systemd.services.gateway-topology-dashboard = mkIf cfg.visualization.enable {
      description = "Network Topology Visualization Dashboard";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = pkgs.writeScript "start-topology-dashboard.sh" ''
          #!/bin/sh
          TOPOLOGY_DIR="/run/gateway-topology"

          # Generate a simple index.html if not present
          if [ ! -f "$TOPOLOGY_DIR/index.html" ]; then
            cat << 'EOF' > "$TOPOLOGY_DIR/index.html"
            <!DOCTYPE html>
            <html>
            <head>
              <title>Network Topology</title>
              <style>
                body { font-family: sans-serif; padding: 20px; }
                pre { background: #f0f0f0; padding: 10px; border-radius: 5px; }
              </style>
            </head>
            <body>
              <h1>Network Topology</h1>
              <div id="status">Loading...</div>
              <pre id="json-display"></pre>
              <script>
                fetch('/topology.json')
                  .then(response => response.json())
                  .then(data => {
                    document.getElementById('status').innerText = 'Last updated: ' + new Date().toLocaleString();
                    document.getElementById('json-display').innerText = JSON.stringify(data, null, 2);
                  })
                  .catch(err => {
                    document.getElementById('status').innerText = 'Error loading topology data';
                    console.error(err);
                  });
              </script>
            </body>
            </html>
          EOF
          fi

          ${pkgs.python3}/bin/python3 -m http.server ${toString cfg.visualization.port} \
            --bind 0.0.0.0 \
            --directory "$TOPOLOGY_DIR"
        '';
      };
    };
  };
}

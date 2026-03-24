{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.gateway.frr;
  gatewayCfg = config.services.gateway;
  bgpLib = import ../lib/bgp-config.nix { inherit lib; };

  # BGP neighbor type
  bgpNeighborType = lib.types.submodule {
    options = {
      asn = lib.mkOption {
        type = lib.types.int;
        description = "Neighbor AS number";
      };

      address = lib.mkOption {
        type = lib.types.str;
        description = "Neighbor IP address";
      };

      description = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Neighbor description";
      };

      password = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "BGP MD5 password";
      };

      capabilities = lib.mkOption {
        type = lib.types.submodule {
          options = {
            multipath = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Enable multipath capability";
            };

            refresh = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Enable route refresh capability";
            };

            gracefulRestart = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Enable graceful restart";
            };

            routeRefresh = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Enable route refresh";
            };
          };
        };
        default = { };
        description = "BGP capabilities";
      };

      policies = lib.mkOption {
        type = lib.types.submodule {
          options = {
            import = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Import route maps";
            };

            export = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Export route maps";
            };
          };
        };
        default = { };
        description = "BGP policies";
      };

      timers = lib.mkOption {
        type = lib.types.submodule {
          options = {
            keepalive = lib.mkOption {
              type = lib.types.int;
              default = 60;
              description = "Keepalive timer in seconds";
            };

            hold = lib.mkOption {
              type = lib.types.int;
              default = 180;
              description = "Hold timer in seconds";
            };

            connect = lib.mkOption {
              type = lib.types.int;
              default = 60;
              description = "Connect timer in seconds";
            };
          };
        };
        default = { };
        description = "BGP timers";
      };
    };
  };

  # Prefix list entry type
  prefixListEntryType = lib.types.submodule {
    options = {
      seq = lib.mkOption {
        type = lib.types.int;
        description = "Sequence number";
      };

      action = lib.mkOption {
        type = lib.types.enum [
          "permit"
          "deny"
        ];
        description = "Action (permit or deny)";
      };

      prefix = lib.mkOption {
        type = lib.types.str;
        description = "IP prefix (e.g., 192.168.1.0/24)";
      };

      le = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "Less than or equal to prefix length";
      };

      ge = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "Greater than or equal to prefix length";
      };
    };
  };

  # Route map entry type
  routeMapEntryType = lib.types.submodule {
    options = {
      seq = lib.mkOption {
        type = lib.types.int;
        description = "Sequence number";
      };

      action = lib.mkOption {
        type = lib.types.enum [
          "permit"
          "deny"
        ];
        description = "Action (permit or deny)";
      };

      match = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Match conditions";
      };

      set = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Set actions";
      };
    };
  };
in
{
  options.services.gateway.frr = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable FRRouting daemon";
    };

    bgp = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable BGP routing";
      };

      asn = lib.mkOption {
        type = lib.types.int;
        description = "Local AS number";
      };

      routerId = lib.mkOption {
        type = lib.types.str;
        description = "BGP router ID";
      };

      neighbors = lib.mkOption {
        type = lib.types.attrsOf bgpNeighborType;
        default = { };
        description = "BGP neighbors";
      };

      policies = lib.mkOption {
        type = lib.types.submodule {
          options = {
            prefixLists = lib.mkOption {
              type = lib.types.attrsOf (lib.types.listOf prefixListEntryType);
              default = { };
              description = "Prefix lists";
            };

            routeMaps = lib.mkOption {
              type = lib.types.attrsOf (lib.types.listOf routeMapEntryType);
              default = { };
              description = "Route maps";
            };

            communities = lib.mkOption {
              type = lib.types.submodule {
                options = {
                  standard = lib.mkOption {
                    type = lib.types.attrsOf lib.types.str;
                    default = { };
                    description = "Standard BGP communities";
                  };

                  expanded = lib.mkOption {
                    type = lib.types.attrsOf lib.types.str;
                    default = { };
                    description = "Expanded BGP communities";
                  };

                  large = lib.mkOption {
                    type = lib.types.attrsOf lib.types.str;
                    default = { };
                    description = "Large BGP communities";
                  };
                };
              };
              default = { };
              description = "BGP communities";
            };

            aspaths = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = { };
              description = "AS path access lists";
            };
          };
        };
        default = { };
        description = "BGP policies";
      };

      multipath = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable BGP multipath";
      };

      flowspec = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable BGP flow specification";
      };

      largeCommunities = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable BGP large communities";
      };

      routeServer = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable BGP route server mode";
      };

      routeClient = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable BGP route client mode";
      };

      monitoring = lib.mkOption {
        type = lib.types.submodule {
          options = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Enable BGP monitoring";
            };

            prometheus = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Export BGP metrics to Prometheus";
            };

            healthChecks = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Enable BGP health checks";
            };

            logLevel = lib.mkOption {
              type = lib.types.enum [
                "debugging"
                "informational"
                "notifications"
                "warnings"
                "errors"
              ];
              default = "informational";
              description = "BGP log level";
            };
          };
        };
        default = { };
        description = "BGP monitoring configuration";
      };
    };

    ospf = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable OSPF routing";
      };
    };

    ospf6 = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable OSPFv3 (IPv6) routing";
      };
    };

    bfd = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable Bidirectional Forwarding Detection for fast failover";
      };
    };

    config = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Raw FRR configuration";
    };
  };

  config = lib.mkIf cfg.enable {
    # Generate FRR configuration
    environment.etc."frr/frr.conf".text = lib.mkIf (cfg.bgp.enable && cfg.bgp.asn != null) (
      bgpLib.generateBGPConfig {
        asn = cfg.bgp.asn;
        routerId = cfg.bgp.routerId;
        neighbors = cfg.bgp.neighbors;
        policies = cfg.bgp.policies;
        multipath = cfg.bgp.multipath;
        flowspec = cfg.bgp.flowspec;
        largeCommunities = cfg.bgp.largeCommunities;
        routeServer = cfg.bgp.routeServer;
        routeClient = cfg.bgp.routeClient;
      }
    );

    # FRR daemons configuration is handled below with BGP-specific options

    # Validate BGP configuration
    assertions =
      lib.optionals (cfg.bgp.enable && cfg.bgp.asn != null) [
        {
          assertion = cfg.bgp.asn != null;
          message = "BGP ASN must be specified when BGP is enabled";
        }
        {
          assertion = cfg.bgp.routerId != null;
          message = "BGP router ID must be specified when BGP is enabled";
        }
        {
          assertion =
            builtins.match "^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}$" cfg.bgp.routerId != null;
          message = "BGP router ID must be a valid IPv4 address";
        }
      ]
      ++ lib.mapAttrsToList (name: neighbor: {
        assertion = neighbor.asn != null && neighbor.address != null;
        message = "BGP neighbor ${name} must have ASN and address";
      }) cfg.bgp.neighbors;

    # Define systemd services
    systemd.services = lib.mkMerge [
      {
        frr = {
          description = "FRRouting Daemon";
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ];
          serviceConfig = {
            Type = "forking";
            ExecStart = "${pkgs.frr}/libexec/frr/frrinit.sh start";
            ExecStop = "${pkgs.frr}/libexec/frr/frrinit.sh stop";
            ExecReload = "${pkgs.frr}/libexec/frr/frrinit.sh reload";
            PIDFile = "/run/frr/frr.pid";
            Restart = "on-failure";
            RestartSec = "5s";
          };
          path = [ pkgs.frr ];
        };
      }
      (lib.mkIf (cfg.bgp.enable && cfg.bgp.monitoring.enable) {
        # BGP health check service
        gateway-bgp-health-check = {
          description = "BGP Health Check Service";
          wantedBy = [ "multi-user.target" ];
          after = [ "frr.service" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = pkgs.writeShellScript "bgp-health-check" ''
              #!/bin/sh
              set -euo pipefail

              HEALTH_DIR="/run/gateway-health-state"
              mkdir -p "$HEALTH_DIR"

              # Check BGP process
              if ! pgrep -f "bgpd" > /dev/null; then
                echo "unhealthy" > "$HEALTH_DIR/bgp.status"
                echo "$(date): BGP daemon not running" >> /var/log/gateway/bgp-health.log
                exit 1
              fi

              # Check BGP neighbors
              ${lib.concatStringsSep "\n" (
                lib.mapAttrsToList (name: neighbor: ''
                  # Check neighbor ${name} (${neighbor.address})
                  if ${pkgs.frr}/bin/vtysh -c "show bgp summary json" | jq -r ".ipv4Unicast.peers.\"${neighbor.address}\".state" | grep -q "Established"; then
                    echo "$(date): BGP neighbor ${name} (${neighbor.address}) is Established" >> /var/log/gateway/bgp-health.log
                  else
                    echo "unhealthy" > "$HEALTH_DIR/bgp.status"
                    echo "$(date): BGP neighbor ${name} (${neighbor.address}) is not Established" >> /var/log/gateway/bgp-health.log
                    exit 1
                  fi
                '') cfg.bgp.neighbors
              )}

              # Check route table
              if ${pkgs.frr}/bin/vtysh -c "show ip route bgp" | grep -q "BGP"; then
                echo "$(date): BGP routes present in routing table" >> /var/log/gateway/bgp-health.log
              else
                echo "$(date): Warning: No BGP routes in routing table" >> /var/log/gateway/bgp-health.log
              fi

              echo "healthy" > "$HEALTH_DIR/bgp.status"
              echo "$(date): BGP health check passed" >> /var/log/gateway/bgp-health.log
            '';
            TimeoutSec = "30s";
          };
        };

        # BGP Prometheus metrics exporter
        gateway-bgp-metrics = lib.mkIf cfg.bgp.monitoring.prometheus {
          description = "BGP Metrics Exporter";
          wantedBy = [ "multi-user.target" ];
          after = [ "frr.service" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = pkgs.writeShellScript "bgp-metrics" ''
              #!/bin/sh
              set -euo pipefail

              METRICS_DIR="/run/prometheus"
              mkdir -p "$METRICS_DIR"
              METRICS_FILE="$METRICS_DIR/gateway-bgp.prom"

              # Clear previous metrics
              > "$METRICS_FILE"

              # BGP neighbor metrics
              ${lib.concatStringsSep "\n" (
                lib.mapAttrsToList (name: neighbor: ''
                  # Get neighbor state
                  STATE=$(${pkgs.frr}/bin/vtysh -c "show bgp summary json" | jq -r ".ipv4Unicast.peers.\"${neighbor.address}\".state // \"unknown\"")
                  UPTIME=$(${pkgs.frr}/bin/vtysh -c "show bgp summary json" | jq -r ".ipv4Unicast.peers.\"${neighbor.address}\".uptime // 0")
                  RECEIVED=$(${pkgs.frr}/bin/vtysh -c "show bgp summary json" | jq -r ".ipv4Unicast.peers.\"${neighbor.address}\".received // 0")
                  ADVERTISED=$(${pkgs.frr}/bin/vtysh -c "show bgp summary json" | jq -r ".ipv4Unicast.peers.\"${neighbor.address}\".advertised // 0")

                  STATE_CODE=0
                  if [ "$STATE" = "Established" ]; then
                    STATE_CODE=1
                  fi

                  echo "gateway_bgp_neighbor_state{neighbor=\"${name}\",address=\"${neighbor.address}\"} $STATE_CODE" >> "$METRICS_FILE"
                  echo "gateway_bgp_neighbor_uptime{neighbor=\"${name}\",address=\"${neighbor.address}\"} $UPTIME" >> "$METRICS_FILE"
                  echo "gateway_bgp_neighbor_routes_received{neighbor=\"${name}\",address=\"${neighbor.address}\"} $RECEIVED" >> "$METRICS_FILE"
                  echo "gateway_bgp_neighbor_routes_advertised{neighbor=\"${name}\",address=\"${neighbor.address}\"} $ADVERTISED" >> "$METRICS_FILE"
                '') cfg.bgp.neighbors
              )}

              # BGP route count metrics
              TOTAL_ROUTES=$(${pkgs.frr}/bin/vtysh -c "show ip route bgp count" | grep "Total" | awk '{print $2}' || echo "0")
              echo "gateway_bgp_total_routes $TOTAL_ROUTES" >> "$METRICS_FILE"

              # BGP process metrics
              if pgrep -f "bgpd" > /dev/null; then
                echo "gateway_bgp_process_running 1" >> "$METRICS_FILE"
              else
                echo "gateway_bgp_process_running 0" >> "$METRICS_FILE"
              fi
            '';
            TimeoutSec = "30s";
          };
        };
      })
    ];

    # Timers for BGP monitoring
    systemd.timers = lib.mkIf cfg.bgp.monitoring.enable {
      # BGP health check timer
      gateway-bgp-health-check = lib.mkIf cfg.bgp.monitoring.healthChecks {
        description = "BGP Health Check Timer";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*:*:0/30"; # Every 30 seconds
          Unit = "gateway-bgp-health-check.service";
        };
      };

      # BGP metrics timer
      gateway-bgp-metrics = lib.mkIf cfg.bgp.monitoring.prometheus {
        description = "BGP Metrics Timer";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*:*:0/60"; # Every minute
          Unit = "gateway-bgp-metrics.service";
        };
      };
    };

    # Create log directory
    systemd.tmpfiles.rules = lib.mkIf (cfg.bgp.enable && cfg.bgp.monitoring.enable) [
      "d /var/log/gateway 0755 root root -"
    ];

    # FRR logging configuration
    environment.etc."frr/daemons".text = lib.mkIf cfg.bgp.enable ''
      bgpd=yes
      ${lib.optionalString cfg.ospf.enable "ospfd=yes"}
      ${lib.optionalString cfg.ospf6.enable "ospf6d=yes"}
      ${lib.optionalString cfg.bfd.enable "bfdd=yes"}
      zebra=yes
      vtysh_enable=yes
      bgpd_options="-A 127.0.0.1 -M ${cfg.bgp.monitoring.logLevel}"
      ${lib.optionalString cfg.ospf.enable "ospfd_options=\"-A 127.0.0.1\""}
      ${lib.optionalString cfg.ospf6.enable "ospf6d_options=\"-A 127.0.0.1\""}
      ${lib.optionalString cfg.bfd.enable "bfdd_options=\"-A 127.0.0.1\""}
      zebra_options="-A 127.0.0.1"
    '';

    environment.systemPackages = with pkgs; [
      frr
      jq # For JSON parsing in health checks
    ];
  };
}

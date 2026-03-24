{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.gateway.byoip;
  gatewayCfg = config.services.gateway;
  frrCfg = config.services.gateway.frr;

  # Import BYOIP libraries
  byoipLib = import ../lib/byoip-config.nix { inherit lib; };
  providerLib = import ../lib/provider-peering.nix { inherit lib; };

  # BYOIP prefix type
  byoipPrefixType = lib.types.submodule {
    options = {
      prefix = lib.mkOption {
        type = lib.types.str;
        description = "BYOIP prefix in CIDR notation";
      };

      communities = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "BGP communities to attach to this prefix";
      };

      asPath = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "AS path to prepend for traffic engineering";
      };

      localPref = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "Local preference for this prefix";
      };

      description = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Description of this prefix";
      };
    };
  };

  # Provider peering type
  providerPeeringType = lib.types.submodule {
    options = {
      asn = lib.mkOption {
        type = lib.types.int;
        description = "Provider ASN";
      };

      neighborIP = lib.mkOption {
        type = lib.types.str;
        description = "Provider neighbor IP address";
      };

      localASN = lib.mkOption {
        type = lib.types.int;
        description = "Local ASN for this peering";
      };

      prefixes = lib.mkOption {
        type = lib.types.listOf byoipPrefixType;
        default = [ ];
        description = "BYOIP prefixes to advertise to this provider";
      };

      filters = lib.mkOption {
        type = lib.types.submodule {
          options = {
            inbound = lib.mkOption {
              type = lib.types.submodule {
                options = {
                  allowCommunities = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [ ];
                    description = "Allowed communities for inbound routes";
                  };

                  maxPrefixLength = lib.mkOption {
                    type = lib.types.int;
                    default = 24;
                    description = "Maximum prefix length to accept";
                  };

                  rejectLongerPrefixes = lib.mkOption {
                    type = lib.types.bool;
                    default = true;
                    description = "Reject prefixes longer than maxPrefixLength";
                  };
                };
              };
              default = { };
              description = "Inbound route filtering";
            };

            outbound = lib.mkOption {
              type = lib.types.submodule {
                options = {
                  prependAS = lib.mkOption {
                    type = lib.types.int;
                    default = 1;
                    description = "Number of AS prepending for outbound routes";
                  };

                  noExport = lib.mkOption {
                    type = lib.types.bool;
                    default = false;
                    description = "Set no-export community on outbound routes";
                  };

                  aggregateOnly = lib.mkOption {
                    type = lib.types.bool;
                    default = false;
                    description = "Only advertise aggregate routes";
                  };
                };
              };
              default = { };
              description = "Outbound route filtering";
            };
          };
        };
        default = { };
        description = "Route filtering configuration";
      };

      monitoring = lib.mkOption {
        type = lib.types.submodule {
          options = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Enable monitoring for this peering";
            };

            checkInterval = lib.mkOption {
              type = lib.types.str;
              default = "30s";
              description = "Health check interval";
            };

            alertThreshold = lib.mkOption {
              type = lib.types.int;
              default = 300;
              description = "Alert threshold in seconds";
            };
          };
        };
        default = { };
        description = "Monitoring configuration";
      };

      capabilities = lib.mkOption {
        type = lib.types.submodule {
          options = {
            multipath = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Enable BGP multipath";
            };

            extendedNexthop = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Enable extended nexthop";
            };

            addPath = lib.mkOption {
              type = lib.types.enum [
                "receive"
                "send"
                "both"
                "disable"
              ];
              default = "receive";
              description = "BGP add-path capability";
            };
          };
        };
        default = { };
        description = "BGP capabilities";
      };

      timers = lib.mkOption {
        type = lib.types.submodule {
          options = {
            keepalive = lib.mkOption {
              type = lib.types.int;
              default = 30;
              description = "Keepalive timer in seconds";
            };

            hold = lib.mkOption {
              type = lib.types.int;
              default = 90;
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

  # Generate FRR configuration for BYOIP
  generateBYOIPFRRConfig =
    let
      # Generate provider configurations
      providerConfigs = lib.mapAttrsToList (name: providerCfg: ''
        # ${name} BYOIP Peering Configuration
        ${byoipLib.generateProviderBGPConfig name providerCfg}
      '') cfg.providers;

      # Generate ROV configuration if enabled
      rovConfig = lib.optionalString cfg.security.rov.enable ''
        # RPKI/ROV Configuration
        ${byoipLib.generateROVConfig cfg.security.rov}
      '';

      # Combine all configurations
      frrConfig = ''
        ! BYOIP BGP Configuration
        ! Generated by NixOS Gateway BYOIP module

        router bgp ${toString cfg.localASN}
          bgp router-id ${cfg.routerId}

          # Enable necessary BGP features
          bgp bestpath as-path multipath-relax
          bgp bestpath med missing-as-worst
          bgp large-community receive
          bgp large-community send
          bgp log-neighbor-changes

          ${lib.concatStringsSep "\n" providerConfigs}

          ${rovConfig}

        exit
      '';
    in
    frrConfig;

  # Generate monitoring configuration
  generateMonitoringConfig =
    let
      monitoringCfg = byoipLib.generateMonitoringConfig cfg.monitoring;
      providerChecks = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (name: providerCfg: ''
          # ${name} monitoring
          check_bgp_session_${name}() {
            ${monitoringCfg.monitoringScript}
          }
        '') cfg.providers
      );
    in
    monitoringCfg // { providerChecks = providerChecks; };

in
{
  options.services.gateway.byoip = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable BYOIP BGP peering functionality";
    };

    localASN = lib.mkOption {
      type = lib.types.int;
      description = "Local ASN for BYOIP peering";
    };

    routerId = lib.mkOption {
      type = lib.types.str;
      description = "BGP router ID for BYOIP";
    };

    providers = lib.mkOption {
      type = lib.types.attrsOf providerPeeringType;
      default = { };
      description = "Cloud provider peering configurations";
      example = {
        aws = {
          asn = 16509;
          neighborIP = "169.254.0.1";
          localASN = 65000;
          prefixes = [
            {
              prefix = "203.0.113.0/24";
              communities = [ "65000:100" ];
            }
          ];
        };
      };
    };

    monitoring = lib.mkOption {
      type = lib.types.submodule {
        options = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable BYOIP monitoring";
          };

          prometheusPort = lib.mkOption {
            type = lib.types.int;
            default = 9093;
            description = "Prometheus metrics port";
          };

          alertRules = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [
              "bgp_session_down"
              "prefix_hijacking_detected"
              "route_leak_detected"
            ];
            description = "Alert rules to enable";
          };
        };
      };
      default = { };
      description = "Global BYOIP monitoring configuration";
    };

    security = lib.mkOption {
      type = lib.types.submodule {
        options = {
          rov = lib.mkOption {
            type = lib.types.submodule {
              options = {
                enable = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                  description = "Enable Route Origin Validation (ROV)";
                };

                strict = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                  description = "Enable strict ROV (reject unknown origins)";
                };
              };
            };
            default = { };
            description = "Route Origin Validation configuration";
          };
        };
      };
      default = { };
      description = "BYOIP security configuration";
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure FRR is enabled
    services.gateway.frr.enable = true;
    services.gateway.frr.bgp.enable = true;

    # Validate BYOIP configuration
    assertions = [
      {
        assertion = cfg.localASN != null;
        message = "BYOIP local ASN must be specified";
      }
      {
        assertion = cfg.routerId != null;
        message = "BYOIP router ID must be specified";
      }
      {
        assertion = builtins.length (lib.attrNames cfg.providers) > 0;
        message = "At least one provider must be configured for BYOIP";
      }
    ]
    ++ lib.mapAttrsToList (name: providerCfg: {
      assertion =
        providerCfg.asn != null && providerCfg.neighborIP != null && providerCfg.localASN != null;
      message = "Provider ${name} must have ASN, neighborIP, and localASN configured";
    }) cfg.providers;

    # Extend FRR configuration with BYOIP
    services.gateway.frr.config = lib.mkAfter generateBYOIPFRRConfig;

    # BYOIP monitoring services
    systemd.services = lib.mkIf cfg.monitoring.enable (
      let
        monitoringCfg = generateMonitoringConfig;
      in
      {
        # BYOIP health check service
        gateway-byoip-health-check = {
          description = "BYOIP BGP Health Check Service";
          wantedBy = [ "multi-user.target" ];
          after = [ "frr.service" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = pkgs.writeShellScript "byoip-health-check" ''
              #!/bin/sh
              set -euo pipefail

              HEALTH_DIR="/run/gateway-health-state"
              mkdir -p "$HEALTH_DIR"

              ${lib.concatStringsSep "\n" (
                lib.mapAttrsToList (name: providerCfg: ''
                  # Check ${name} BGP session
                  SESSION_STATE=$(vtysh -c "show bgp summary json" | jq -r ".ipv4Unicast.peers.\"${providerCfg.neighborIP}\".state // \"unknown\"")

                  if [ "$SESSION_STATE" != "Established" ]; then
                    echo "unhealthy" > "$HEALTH_DIR/byoip-${name}.status"
                    echo "$(date): BYOIP BGP session with ${name} (${providerCfg.neighborIP}) is $SESSION_STATE" >> /var/log/gateway/byoip-health.log
                    exit 1
                  fi

                  echo "$(date): BYOIP BGP session with ${name} established" >> /var/log/gateway/byoip-health.log
                '') cfg.providers
              )}

              # Check ROV if enabled
              ${lib.optionalString cfg.security.rov.enable ''
                ROV_STATUS=$(vtysh -c "show rpki" | grep -c "prefix" || echo "0")
                if [ "$ROV_STATUS" -eq 0 ]; then
                  echo "$(date): Warning: No RPKI ROAs loaded" >> /var/log/gateway/byoip-health.log
                fi
              ''}

              echo "healthy" > "$HEALTH_DIR/byoip.status"
              echo "$(date): BYOIP health check passed" >> /var/log/gateway/byoip-health.log
            '';
            TimeoutSec = "30s";
          };
        };

        # BYOIP metrics exporter
        gateway-byoip-metrics = {
          description = "BYOIP Metrics Exporter";
          wantedBy = [ "multi-user.target" ];
          after = [ "frr.service" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = pkgs.writeShellScript "byoip-metrics" ''
              #!/bin/sh
              set -euo pipefail

              METRICS_DIR="/run/prometheus"
              mkdir -p "$METRICS_DIR"
              METRICS_FILE="$METRICS_DIR/gateway-byoip.prom"

              # Clear previous metrics
              > "$METRICS_FILE"

              ${lib.concatStringsSep "\n" (
                lib.mapAttrsToList (name: providerCfg: ''
                  # ${name} BGP metrics
                  STATE=$(vtysh -c "show bgp summary json" | jq -r ".ipv4Unicast.peers.\"${providerCfg.neighborIP}\".state // \"unknown\"")
                  UPTIME=$(vtysh -c "show bgp summary json" | jq -r ".ipv4Unicast.peers.\"${providerCfg.neighborIP}\".uptime // 0")
                  RECEIVED=$(vtysh -c "show bgp summary json" | jq -r ".ipv4Unicast.peers.\"${providerCfg.neighborIP}\".received // 0")
                  ADVERTISED=$(vtysh -c "show bgp summary json" | jq -r ".ipv4Unicast.peers.\"${providerCfg.neighborIP}\".advertised // 0")

                  STATE_CODE=0
                  if [ "$STATE" = "Established" ]; then
                    STATE_CODE=1
                  fi

                  echo "gateway_bgp_neighbor_state{provider=\"${name}\",neighbor=\"${providerCfg.neighborIP}\"} $STATE_CODE" >> "$METRICS_FILE"
                  echo "gateway_bgp_neighbor_uptime{provider=\"${name}\",neighbor=\"${providerCfg.neighborIP}\"} $UPTIME" >> "$METRICS_FILE"
                  echo "gateway_bgp_neighbor_routes_received{provider=\"${name}\",neighbor=\"${providerCfg.neighborIP}\"} $RECEIVED" >> "$METRICS_FILE"
                  echo "gateway_bgp_neighbor_routes_advertised{provider=\"${name}\",neighbor=\"${providerCfg.neighborIP}\"} $ADVERTISED" >> "$METRICS_FILE"
                '') cfg.providers
              )}

              # BYOIP-specific metrics
              TOTAL_PREFIXES=0
              ${lib.concatStringsSep "\n" (
                map (prefix: "TOTAL_PREFIXES=$((TOTAL_PREFIXES + 1))") (
                  lib.concatLists (map (providerCfg: providerCfg.prefixes) (lib.attrValues cfg.providers))
                )
              )}
              echo "gateway_byoip_total_prefixes $TOTAL_PREFIXES" >> "$METRICS_FILE"

              # ROV metrics
              ${lib.optionalString cfg.security.rov.enable ''
                ROV_PREFIXES=$(vtysh -c "show rpki" | grep -c "prefix" || echo "0")
                echo "gateway_byoip_rov_prefixes $ROV_PREFIXES" >> "$METRICS_FILE"
              ''}
            '';
            TimeoutSec = "30s";
          };
        };
      }
    );

    # BYOIP monitoring timers
    systemd.timers = lib.mkIf cfg.monitoring.enable {
      # BYOIP health check timer
      gateway-byoip-health-check = {
        description = "BYOIP Health Check Timer";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*:*:0/30"; # Every 30 seconds
          Unit = "gateway-byoip-health-check.service";
        };
      };

      # BYOIP metrics timer
      gateway-byoip-metrics = {
        description = "BYOIP Metrics Timer";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*:*:0/60"; # Every minute
          Unit = "gateway-byoip-metrics.service";
        };
      };
    };

    # Create log directory
    systemd.tmpfiles.rules = lib.mkIf cfg.monitoring.enable [
      "d /var/log/gateway 0755 root root -"
    ];

    # Prometheus configuration for BYOIP
    services.prometheus = lib.mkIf cfg.monitoring.enable {
      enable = true;
      port = cfg.monitoring.prometheusPort;
      exporters = {
        blackbox = {
          enable = true;
          configFile = pkgs.writeText "blackbox.yml" ''
            modules:
              bgp_check:
                prober: tcp
                timeout: 5s
                tcp:
                  query_response:
                    - expect: "Established"
          '';
        };
      };
      rules = lib.singleton (
        builtins.toJSON {
          groups = [
            {
              name = "byoip-bgp";
              rules = [
                {
                  alert = "BYOIPBGPSessionDown";
                  expr = "gateway_bgp_neighbor_state == 0";
                  for = "5m";
                  labels = {
                    severity = "critical";
                  };
                  annotations = {
                    summary = "BYOIP BGP session with {{ $labels.provider }} is down";
                    description = "BYOIP BGP session with provider {{ $labels.provider }} ({{ $labels.neighbor }}) has been down for more than 5 minutes";
                  };
                }
                {
                  alert = "BYOIPPrefixHijacking";
                  expr = "gateway_byoip_prefix_hijacking_detected > 0";
                  for = "1m";
                  labels = {
                    severity = "critical";
                  };
                  annotations = {
                    summary = "BYOIP prefix hijacking detected";
                    description = "Potential prefix hijacking detected for BYOIP prefix {{ $labels.prefix }}";
                  };
                }
              ];
            }
          ];
        }
      );
      scrapeConfigs = [
        {
          job_name = "byoip-bgp";
          static_configs = [
            {
              targets = [ "localhost:${toString cfg.monitoring.prometheusPort}" ];
            }
          ];
          metrics_path = "/metrics";
        }
      ];
    };

    # Install required packages
    environment.systemPackages = with pkgs; [
      frr
      jq
      prometheus
    ];
  };
}

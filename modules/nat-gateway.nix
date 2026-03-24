{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.gateway.natGateway;
  natConfig = import ../../lib/nat-config.nix { inherit lib pkgs; };
  natMonitoring = import ../../lib/nat-monitoring.nix { inherit lib pkgs; };
  inherit (lib)
    mkOption
    types
    mkEnableOption
    mkIf
    mkMerge
    ;

  instanceOptions = types.submodule {
    options = {
      name = mkOption {
        type = types.str;
        description = "Unique name for this NAT instance";
      };

      publicInterface = mkOption {
        type = types.str;
        description = "Network interface with public IP addresses";
      };

      privateSubnets = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "List of private subnet CIDRs to NAT";
      };

      publicIPs = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "List of public IP addresses to use for SNAT";
      };

      maxConnections = mkOption {
        type = types.int;
        default = 100000;
        description = "Maximum number of concurrent connections";
      };

      timeout = mkOption {
        type = types.submodule {
          options = {
            tcp = mkOption {
              type = types.str;
              default = "24h";
              description = "TCP connection timeout";
            };
            udp = mkOption {
              type = types.str;
              default = "300s";
              description = "UDP connection timeout";
            };
          };
        };
        default = { };
        description = "Connection timeout settings";
      };

      allowInbound = mkOption {
        type = types.bool;
        default = false;
        description = "Allow inbound connections through NAT";
      };

      portForwarding = mkOption {
        type = types.listOf (
          types.submodule {
            options = {
              protocol = mkOption {
                type = types.enum [
                  "tcp"
                  "udp"
                ];
                description = "Protocol for port forwarding";
              };
              port = mkOption {
                type = types.int;
                description = "External port to forward";
              };
              targetIP = mkOption {
                type = types.str;
                description = "Internal target IP address";
              };
              targetPort = mkOption {
                type = types.int;
                description = "Internal target port";
              };
            };
          }
        );
        default = [ ];
        description = "Port forwarding rules";
      };
    };
  };

in
{
  options.services.gateway.natGateway = {
    enable = mkEnableOption "AWS NAT Gateway replacement with SNAT functionality";

    instances = mkOption {
      type = types.listOf instanceOptions;
      default = [ ];
      description = "List of NAT gateway instances";
    };

    monitoring = mkOption {
      type = types.submodule {
        options = {
          enable = mkEnableOption "NAT Gateway monitoring";
          prometheusPort = mkOption {
            type = types.int;
            default = 9092;
            description = "Port for Prometheus metrics";
          };
        };
      };
      default = { };
      description = "Monitoring configuration";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      # Enable required kernel modules
      boot.kernelModules = [
        "nf_conntrack"
        "nf_nat"
        "iptable_nat"
        "ipt_MASQUERADE"
        "iptable_mangle"
      ];

      # Kernel parameters for NAT performance
      boot.kernel.sysctl = {
        "net.netfilter.nf_conntrack_max" = 1000000;
        "net.netfilter.nf_conntrack_tcp_timeout_established" = 86400;
        "net.netfilter.nf_conntrack_tcp_timeout_time_wait" = 120;
        "net.netfilter.nf_conntrack_tcp_timeout_close_wait" = 60;
        "net.netfilter.nf_conntrack_udp_timeout" = 30;
        "net.netfilter.nf_conntrack_udp_timeout_stream" = 180;
        "net.ipv4.ip_forward" = 1;
      };

      # Use nftables instead of iptables for consistency
      networking.nftables.enable = true;
      networking.firewall.enable = false; # Disable firewall as we manage rules directly

      # Generate NAT configuration for each instance
      systemd.services = lib.listToAttrs (
        map (
          instance:
          let
            serviceName = "nat-gateway-${instance.name}";
          in
          {
            name = serviceName;
            value = {
              description = "NAT Gateway Instance ${instance.name}";
              after = [ "network.target" "nftables.service" ];
              wantedBy = [ "multi-user.target" ];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart = "${pkgs.bash}/bin/bash -c 'set -euo pipefail; echo 1 > /proc/sys/net/ipv4/ip_forward; ${natConfig.mkSnatRules instance} && ${natConfig.mkPortForwardingRules instance} && ${natConfig.mkConntrackRules instance} && ${natConfig.mkRoutingRules instance} && echo \"NAT Gateway ${instance.name} started successfully\"'";
                ExecStop = "${pkgs.bash}/bin/bash -c 'set -euo pipefail; ${natConfig.mkNatCleanup instance} && echo \"NAT Gateway ${instance.name} stopped successfully\"'";
              };
            };
          }
        ) cfg.instances
      );
    }

    # Monitoring configuration
    (mkIf cfg.monitoring.enable {
      services.prometheus.exporters = {
        node = {
          enable = true;
          enabledCollectors = [
            "conntrack"
            "netstat"
          ];
        };
      };

      # NAT-specific monitoring
      systemd.services.nat-gateway-monitoring = {
        description = "NAT Gateway Monitoring";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart = "${natMonitoring.mkMonitoringScript cfg.instances}/bin/nat-monitor";
          Restart = "always";
          RestartSec = 10;
        };
      };

      # Prometheus scrape configuration
      services.prometheus.scrapeConfigs = [
        {
          job_name = "nat_gateway";
          static_configs = [
            {
              targets = [ "localhost:${toString cfg.monitoring.prometheusPort}" ];
            }
          ];
          scrape_interval = "30s";
          metrics_path = "/";
        }
      ];
    })
  ]);
}

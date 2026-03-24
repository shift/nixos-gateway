# IPv6 Transition Mechanisms Module
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.networking.ipv6;

  # NAT64 configuration helpers
  nat64Config = import ../lib/nat64-config.nix { inherit lib pkgs; };

  # IPv6 transition helpers
  ipv6Transition = import ../lib/ipv6-transition.nix { inherit lib pkgs; };

in
{
  options.networking.ipv6 = {
    only = mkEnableOption "IPv6-only internal network";

    nat64 = {
      enable = mkEnableOption "NAT64 translation";

      prefix = mkOption {
        type = types.str;
        default = "64:ff9b::/96";
        description = "NAT64 prefix for IPv4-mapped IPv6 addresses";
      };

      implementation = mkOption {
        type = types.enum [
          "jool"
          "tayga"
        ];
        default = "jool";
        description = "NAT64 implementation";
      };

      pool = mkOption {
        type = types.str;
        description = "IPv4 address pool for NAT64";
      };

      performance = {
        maxSessions = mkOption {
          type = types.int;
          default = 65536;
          description = "Maximum concurrent NAT64 sessions";
        };

        timeout = mkOption {
          type = types.int;
          default = 300;
          description = "Session timeout in seconds";
        };
      };
    };

    dns64 = {
      enable = mkEnableOption "DNS64 synthesis";

      server = {
        enable = mkEnableOption "Local DNS64 server";

        listen = mkOption {
          type = types.listOf types.str;
          default = [ "[::1]:53" ];
          description = "DNS64 server listen addresses";
        };

        upstream = mkOption {
          type = types.listOf types.str;
          default = [
            "8.8.8.8"
            "8.8.4.4"
          ];
          description = "Upstream DNS servers";
        };

        prefix = mkOption {
          type = types.str;
          default = "64:ff9b::/96";
          description = "DNS64 synthesis prefix";
        };
      };

      client = {
        enable = mkEnableOption "DNS64 client configuration";

        servers = mkOption {
          type = types.listOf types.str;
          default = [ "::1" ];
          description = "DNS64 servers for clients";
        };
      };
    };

    addressing = {
      mode = mkOption {
        type = types.enum [
          "slaac"
          "dhcpv6"
          "static"
        ];
        default = "slaac";
        description = "IPv6 address assignment mode";
      };

      prefix = mkOption {
        type = types.str;
        description = "IPv6 prefix for internal network";
      };

      routerAdvertisements = {
        enable = mkEnableOption "Router advertisements";

        interval = mkOption {
          type = types.int;
          default = 200;
          description = "RA interval in seconds";
        };

        managed = mkOption {
          type = types.bool;
          default = false;
          description = "Managed flag (DHCPv6)";
        };

        other = mkOption {
          type = types.bool;
          default = false;
          description = "Other configuration flag";
        };
      };
    };

    firewall = {
      enable = mkEnableOption "IPv6 firewall";

      rules = mkOption {
        type = types.listOf types.attrs;
        default = [ ];
        description = "IPv6 firewall rules";
      };

      nat64 = {
        allowForwarding = mkOption {
          type = types.bool;
          default = true;
          description = "Allow NAT64 forwarding";
        };

        restrictAccess = mkOption {
          type = types.bool;
          default = true;
          description = "Restrict NAT64 to internal networks";
        };
      };
    };

    monitoring = {
      enable = mkEnableOption "IPv6 transition monitoring";

      nat64 = {
        enable = mkEnableOption "NAT64 monitoring";

        metrics = mkOption {
          type = types.listOf types.str;
          default = [
            "sessions"
            "translations"
            "errors"
            "performance"
          ];
          description = "NAT64 metrics to collect";
        };
      };

      dns64 = {
        enable = mkEnableOption "DNS64 monitoring";

        metrics = mkOption {
          type = types.listOf types.str;
          default = [
            "queries"
            "synthesis"
            "cache"
            "errors"
          ];
          description = "DNS64 metrics to collect";
        };
      };
    };
  };

  config = mkIf (cfg.only || cfg.nat64.enable || cfg.dns64.enable) {
    # Enable IPv6 forwarding
    boot.kernel.sysctl = {
      "net.ipv6.conf.all.forwarding" = mkDefault true;
      "net.ipv6.conf.all.accept_ra" = mkDefault 2;
      "net.ipv6.conf.all.accept_redirects" = mkDefault 1;
    };

    # Required packages
    environment.systemPackages = with pkgs; [
      jool # NAT64 implementation
      radvd # Router advertisements
      dhcp6c # DHCPv6 client
      wide-dhcpv6-client # Alternative DHCPv6 client
      ndisc6 # IPv6 neighbor discovery
      rdisc6 # Router discovery
      bind # DNS server with DNS64 support
      unbound # Alternative DNS server
      ip6tables # IPv6 firewall
      iproute2 # Advanced IPv6 routing
      ndisc6 # IPv6 discovery tools
    ];

    # NAT64 service
    systemd.services.nat64 = mkIf cfg.nat64.enable {
      description = "NAT64 Translation Service";
      wantedBy = [ "network.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = 5;
        ExecStart = nat64Config.mkNat64Service cfg.nat64;
        ExecReload = "${pkgs.jool}/bin/jool --instance ${cfg.nat64.implementation} --flush";
      };
    };

    # DNS64 service
    systemd.services.dns64 = mkIf cfg.dns64.server.enable {
      description = "DNS64 Synthesis Service";
      wantedBy = [ "network.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = 5;
        ExecStart = ipv6Transition.mkDns64Service cfg.dns64.server;
      };
    };

    # Router advertisements
    systemd.services.radvd = mkIf cfg.addressing.routerAdvertisements.enable {
      description = "IPv6 Router Advertisement Service";
      wantedBy = [ "network.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = 5;
        ExecStart = pkgs.writeShellScript "radvd-start" ''
          set -euo pipefail

          # Generate radvd.conf
          cat > /etc/radvd.conf << EOF
          interface ${ipv6Transition.getRadvdInterface cfg}
          ${ipv6Transition.mkRadvdConfig cfg}
          EOF

          exec ${pkgs.radvd}/bin/radvd -C /etc/radvd.conf
        '';
      };
    };

    # DHCPv6 client
    systemd.services.dhcp6c = mkIf (cfg.addressing.mode == "dhcpv6") {
      description = "IPv6 DHCP Client";
      wantedBy = [ "network-online.target" ];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = 5;
        ExecStart = pkgs.writeShellScript "dhcp6c-start" ''
          set -euo pipefail

          # Get primary interface
          INTERFACE=${ipv6Transition.getPrimaryInterface cfg}

          # Request IPv6 address
          exec ${pkgs.dhcp6c}/bin/dhcp6c -i $INTERFACE -d -v
        '';
      };
    };

    # IPv6 firewall rules
    networking.firewall.extraCommands = mkIf cfg.firewall.enable ''
      # Clear existing IPv6 rules
      ip6tables -F
      ip6tables -X

      # Create NAT64 chain
      ip6tables -N NAT64

      ${lib.concatMapStringsSep "\n" (rule: ''
        # Add rule: ${rule.description or ""}
        ip6tables -A ${rule.chain or "INPUT"} ${
          lib.concatStringsSep " " (rule.options or [ ])
        } -j ${rule.target or "ACCEPT"}
      '') cfg.firewall.rules}

      ${lib.optionalString cfg.firewall.nat64.allowForwarding ''
        # Allow NAT64 forwarding
        ip6tables -A FORWARD -m comment --comment "NAT64" -j ACCEPT
      ''}

      ${lib.optionalString cfg.firewall.nat64.restrictAccess ''
        # Restrict NAT64 to internal networks only
        ip6tables -A FORWARD -m comment --comment "NAT64-internal" -s ${
          cfg.nat64.pool or "192.168.0.0/16"
        } -j ACCEPT
        ip6tables -A FORWARD -m comment --comment "NAT64-block" -d ${
          cfg.nat64.pool or "192.168.0.0/16"
        } -j DROP
      ''}
    '';

    # Network configuration
    networking.localCommands = mkIf cfg.only ''
      # Configure IPv6-only networking
      ${ipv6Transition.mkNetworkConfig cfg}

      # Disable IPv4 on internal interfaces
      ${ipv6Transition.mkDisableIPv4 cfg}
    '';

    # Monitoring services
    systemd.services.ipv6-monitor = mkIf cfg.monitoring.enable {
      description = "IPv6 Transition Monitoring";
      wantedBy = [ "network.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = 30;
        ExecStart = ipv6Transition.mkMonitoringService cfg;
      };
    };

    # DNS64 client configuration
    environment.etc."resolv.conf".text = mkIf (cfg.dns64.client.enable && !cfg.dns64.server.enable) ''
      # DNS64 configuration
      ${lib.concatMapStringsSep "\n" (server: "nameserver ${server}") cfg.dns64.client.servers}
    '';

    # IPv6 address configuration
    networking.interfaces = mkIf (cfg.addressing.mode == "static") (
      nat64Config.mkStaticInterfacesAttributeSet cfg
    );
  };
}

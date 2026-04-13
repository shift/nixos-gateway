{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.gateway;

  # All modules are imported unconditionally.
  # Each module gates itself with lib.mkIf based on cfg.profile or its own enable flag.
  # This avoids infinite recursion from referencing `config` in `imports`.
  #
  # Profile behavior:
  #   full:            dns.nix + dhcp.nix (Kea/Knot/kresd) + monitoring.nix + security.nix + ...
  #   alix-networkd:   dns-lean-unbound.nix + dhcp-networkd.nix + monitoring-lean.nix
  #   alix-dnsmasq:    dns-dnsmasq.nix + monitoring-lean.nix
  # Shared across all: network.nix + nat-gateway.nix + policy-routing.nix + vpn.nix + ...

in
{
  imports = [
    # Core (all profiles)
    ./network.nix
    ./nat-gateway.nix
    ./policy-routing.nix
    ./aethalloc.nix
    ./vpn.nix

    # Full profile modules (gated internally by profile == "full" or own enable flags)
    ./dns.nix
    ./dhcp.nix
    ./monitoring.nix
    ./health-monitoring
    ./security.nix
    ./management-ui.nix
    ./troubleshooting.nix
    ./xdp-firewall.nix
    ./vrf.nix
    ./8021x.nix
    ./sdwan.nix
    ./ipv6-transition.nix
    ./secrets.nix
    ./frr.nix

    # ALIX profile modules (gated internally by profile == "alix-*")
    ./dns-lean-unbound.nix
    ./dns-dnsmasq.nix
    ./dhcp-networkd.nix
    ./wifi-ap.nix
    ./monitoring-lean.nix
    ./disk-alix.nix
  ];

  options.services.gateway = {
    enable = lib.mkEnableOption "NixOS Gateway Services";

    profile = lib.mkOption {
      type = lib.types.enum [ "full" "alix-networkd" "alix-dnsmasq" ];
      default = "full";
      description = ''
        Gateway profile selects backend implementations.
        All profiles present the same configuration interface (services.gateway.data.*).
        - full: Kea DHCP, Knot DNS + kresd, full monitoring, all modules.
        - alix-networkd: systemd-networkd DHCP, unbound DNS, lean monitoring.
        - alix-dnsmasq: dnsmasq combined DNS+DHCP, lean monitoring.
      '';
    };

    interfaces = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      example = {
        lan = "enp1s0f0";
        wan = "enp1s0f1";
        wwan = "wwan0";
        mgmt = "eno1";
      };
      description = "Physical network interfaces mapping";
    };

    redInterfaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "eth0"
        "eth1"
      ];
      description = "WAN/external (red zone) interfaces for firewall and QoS";
    };

    greenInterfaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "eth2"
        "eth3"
      ];
      description = "LAN/internal (green zone) interfaces for firewall and QoS";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "lan.local";
      example = "example.com";
      description = "Primary domain name for the gateway";
    };

    data = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Gateway configuration data";
    };

    ipv6Prefix = lib.mkOption {
      type = lib.types.str;
      default = "2001:db8::";
      example = "2001:db8::/48";
      description = "IPv6 prefix for gateway services";
    };
  };
}

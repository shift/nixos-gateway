{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.gateway;

  # Full profile imports - all modules, heavy but feature-complete
  fullImports = [
    ./dns.nix
    ./dhcp.nix
    ./network.nix
    ./monitoring.nix
    ./health-monitoring
    ./security.nix
    ./management-ui.nix
    ./troubleshooting.nix
    ./xdp-firewall.nix # XDP/eBPF Data Plane Acceleration
    ./vrf.nix # VRF (Virtual Routing and Forwarding) Support
    ./8021x.nix # 802.1X Network Access Control
    ./sdwan.nix # SD-WAN Traffic Engineering
    ./ipv6-transition.nix # IPv6 Transition Mechanisms
    ./secrets.nix # Secrets Management
    ./nat-gateway.nix # NAT Gateway Configuration
    ./frr.nix # FRR BGP Routing
    ./policy-routing.nix # Policy-Based Routing
    ./aethalloc.nix # AethAlloc memory allocator (optional, default enabled)
  ];

  # ALIX-shared imports - lightweight modules common to both ALIX profiles
  alixSharedImports = [
    ./network.nix # systemd-networkd + nftables (shared core)
    ./nat-gateway.nix # nftables NAT rules
    ./policy-routing.nix # nftables policy routing
    ./wifi-ap.nix # hostapd WiFi AP
    ./monitoring-lean.nix # Rust gateway-health D-Bus service
    ./vpn.nix # WireGuard VPN
    ./disk-alix.nix # CF-friendly storage (ext4-noatime)
    ./aethalloc.nix # AethAlloc option definitions (no heavy services, just options)
  ];

  # alix-networkd profile - systemd-networkd DHCP + unbound DNS
  alixNetworkdImports = alixSharedImports ++ [
    ./dns-lean-unbound.nix # unbound recursive DNS caching
    ./dhcp-networkd.nix # systemd-networkd built-in DHCP server
  ];

  # alix-dnsmasq profile - dnsmasq combined DNS+DHCP
  alixDnsmasqImports = alixSharedImports ++ [
    ./dns-dnsmasq.nix # dnsmasq DNS caching + authoritative + DHCP
  ];

  # Select imports based on profile
  profileImports =
    if cfg.profile == "full" then
      fullImports
    else if cfg.profile == "alix-networkd" then
      alixNetworkdImports
    else if cfg.profile == "alix-dnsmasq" then
      alixDnsmasqImports
    else
      fullImports;

in
{
  imports = profileImports;

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

{
  config,
  pkgs,
  lib,
  ...
}:

{
  imports = [
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
    # ./api-gateway.nix  # Temporarily disabled - complex dependencies
  ];

  options.services.gateway = {
    enable = lib.mkEnableOption "NixOS Gateway Services";

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

    # frr = lib.mkOption {
    #   type = lib.types.submodule {
    #     options = {
    #       enable = lib.mkEnableOption "FRR BGP routing";
    #       bgp = lib.mkOption {
    #         type = lib.types.submodule {
    #           options = {
    #             enable = lib.mkEnableOption "BGP protocol";
    #             asn = lib.mkOption {
    #               type = lib.types.int;
    #               default = 65001;
    #               description = "Autonomous System Number";
    #             };
    #             routerId = lib.mkOption {
    #               type = lib.types.str;
    #               default = "router1";
    #               description = "BGP router identifier";
    #             };
    #           };
    #         };
    #       };
    #     };
    #   };
    #   default = { };
    #   description = "FRR routing configuration";
    # };
  };
}

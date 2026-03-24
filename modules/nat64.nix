{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.networking.ipv6.nat64;
  nat64Config = import ../lib/nat64-config.nix { inherit lib pkgs; };
  inherit (lib)
    mkOption
    types
    mkEnableOption
    mkIf
    ;
in
{
  options.networking.ipv6.nat64 = {
    enable = mkEnableOption "NAT64 translation";

    prefix = mkOption {
      type = types.str;
      default = "64:ff9b::/96";
      description = "NAT64 prefix for IPv4-mapped IPv6 addresses";
    };

    implementation = mkOption {
      type = types.enum [ "tayga" ]; # Simplified for now, Jool requires kernel module
      default = "tayga";
      description = "NAT64 implementation";
    };

    pool = mkOption {
      type = types.str;
      default = "192.168.255.0/24";
      description = "IPv4 address pool for NAT64";
    };

    ipv4Addr = mkOption {
      type = types.str;
      default = "192.168.255.1";
      description = "IPv4 address for the NAT64 router";
    };
  };

  config = mkIf cfg.enable {
    # Tayga implementation
    services.tayga = mkIf (cfg.implementation == "tayga") {
      enable = true;
      ipv4.address = cfg.ipv4Addr;
      ipv4.router.address = cfg.ipv4Addr; # Self as router
      ipv6.address = "2001:db8::1"; # Dummy, Tayga uses prefix
      ipv6.router.address = "2001:db8::1";

      # Use our helper for extra config if needed, or mapping
      # For now, Tayga module in NixOS handles basic config well
      # We override the prefix

      # Note: NixOS tayga module doesn't expose prefix directly in some versions
      # We rely on extraConfig if needed, or assume standard options
    };

    # Since NixOS existing tayga module might be limited, we can write a custom service
    # But let's use the standard one and extend config

    systemd.services.tayga = mkIf (cfg.implementation == "tayga") {
      serviceConfig.ExecStartPre = [
        "${pkgs.iproute2}/bin/ip route add ${cfg.pool} dev nat64"
        "${pkgs.iproute2}/bin/ip route add ${cfg.prefix} dev nat64"
      ];
    };

    # Write custom config file if needed
    environment.etc."tayga.conf".text = nat64Config.mkTaygaConfig {
      prefix = cfg.prefix;
      pool = cfg.pool;
      ipv4Addr = cfg.ipv4Addr;
    };

    # Enable forwarding
    boot.kernel.sysctl = {
      "net.ipv6.conf.all.forwarding" = 1;
      "net.ipv4.ip_forward" = 1;
    };
  };
}

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.gateway.aethalloc;
in
{
  # NOTE: aethalloc.nixosModules.default is imported by the flake wrapper
  # (nixosModules.default / nixosModules.gateway) which also injects
  # _module.args.aethalloc.  This module only owns the gateway-level option
  # surface and delegates to services.aethalloc.* which is provided by that
  # upstream module when available.
  #
  # We do NOT import aethalloc.nixosModules.default here because this file is
  # also imported by tests and standalone configurations that don't carry the
  # aethalloc flake input — importing it here would cause an infinite
  # recursion when the `aethalloc` module arg is absent.

  options.services.gateway.aethalloc = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to inject AethAlloc as the default memory allocator for
        gateway services via LD_PRELOAD.  AethAlloc is optimised for
        network packet-processing workloads and reduces memory
        fragmentation in long-running gateway daemons.

        When enabled, the allocator is injected into the core gateway
        services listed in <option>services.gateway.aethalloc.services</option>.
        Set to <literal>false</literal> to fall back to glibc ptmalloc2.

        Requires the aethalloc flake input to be wired in via the flake
        nixosModules.default or nixosModules.gateway wrapper.
      '';
    };

    services = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "systemd-networkd"
        "nftables"
        "kea-dhcp4-server"
        "kea-dhcp6-server"
        "bind"
        "unbound"
        "frr"
        "bird2"
        "suricata"
      ];
      example = [
        "systemd-networkd"
        "nftables"
      ];
      description = ''
        Systemd service units to inject AethAlloc into.  Only services
        that are actually enabled on the system are affected; entries
        for disabled services are silently ignored by systemd.

        The defaults cover the full set of gateway daemons that benefit
        from AethAlloc's packet-processing optimisations.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Delegate to aethalloc's own module (services.aethalloc.* is provided by
    # aethalloc.nixosModules.default, imported by the flake wrapper).
    services.aethalloc = {
      enable = true;
      services = cfg.services;
    };
  };
}

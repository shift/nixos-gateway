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
  # This module only declares the gateway-level option surface.
  # Actual delegation to services.aethalloc.* (from aethalloc.nixosModules.default)
  # happens in the flake nixosModules.default / nixosModules.gateway wrapper,
  # where aethalloc.nixosModules.default is co-imported and the upstream option
  # namespace exists.  Keeping the delegation here would cause NixOS strict
  # option checking to error on `services.aethalloc' being undefined in tests
  # and standalone configurations that don't go through the flake wrapper.

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

}

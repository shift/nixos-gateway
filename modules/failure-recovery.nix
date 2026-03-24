{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.services.nixos-gateway.failure-recovery;
in
{
  options.services.nixos-gateway.failure-recovery = {
    enable = mkEnableOption "Failure Recovery and Chaos Engineering Framework";

    enableChaosTools = mkOption {
      type = types.bool;
      default = false;
      description = "Enable installation of chaos engineering tools (stress-ng, tc, etc.)";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = mkIf cfg.enableChaosTools (
      with pkgs;
      [
        stress-ng
        iproute2
        procps
        unixtools.ping
      ]
    );

    # Placeholder for future automated failure injection service
    # systemd.services.failure-injector = { ... };
  };
}

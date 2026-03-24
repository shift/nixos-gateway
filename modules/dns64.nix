{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.networking.ipv6.dns64;
  ipv6Transition = import ../lib/ipv6-transition.nix { inherit lib pkgs; };
  inherit (lib)
    mkOption
    types
    mkEnableOption
    mkIf
    ;
in
{
  options.networking.ipv6.dns64 = {
    enable = mkEnableOption "DNS64 synthesis";

    server = {
      enable = mkEnableOption "Local DNS64 server (Unbound)";

      prefix = mkOption {
        type = types.str;
        default = "64:ff9b::/96";
        description = "DNS64 synthesis prefix";
      };

      interfaces = mkOption {
        type = types.listOf types.str;
        default = [ "::1" ];
      };
    };
  };

  config = mkIf (cfg.enable && cfg.server.enable) {
    services.unbound = {
      enable = true;
      settings = {
        server = {
          interface = cfg.server.interfaces;
          access-control = [ "::0/0 allow" ];
          module-config = "dns64 validator iterator";
          "dns64-prefix" = cfg.server.prefix;
          "dns64-synthall" = "no";
        };
      };
    };
  };
}

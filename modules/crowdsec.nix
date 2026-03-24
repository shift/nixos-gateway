{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.gateway;
in
{
  config = lib.mkIf (cfg.security.engine == "crowdsec") {
    environment.systemPackages = with pkgs; [ crowdsec ];
  };
}

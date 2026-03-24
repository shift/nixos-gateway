{ config, pkgs, lib, ... }:

{
  options.services.routing-ip-forwarding = {
    enable = lib.mkEnableOption "Routing and IP forwarding";
  };

  config = lib.mkIf config.services.routing-ip-forwarding.enable {
    assertions = [
      {
        assertion = true;
        message = "Routing and IP forwarding configuration";
      }
    ];
  };
}

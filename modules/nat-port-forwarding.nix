{ config, pkgs, lib, ... }:

{
  options.services.nat-port-forwarding = {
    enable = lib.mkEnableOption "NAT and port forwarding";
  };

  config = lib.mkIf config.services.nat-port-forwarding.enable {
    assertions = [
      {
        assertion = true;
        message = "NAT and port forwarding configuration";
      }
    ];
  };
}

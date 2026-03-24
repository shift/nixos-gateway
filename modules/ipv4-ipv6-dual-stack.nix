{ config, pkgs, lib, ... }:

{
  options.services.ipv4-ipv6-dual-stack = {
    enable = lib.mkEnableOption "IPv4/IPv6 dual-stack networking";
  };

  config = lib.mkIf config.services.ipv4-ipv6-dual-stack.enable {
    assertions = [
      {
        assertion = true;
        message = "IPv4/IPv6 dual-stack configuration";
      }
    ];
  };
}

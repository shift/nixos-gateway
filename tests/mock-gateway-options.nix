{ lib, ... }:
{
  options.services.gateway = {
    interfaces = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        eth0 = "eth0";
        eth1 = "eth1";
      };
    };
    data = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {
        firewall = null;
      };
    };
  };
}

{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.gateway.netboot or { };
in
{
  config = lib.mkIf (cfg.enable or false) {
    services.atftpd = {
      enable = true;
      root = cfg.root or "/var/lib/tftpboot";
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.root or "/var/lib/tftpboot"} 0755 root root -"
      "L+ ${
        cfg.root or "/var/lib/tftpboot"
      }/netboot.xyz.kpxe - - - - ${pkgs.netboot-xyz}/netboot.xyz.kpxe"
      "L+ ${cfg.root or "/var/lib/tftpboot"}/netboot.xyz.efi - - - - ${pkgs.netboot-xyz}/netboot.xyz.efi"
    ];
  };
}

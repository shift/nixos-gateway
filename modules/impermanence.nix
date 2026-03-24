{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.services.gateway.persistence or { };
in
{
  config = lib.mkIf (cfg.enable or false) {
    environment.persistence.${cfg.persistPath} =
      lib.mkIf (config.environment.persistence.enable or false)
        {
          enable = true;
          hideMounts = true;

          directories = [
            "/etc/ssh"
            "/etc/NetworkManager/system-connections"
            "/var/lib/nixos"
            "/var/lib/systemd/timers"
            "/var/log"
            "/var/lib/kea"
            "/var/lib/knot"
            "/var/lib/kresd"
            "/var/cache/knot-resolver"
            "/var/lib/suricata"
            "/var/log/suricata"
            "/var/lib/acme"
            "/var/lib/prometheus"
            "/var/lib/grafana-alloy"
            "/var/log/dnscollector"
            "/var/lib/prometheus-node-exporter-text-files"
          ]
          ++ (lib.optionals (config.services.gateway.adblock.enable or false) [ "/var/lib/adblock" ])
          ++ (lib.optionals (config.services.gateway.tailscale.enable or false) [ "/var/lib/tailscale" ])
          ++ (lib.optionals (config.services.gateway.wireguard.enable or false) [ "/var/lib/wireguard" ])
          ++ cfg.extraDirectories;

          files = [ "/etc/machine-id" ] ++ cfg.extraFiles;
        };

    fileSystems.${cfg.persistPath}.neededForBoot = true;
  };
}

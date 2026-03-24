{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.gateway;
  captiveCfg = cfg.captivePortal;

  portalChecker = pkgs.writeShellScript "check-captive-portal" ''
    set -u

    METRICS_FILE="/var/lib/prometheus-node-exporter-text-files/captive_portal.prom"
    mkdir -p $(dirname $METRICS_FILE)

    if ! ${pkgs.iproute2}/bin/ip link show ${captiveCfg.interface} | grep -q "state UP"; then
       echo "wifi_status{interface=\"${captiveCfg.interface}\"} 0" > $METRICS_FILE
       echo "wifi_captive_portal{interface=\"${captiveCfg.interface}\"} 0" >> $METRICS_FILE
       exit 0
    fi

    HTTP_CODE=$(${pkgs.curl}/bin/curl --interface ${captiveCfg.interface} \
      --connect-timeout ${toString captiveCfg.checkTimeout} \
      --write-out "%{http_code}" \
      --silent \
      --output /dev/null \
      ${captiveCfg.checkUrl})

    if [ "$HTTP_CODE" -eq 204 ]; then
       echo "wifi_status{interface=\"${captiveCfg.interface}\"} 1" > $METRICS_FILE
       echo "wifi_captive_portal{interface=\"${captiveCfg.interface}\"} 0" >> $METRICS_FILE
       
       CURRENT_METRIC=$(${pkgs.iproute2}/bin/ip -4 route show dev ${captiveCfg.interface} default | grep -oP 'metric \K\d+' || echo "0")
       if [ "$CURRENT_METRIC" -gt ${toString captiveCfg.normalMetric} ]; then
         ${pkgs.iproute2}/bin/ip -4 route del default dev ${captiveCfg.interface} metric $CURRENT_METRIC
         GW=$(${pkgs.iproute2}/bin/ip -4 route show dev ${captiveCfg.interface} default | awk '{print $3}')
         ${lib.optionalString (captiveCfg.gateway != null) ''GW="${captiveCfg.gateway}"''}
         ${pkgs.iproute2}/bin/ip -4 route add default via $GW dev ${captiveCfg.interface} metric ${toString captiveCfg.normalMetric}
         echo "Restored WiFi priority"
       fi
       
       ${lib.optionalString captiveCfg.manageTailscale ''
         if ! systemctl is-active --quiet tailscale; then
           systemctl start tailscale
           echo "Started Tailscale after captive portal cleared"
         fi
       ''}

    else
       echo "wifi_status{interface=\"${captiveCfg.interface}\"} 1" > $METRICS_FILE
       echo "wifi_captive_portal{interface=\"${captiveCfg.interface}\"} 1" >> $METRICS_FILE
       
       ${lib.optionalString captiveCfg.manageTailscale ''
         if systemctl is-active --quiet tailscale; then
           systemctl stop tailscale
           echo "Stopped Tailscale to allow Captive Portal Login"
         fi
       ''}
       
       CURRENT_METRIC=$(${pkgs.iproute2}/bin/ip -4 route show dev ${captiveCfg.interface} default | grep -oP 'metric \K\d+' || echo "0")
       if [ "$CURRENT_METRIC" -lt 1000 ]; then
         GW=$(${pkgs.iproute2}/bin/ip -4 route show dev ${captiveCfg.interface} default | awk '{print $3}')
         ${lib.optionalString (captiveCfg.gateway != null) ''GW="${captiveCfg.gateway}"''}
         ${pkgs.iproute2}/bin/ip -4 route del default dev ${captiveCfg.interface} metric $CURRENT_METRIC
         ${pkgs.iproute2}/bin/ip -4 route add default via $GW dev ${captiveCfg.interface} metric ${toString captiveCfg.portalMetric}
         echo "Deprioritized WiFi due to Captive Portal ($HTTP_CODE)"
       fi
    fi
  '';

in
{
  options.services.gateway.captivePortal = {
    enable = lib.mkEnableOption "WiFi captive portal detection and handling";

    interface = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "WiFi interface to monitor for captive portals";
    };

    checkUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://connectivitycheck.gstatic.com/generate_204";
      description = "URL to check for captive portal (should return HTTP 204)";
    };

    checkTimeout = lib.mkOption {
      type = lib.types.int;
      default = 5;
      description = "Connection timeout in seconds for portal check";
    };

    checkInterval = lib.mkOption {
      type = lib.types.str;
      default = "15s";
      description = "How often to check for captive portal (systemd time format)";
    };

    gateway = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "192.168.178.1";
      description = "WiFi gateway IP (auto-detected if null)";
    };

    normalMetric = lib.mkOption {
      type = lib.types.int;
      default = 50;
      description = "Route metric when WiFi is working normally";
    };

    portalMetric = lib.mkOption {
      type = lib.types.int;
      default = 5000;
      description = "Route metric when captive portal is detected (deprioritize)";
    };

    manageTailscale = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Automatically stop/start Tailscale when portal is detected/cleared";
    };
  };

  config = lib.mkIf (cfg.enable && captiveCfg.enable) {
    systemd.services.captive-portal-check = {
      description = "Check for WiFi Captive Portal";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = portalChecker;
      };
    };

    systemd.timers.captive-portal-check = {
      description = "Run captive portal check";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "1m";
        OnUnitActiveSec = captiveCfg.checkInterval;
      };
    };
  };
}

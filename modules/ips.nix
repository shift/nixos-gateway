{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.gateway;
  enabled = cfg.enable or true;

  # Import schema normalization
  schemaNormalization = import ../lib/schema-normalization.nix { inherit lib; };

  networkData = schemaNormalization.normalizeNetworkData (cfg.data.network or { });
  idsData = cfg.data.ids or { };
in
{
  config = lib.mkIf enabled {
    systemd.tmpfiles.rules = [
      "d /var/lib/suricata 0755 suricata suricata -"
      "d /var/lib/suricata/update 0755 suricata suricata -"
      "d /var/lib/suricata/update/sources 0755 suricata suricata -"
      "d /run/suricata 0755 suricata suricata -"
    ];

    services.suricata = {
      enable = true;
      settings = {
        unix-command = {
          enabled = true;
          filename = "/run/suricata/suricata.socket";
        };

        vars = {
          address-groups = {
            HOME_NET = "[${schemaNormalization.getSubnetNetwork networkData "lan"},${cfg.ipv6Prefix or "2001:db8::"}/48]";
            EXTERNAL_NET = "!$HOME_NET";
          };
        };

        # Crucial for Intel CPUs
        detect-engine = [
          {
            profile = idsData.detectEngine.profile or "medium";
            sgh-mpm-context = idsData.detectEngine.sghMpmContext or "auto";
            mpm-algo = idsData.detectEngine.mpmAlgo or "hs";
          }
        ];
        threading = {
          set-cpu-affinity = if (idsData.threading.setCpuAffinity or false) then "yes" else "no";
          cpu-affinity = lib.optionals (idsData.threading or null != null) [
            {
              management-cpu-set = {
                cpu = idsData.threading.managementCpus or [ 0 ];
              };
            }
            {
              worker-cpu-set = {
                cpu =
                  idsData.threading.workerCpus or [
                    1
                    2
                    3
                  ];
              };
            }
          ];
        };

        default-log-dir = "/var/log/suricata";

        outputs = [
          {
            eve-log = {
              enabled = idsData.logging.eveLog.enabled or true;
              filetype = "regular";
              filename = "eve.json";
              types = map (type: { ${type} = { }; }) (
                idsData.logging.eveLog.types or [
                  "alert"
                  "http"
                  "dns"
                ]
              );
            };
          }
        ];

        af-packet = map (iface: {
          interface = iface;
          threads = "auto";
          cluster-type = "cluster_flow";
          defrag = true;
        }) cfg.greenInterfaces;

        nfqueue = [
          {
            mode = "repeat";
            repeat-mark = 1;
            repeat-mask = 1;
          }
        ];

        app-layer = {
          protocols = {
            http = {
              enabled = if (idsData.protocols.http.enabled or true) then "yes" else "no";
            };
            tls = {
              enabled = if (idsData.protocols.tls.enabled or true) then "yes" else "no";
              detection-ports = {
                dp = lib.head (idsData.protocols.tls.ports or [ 443 ]);
              };
            };
            dns = {
              enabled = if (idsData.protocols.dns.enabled or true) then "yes" else "no";
              tcp = {
                enabled = if (idsData.protocols.dns.tcp or true) then "yes" else "no";
              };
              udp = {
                enabled = if (idsData.protocols.dns.udp or true) then "yes" else "no";
              };
            };
            modbus = {
              enabled = if (idsData.protocols.modbus.enabled or false) then "yes" else "no";
              detection-enabled = if (idsData.protocols.modbus.detectionEnabled or false) then "yes" else "no";
            };
          };
        };
      };
    };

    systemd.services.suricata = {
      serviceConfig = {
        ProtectProc = lib.mkForce "default";
        RuntimeDirectory = "suricata";
        RuntimeDirectoryMode = "0755";
      };
    };

    systemd.services.suricata-exporter = {
      description = "Suricata Prometheus Exporter";
      after = [ "suricata.service" ];
      wants = [ "suricata.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.coreutils}/bin/echo 'Suricata exporter would start here'";
        Restart = "on-failure";
        RestartSec = "5s";

        DynamicUser = true;
        SupplementaryGroups = [ "suricata" ];

        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };

    systemd.services.suricata-update = {
      after = [ "kresd@1.service" ];
      wants = [ "kresd@1.service" ];
    };

    systemd.timers.suricata-update = {
      enable = false;
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
    };

    # Log rotation for Suricata
    services.logrotate = lib.mkIf (idsData.logging.rotation or null != null) {
      enable = true;
      settings = {
        "/var/log/suricata/*.log" = {
          rotate = idsData.logging.rotation.logs.days or 7;
          daily = true;
          compress = idsData.logging.rotation.logs.compress or true;
          delaycompress = true;
          missingok = true;
          notifempty = true;
          postrotate = "systemctl reload suricata.service";
        };
        "/var/log/suricata/*.json" = {
          rotate = idsData.logging.rotation.json.days or 30;
          daily = true;
          compress = idsData.logging.rotation.json.compress or true;
          delaycompress = true;
          missingok = true;
          notifempty = true;
          maxsize = idsData.logging.rotation.json.maxSize or "1G";
        };
      };
    };
  };
}

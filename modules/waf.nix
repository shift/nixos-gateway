{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.services.gateway;
  enabled = cfg.enable or true;
in
{
  options.services.gateway = {
    waf = {
      enable = lib.mkEnableOption "Web Application Firewall";

      engine = lib.mkOption {
        type = lib.types.enum [
          "modsecurity"
          "coraza"
        ];
        default = "modsecurity";
        description = "WAF engine to use";
      };

      sites = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              enable = lib.mkEnableOption "WAF for this site";

              rules = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "Custom WAF rules";
              };

              crs = {
                enable = lib.mkEnableOption "OWASP Core Rule Set";
                paranoiaLevel = lib.mkOption {
                  type = lib.types.ints.between 1 4;
                  default = 1;
                  description = "CRS paranoia level";
                };
              };

              rateLimit = {
                enable = lib.mkEnableOption "Rate limiting";
                requestsPerMinute = lib.mkOption {
                  type = lib.types.int;
                  default = 1000;
                  description = "Requests per minute limit";
                };
              };

              compliance = lib.mkOption {
                type = lib.types.listOf (
                  lib.types.enum [
                    "pci-dss"
                    "hipaa"
                    "gdpr"
                  ]
                );
                default = [ ];
                description = "Compliance standards to enforce";
              };
            };
          }
        );
        default = { };
        description = "WAF configuration per site";
      };

      monitoring = {
        enable = lib.mkEnableOption "WAF monitoring";
        metricsPort = lib.mkOption {
          type = lib.types.port;
          default = 9092;
          description = "Port for WAF metrics export";
        };
      };

      threatIntelligence = {
        enable = lib.mkEnableOption "Automated threat intelligence updates";
        updateInterval = lib.mkOption {
          type = lib.types.str;
          default = "hourly";
          description = "How often to update threat intelligence feeds";
        };
      };
    };
  };

  config = lib.mkIf (enabled && cfg.waf.enable) {
    # Install required packages
    environment.systemPackages = with pkgs; [
      # ModSecurity packages would be added here when available
      curl
      jq
    ];

    # Create WAF configuration directory
    systemd.tmpfiles.rules = [
      "d /etc/waf 0755 root root -"
      "d /etc/waf/rules 0755 root root -"
      "d /etc/waf/logs 0755 nginx nginx -"
      "d /var/lib/waf 0755 root root -"
    ];

    # WAF rule management service
    systemd.services.waf-rule-manager = {
      description = "WAF Rule Manager";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = "${pkgs.bash}/bin/bash ${./waf-rule-manager.sh}";
        RemainAfterExit = true;
      };
    };

    # Threat intelligence update service
    systemd.services.waf-threat-intel-update = lib.mkIf cfg.waf.threatIntelligence.enable {
      description = "WAF Threat Intelligence Update";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = "${pkgs.bash}/bin/bash ${./waf-threat-intel.sh}";
      };

      # Run updates based on configured interval
      startAt = cfg.waf.threatIntelligence.updateInterval;
    };

    # Monitoring service
    systemd.services.waf-monitoring = lib.mkIf cfg.waf.monitoring.enable {
      description = "WAF Monitoring Service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        ExecStart = "${pkgs.bash}/bin/bash ${./waf-monitoring.sh} ${toString cfg.waf.monitoring.metricsPort}";
        Restart = "always";
        User = "nginx";
        Group = "nginx";
      };
    };

    # Nginx integration
    services.nginx = lib.mkIf (cfg.api-gateway.enable or cfg.load-balancing.enable) {
      additionalModules = [
        # ModSecurity nginx module would be added here
      ];

      appendHttpConfig = ''
        # WAF Configuration
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (siteName: siteCfg: ''
            server {
              listen 80;
              server_name ${siteName};

              ${lib.optionalString siteCfg.enable ''
                # Enable ModSecurity
                modsecurity on;
                modsecurity_rules_file /etc/waf/rules/${siteName}.conf;

                # Rate limiting
                ${lib.optionalString siteCfg.rateLimit.enable ''
                  limit_req_zone $binary_remote_addr zone=${siteName}_rate:10m rate=${toString siteCfg.rateLimit.requestsPerMinute}r/m;
                  limit_req zone=${siteName}_rate burst=20 nodelay;
                ''}

                # Custom rules
                ${lib.concatStringsSep "\n" (map (rule: "modsecurity_rules '${rule}';") siteCfg.rules)}
              ''}

              location / {
                proxy_pass http://backend;
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto $scheme;
              }
            }
          '') cfg.waf.sites
        )}
      '';
    };

    # Log rotation
    services.logrotate = {
      enable = true;
      settings.waf = {
        files = "/etc/waf/logs/*.log";
        frequency = "daily";
        rotate = 30;
        compress = true;
        postrotate = "systemctl reload waf-monitoring";
      };
    };

    # Prometheus monitoring
    services.prometheus = lib.mkIf cfg.waf.monitoring.enable {
      exporters.nginx = {
        enable = true;
        port = cfg.waf.monitoring.metricsPort;
      };

      scrapeConfigs = [
        {
          job_name = "waf";
          static_configs = [
            {
              targets = [ "localhost:${toString cfg.waf.monitoring.metricsPort}" ];
            }
          ];
        }
      ];
    };

    # Alerting rules
    services.prometheus.alertmanager = lib.mkIf cfg.waf.monitoring.enable {
      enable = true;
      configuration = {
        route = {
          group_by = [ "alertname" ];
          group_wait = "10s";
          group_interval = "10s";
          repeat_interval = "1h";
          receiver = "admin";
        };
        receivers = [
          {
            name = "admin";
            email_configs = [
              {
                to = "admin@example.com";
                from = "alerts@example.com";
                smarthost = "localhost:25";
              }
            ];
          }
        ];
      };
    };
  };
}

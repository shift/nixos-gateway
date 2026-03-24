{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.gateway-dev-tools;
in
{
  options.services.gateway-dev-tools = {
    enable = lib.mkEnableOption "NixOS Gateway Development Tools";

    monitoring = {
      enable = lib.mkEnableOption "Monitoring Stack (Loki, Grafana, Promtail)";
      grafanaPort = lib.mkOption {
        type = lib.types.port;
        default = 3000;
        description = "Port for Grafana dashboard";
      };
      lokiPort = lib.mkOption {
        type = lib.types.port;
        default = 3100;
        description = "Port for Loki log aggregation";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Grafana Configuration
    services.grafana = lib.mkIf cfg.monitoring.enable {
      enable = true;
      settings = {
        server = {
          http_addr = "0.0.0.0";
          http_port = cfg.monitoring.grafanaPort;
        };
        "auth.anonymous" = {
          enable = true;
          org_role = "Admin";
        };
      };
      provision.datasources.settings.datasources = [
        {
          name = "Loki";
          type = "loki";
          access = "proxy";
          url = "http://127.0.0.1:${toString cfg.monitoring.lokiPort}";
        }
      ];
    };

    # Loki Configuration
    services.loki = lib.mkIf cfg.monitoring.enable {
      enable = true;
      configuration = {
        server.http_listen_port = cfg.monitoring.lokiPort;
        auth_enabled = false;
        ingester = {
          lifecycler = {
            address = "127.0.0.1";
            ring = {
              kvstore = {
                store = "inmemory";
              };
              replication_factor = 1;
            };
            final_sleep = "0s";
          };
          chunk_idle_period = "5m";
          chunk_retain_period = "30s";
        };
        schema_config = {
          configs = [
            {
              from = "2020-05-15";
              store = "tsdb";
              object_store = "filesystem";
              schema = "v13";
              index = {
                prefix = "index_";
                period = "24h";
              };
            }
          ];
        };
        storage_config = {
          tsdb_shipper = {
            active_index_directory = "/var/lib/loki/tsdb-index";
            cache_location = "/var/lib/loki/tsdb-cache";
            cache_ttl = "24h";
          };
          filesystem = {
            directory = "/var/lib/loki/chunks";
          };
        };
      };
    };

    # Promtail Configuration
    services.promtail = lib.mkIf cfg.monitoring.enable {
      enable = true;
      configuration = {
        server = {
          http_listen_port = 9080;
          grpc_listen_port = 0;
        };
        clients = [
          {
            url = "http://127.0.0.1:${toString cfg.monitoring.lokiPort}/loki/api/v1/push";
          }
        ];
        scrape_configs = [
          {
            job_name = "gateway_logs";
            static_configs = [
              {
                targets = [ "localhost" ];
                labels = {
                  job = "gateway-logs";
                  host = "localhost";
                  __path__ = "/var/lib/gateway/logs/*.log"; # Adjust path as needed
                };
              }
            ];
          }
        ];
      };
    };

    # Open firewall ports
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.monitoring.enable [
      cfg.monitoring.grafanaPort
      cfg.monitoring.lokiPort
    ];
  };
}

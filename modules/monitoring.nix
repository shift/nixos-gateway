{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.gateway;
  enabled = cfg.enable or true;
  hostsData = cfg.data.hosts or { staticDHCPv4Assignments = [ ]; };
  idsData = cfg.data.ids or { };

  monitoredHosts = builtins.filter (h: h ? prometheusPort) (hostsData.staticDHCPv4Assignments or [ ]);

  generateScrapeConfig = host: {
    job_name = "node_exporter_${host.name}";
    targets = [ "${host.ipAddress}:${toString host.prometheusPort}" ];
    scrape_interval = "30s";
    labels = {
      service = "node_exporter";
      group = host.type;
      hostname = host.name;
    };
  };

  remoteNodeExporters = map generateScrapeConfig monitoredHosts;
in
{
  options.services.gateway = {
    monitoring = {
      ports = lib.mkOption {
        type = lib.types.submodule {
          options = {
            prometheus = lib.mkOption {
              type = lib.types.port;
              default = 9090;
              description = "Port for Prometheus server";
            };
            nodeExporter = lib.mkOption {
              type = lib.types.port;
              default = 9100;
              description = "Port for Node Exporter";
            };
          };
        };
        default = { };
        description = "Monitoring service ports";
      };
    };
  };

  config = lib.mkMerge [
    {
      services.prometheus = {
        enable = true;
        port = cfg.monitoring.ports.prometheus;
        exporters = {
          node = {
            enable = true;
            port = cfg.monitoring.ports.nodeExporter;
            enabledCollectors = [
              "systemd"
              "textfile"
              "processes"
              "interrupts"
              "tcpstat"
              "netstat"
              "conntrack"
            ];
            extraFlags = [ "--collector.textfile.directory=/var/lib/prometheus-node-exporter-text-files" ];
          };
          systemd = {
            enable = true;
          };
        };
      };
      systemd.tmpfiles.rules = [
        "d /var/lib/prometheus-node-exporter-text-files 0775 node_exporter node_exporter -"
      ];
    }

  ];
}

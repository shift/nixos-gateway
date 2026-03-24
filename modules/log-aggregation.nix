{ config, lib, ... }:

with lib;

let
  cfg = config.services.logAggregation;
in

{
  options.services.logAggregation = {
    enable = mkEnableOption "Log aggregation framework";

    collector = {
      type = mkOption {
        type = types.enum [ "fluent-bit" "fluentd" "filebeat" ];
        default = "fluent-bit";
        description = "Log collector type";
      };

      inputs = mkOption {
        type = types.listOf types.attrs;
        default = [];
        description = "Log input configurations";
      };

      outputs = mkOption {
        type = types.listOf types.attrs;
        default = [];
        description = "Log output configurations";
      };

      filters = mkOption {
        type = types.listOf types.attrs;
        default = [];
        description = "Log filter configurations";
      };

      parsers = mkOption {
        type = types.attrsOf types.attrs;
        default = {};
        description = "Log parser configurations";
      };
    };

    retention = {
      policies = mkOption {
        type = types.attrsOf types.attrs;
        default = {};
        description = "Log retention policies";
      };

      cleanup = {
        schedule = mkOption {
          type = types.str;
          default = "daily";
          description = "Cleanup schedule";
        };

        batchSize = mkOption {
          type = types.int;
          default = 1000;
          description = "Cleanup batch size";
        };

        maxDiskUsage = mkOption {
          type = types.str;
          default = "80%";
          description = "Maximum disk usage before cleanup";
        };
      };
    };

    monitoring = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable log aggregation monitoring";
      };

      metrics = mkOption {
        type = types.attrsOf types.bool;
        default = {
          logVolume = true;
          errorRates = true;
          parsingErrors = true;
          bufferUtilization = true;
        };
        description = "Monitoring metrics to enable";
      };

      alerting = mkOption {
        type = types.attrsOf types.attrs;
        default = {};
        description = "Alerting configurations";
      };
    };

    search = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable log search capabilities";
      };

      indexes = mkOption {
        type = types.listOf types.attrs;
        default = [];
        description = "Search index configurations";
      };

      dashboards = mkOption {
        type = types.listOf types.attrs;
        default = [];
        description = "Dashboard configurations";
      };
    };
  };

  config = mkIf cfg.enable {
    # Fluent Bit service
    services.fluent-bit = mkIf (cfg.collector.type == "fluent-bit") {
      enable = true;

      settings = {
        service = {
          log_level = "info";
          parsers_file = "/etc/fluent-bit/parsers.conf";
        };

        inputs = cfg.collector.inputs;

        filters = cfg.collector.filters;

        outputs = cfg.collector.outputs;
      };
    };

    # Generate parsers configuration
    environment.etc."fluent-bit/parsers.conf" = mkIf (cfg.collector.type == "fluent-bit") {
      text = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: parser: ''
        [PARSER]
            Name        ${name}
            Format      ${parser.type or "regex"}
            Regex       ${parser.regex or ""}
            Time_Key    ${parser.timeKey or "timestamp"}
            Time_Format ${parser.timeFormat or "%Y-%m-%d %H:%M:%S"}
      '') cfg.collector.parsers);
    };

    # Log aggregation monitoring service
    systemd.services.log-aggregation-monitor = mkIf cfg.monitoring.enable {
      description = "Log Aggregation Monitoring";
      wantedBy = [ "multi-user.target" ];
      after = [ "fluent-bit.service" ];

      serviceConfig = {
        ExecStart = "${pkgs.callPackage ./log-aggregation-monitor.nix {
          inherit (cfg) monitoring;
        }}/bin/log-aggregation-monitor";
        Restart = "on-failure";
        User = "log-aggregation";
        Group = "log-aggregation";
      };
    };

    # Create log aggregation user and directories
    users.users.log-aggregation = {
      isSystemUser = true;
      group = "log-aggregation";
      home = "/var/lib/log-aggregation";
      createHome = true;
    };

    users.groups.log-aggregation = {};

    systemd.tmpfiles.rules = [
      "d /var/lib/log-aggregation 0750 log-aggregation log-aggregation -"
      "d /var/lib/log-aggregation/buffers 0750 log-aggregation log-aggregation -"
      "d /var/lib/log-aggregation/logs 0750 log-aggregation log-aggregation -"
    ];

    # Install required packages
    environment.systemPackages = with pkgs; [
      fluent-bit
      jq
      curl
    ];
  };
}

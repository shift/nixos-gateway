{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.gateway;
  ncpsCfg = cfg.ncps;
in
{
  options.services.gateway.ncps = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable NCPS Nix cache proxy server";
    };

    hostName = lib.mkOption {
      type = lib.types.str;
      example = "cache.example.com";
      description = "Hostname for the cache server";
    };

    dataPath = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/ncps";
      description = "Path for cache data storage";
    };

    tempPath = lib.mkOption {
      type = lib.types.str;
      default = "/var/cache/ncps/tmp";
      description = "Temporary storage path";
    };

    databaseURL = lib.mkOption {
      type = lib.types.str;
      default = "sqlite:/var/lib/ncps/db/db.sqlite";
      description = "Database URL for NCPS";
    };

    maxSize = lib.mkOption {
      type = lib.types.str;
      default = "20G";
      description = "Maximum cache size";
    };

    allowPutVerb = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Allow PUT verb for cache uploads";
    };

    allowDeleteVerb = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Allow DELETE verb for cache management";
    };

    serverAddr = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0:8501";
      description = "Server listen address and port";
    };

    upstreamCaches = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
        "https://cache.garnix.io"
      ];
      description = "List of upstream cache servers";
    };

    upstreamPublicKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
      ];
      description = "Public keys for upstream caches";
    };

    enableNginxProxy = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable nginx reverse proxy for HTTPS";
    };

    enablePrometheus = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Prometheus metrics";
    };
  };

  config = lib.mkIf (cfg.enable && ncpsCfg.enable) {
    services.ncps = {
      enable = true;

      cache = {
        hostName = ncpsCfg.hostName;
        dataPath = ncpsCfg.dataPath;
        tempPath = ncpsCfg.tempPath;
        databaseURL = ncpsCfg.databaseURL;
        maxSize = ncpsCfg.maxSize;

        allowPutVerb = ncpsCfg.allowPutVerb;
        allowDeleteVerb = ncpsCfg.allowDeleteVerb;
      };

      server = {
        addr = ncpsCfg.serverAddr;
      };

      upstream = {
        caches = ncpsCfg.upstreamCaches;
        publicKeys = ncpsCfg.upstreamPublicKeys;
      };
    };

    systemd.services.ncps.environment = lib.mkIf ncpsCfg.enablePrometheus {
      PROMETHEUS_ENABLED = "true";
    };

    networking.firewall.allowedTCPPorts = [ 8501 ] ++ lib.optional ncpsCfg.enableNginxProxy 443;

    services.nginx = lib.mkIf ncpsCfg.enableNginxProxy {
      enable = true;

      recommendedTlsSettings = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true;

      statusPage = true;

      virtualHosts."${ncpsCfg.hostName}" = {
        locations."/" = {
          proxyPass = "http://127.0.0.1:8501";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_buffering off;
            proxy_request_buffering off;
            client_max_body_size 0;
          '';
        };
      };
    };

    services.prometheus.exporters.nginx =
      lib.mkIf (ncpsCfg.enableNginxProxy && ncpsCfg.enablePrometheus)
        {
          enable = true;
          scrapeUri = "http://127.0.0.1/nginx_status";
        };
  };
}

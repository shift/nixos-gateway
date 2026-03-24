{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.gateway.cdn;
  inherit (lib)
    mkOption
    types
    mkIf
    mkEnableOption
    optionalAttrs
    mapAttrsToList
    concatStringsSep
    filter
    mapAttrs
    mkDefault
    ;

  # Import CDN library functions
  cdnLib = import ../lib/cdn { inherit lib pkgs; };

  # Validate CDN configuration
  validateConfig = cdnLib.validateConfig cfg;

  # Generate Nginx configuration for CDN edge nodes
  generateNginxConfig = cdnLib.nginx.generateConfig cfg;

  # Generate Varnish configuration for caching
  generateVarnishConfig = cdnLib.varnish.generateConfig cfg;

  # Generate CDN edge node configurations
  edgeNodeConfigs = mapAttrs (
    name: node:
    cdnLib.edgeNode.generateConfig name node cfg
  ) cfg.edgeNodes;

in
{
  options.services.gateway.cdn = {
    enable = mkEnableOption "Self-Hosted CDN Edge Caching";

    domain = mkOption {
      type = types.str;
      description = "Primary CDN domain name";
      example = "cdn.example.com";
    };

    origins = mkOption {
      type = types.listOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Origin server name";
          };
          host = mkOption {
            type = types.str;
            description = "Origin server hostname or IP";
          };
          port = mkOption {
            type = types.int;
            default = 80;
            description = "Origin server port";
          };
          tls = mkOption {
            type = types.bool;
            default = false;
            description = "Use HTTPS for origin connection";
          };
          healthCheck = mkOption {
            type = types.submodule {
              options = {
                path = mkOption {
                  type = types.str;
                  default = "/health";
                  description = "Health check path";
                };
                interval = mkOption {
                  type = types.str;
                  default = "30s";
                  description = "Health check interval";
                };
                timeout = mkOption {
                  type = types.str;
                  default = "5s";
                  description = "Health check timeout";
                };
                expectedStatus = mkOption {
                  type = types.int;
                  default = 200;
                  description = "Expected HTTP status code";
                };
              };
            };
            default = {};
            description = "Origin health check configuration";
          };
        };
      });
      default = [];
      description = "Origin server configurations";
      example = [
        {
          name = "primary";
          host = "origin.example.com";
          port = 443;
          tls = true;
          healthCheck = {
            path = "/health";
            interval = "30s";
            timeout = "5s";
          };
        }
      ];
    };

    edgeNodes = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          region = mkOption {
            type = types.str;
            description = "Geographic region for the edge node";
            example = "us-east";
          };
          location = mkOption {
            type = types.str;
            description = "Physical location of the edge node";
            example = "New York";
          };
          capacity = mkOption {
            type = types.int;
            default = 100;
            description = "Cache capacity in GB";
          };
          maxConnections = mkOption {
            type = types.int;
            default = 10000;
            description = "Maximum concurrent connections";
          };
          bandwidth = mkOption {
            type = types.str;
            default = "1Gbps";
            description = "Maximum bandwidth limit";
          };
          address = mkOption {
            type = types.str;
            description = "IP address for the edge node";
          };
        };
      });
      default = {};
      description = "Edge node configurations";
      example = {
        node1 = {
          region = "us-east";
          location = "New York";
          capacity = 100;
          address = "192.168.1.10";
        };
        node2 = {
          region = "eu-west";
          location = "London";
          capacity = 150;
          address = "192.168.1.11";
        };
      };
    };

    caching = mkOption {
      type = types.submodule {
        options = {
          defaultTtl = mkOption {
            type = types.str;
            default = "1h";
            description = "Default cache TTL";
          };
          maxTtl = mkOption {
            type = types.str;
            default = "24h";
            description = "Maximum cache TTL";
          };
          minTtl = mkOption {
            type = types.str;
            default = "1m";
            description = "Minimum cache TTL";
          };
          rules = mkOption {
            type = types.listOf (types.submodule {
              options = {
                path = mkOption {
                  type = types.str;
                  description = "Path pattern for cache rule";
                };
                ttl = mkOption {
                  type = types.str;
                  description = "Cache TTL for this rule";
                };
                compression = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Enable compression";
                };
                cacheByQuery = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Cache by query parameters";
                };
                vary = mkOption {
                  type = types.listOf types.str;
                  default = [];
                  description = "Cache variation headers";
                };
                bypass = mkOption {
                  type = types.bool;
                  default = false;
                  description = "Bypass cache for this rule";
                };
              };
            });
            default = [];
            description = "Cache rules";
          };
        };
      };
      default = {};
      description = "Caching configuration";
    };

    security = mkOption {
      type = types.submodule {
        options = {
          waf = mkOption {
            type = types.submodule {
              options = {
                enable = mkOption {
                  type = types.bool;
                  default = false;
                  description = "Enable Web Application Firewall";
                };
                rules = mkOption {
                  type = types.listOf types.str;
                  default = [];
                  description = "WAF rule sets";
                };
                mode = mkOption {
                  type = types.enum [ "detect" "prevent" ];
                  default = "detect";
                  description = "WAF operation mode";
                };
              };
            };
            default = {};
            description = "Web Application Firewall configuration";
          };
          rateLimit = mkOption {
            type = types.submodule {
              options = {
                requests = mkOption {
                  type = types.int;
                  default = 1000;
                  description = "Maximum requests per window";
                };
                window = mkOption {
                  type = types.str;
                  default = "1m";
                  description = "Rate limiting window";
                };
                burst = mkOption {
                  type = types.int;
                  default = 2000;
                  description = "Maximum burst size";
                };
              };
            };
            default = {};
            description = "Rate limiting configuration";
          };
          geoBlock = mkOption {
            type = types.submodule {
              options = {
                allow = mkOption {
                  type = types.listOf types.str;
                  default = [];
                  description = "Allowed country codes";
                };
                deny = mkOption {
                  type = types.listOf types.str;
                  default = [];
                  description = "Denied country codes";
                };
              };
            };
            default = {};
            description = "Geographic access restrictions";
          };
        };
      };
      default = {};
      description = "Security configuration";
    };

    optimization = mkOption {
      type = types.submodule {
        options = {
          imageOptimization = mkOption {
            type = types.bool;
            default = true;
            description = "Enable automatic image optimization";
          };
          compression = mkOption {
            type = types.submodule {
              options = {
                brotli = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Enable Brotli compression";
                };
                gzip = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Enable Gzip compression";
                };
                level = mkOption {
                  type = types.int;
                  default = 6;
                  description = "Compression level (1-9)";
                };
              };
            };
            default = {};
            description = "Compression settings";
          };
          httpVersion = mkOption {
            type = types.enum [ "h1" "h2" "h3" ];
            default = "h2";
            description = "Preferred HTTP version";
          };
          tlsVersion = mkOption {
            type = types.str;
            default = "TLSv1.3";
            description = "Preferred TLS version";
          };
        };
      };
      default = {};
      description = "Content optimization settings";
    };

    monitoring = mkOption {
      type = types.submodule {
        options = {
          prometheus = mkOption {
            type = types.submodule {
              options = {
                enable = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Enable Prometheus metrics";
                };
                port = mkOption {
                  type = types.int;
                  default = 9090;
                  description = "Prometheus metrics port";
                };
                path = mkOption {
                  type = types.str;
                  default = "/metrics";
                  description = "Metrics endpoint path";
                };
              };
            };
            default = {};
            description = "Prometheus monitoring configuration";
          };
          logging = mkOption {
            type = types.submodule {
              options = {
                level = mkOption {
                  type = types.enum [ "debug" "info" "warn" "error" ];
                  default = "info";
                  description = "Log level";
                };
                format = mkOption {
                  type = types.enum [ "text" "json" ];
                  default = "json";
                  description = "Log format";
                };
                access = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Enable access logging";
                };
              };
            };
            default = {};
            description = "Logging configuration";
          };
        };
      };
      default = {};
      description = "Monitoring and logging configuration";
    };

    api = mkOption {
      type = types.submodule {
        options = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Enable CDN management API";
          };
          port = mkOption {
            type = types.int;
            default = 8080;
            description = "API service port";
          };
          authToken = mkOption {
            type = types.str;
            description = "Authentication token for API access";
          };
          webhooks = mkOption {
            type = types.listOf (types.submodule {
              options = {
                url = mkOption {
                  type = types.str;
                  description = "Webhook URL";
                };
                events = mkOption {
                  type = types.listOf types.str;
                  description = "Events to trigger webhook";
                };
                secret = mkOption {
                  type = types.str;
                  description = "Webhook secret";
                };
              };
            });
            default = [];
            description = "Webhook configurations";
          };
        };
      };
      default = {};
      description = "API and webhook configuration";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.origins != [];
        message = "CDN requires at least one origin server";
      }
      {
        assertion = cfg.edgeNodes != {};
        message = "CDN requires at least one edge node";
      }
    ];

    # Main CDN Nginx configuration
    services.nginx = {
      enable = true;
      package = pkgs.nginxMainline;

      # Virtual hosts for CDN domains
      virtualHosts = {
        "${cfg.domain}" = {
          enableACME = true;
          forceSSL = true;
          
          serverName = cfg.domain;
          
          locations = {
            "/" = {
              proxyPass = "http://varnish_backend";
              extraConfig = ''
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto $scheme;
                proxy_set_header X-CDN-Edge $server_addr;
                
                # Security headers
                add_header X-Content-Type-Options nosniff;
                add_header X-Frame-Options DENY;
                add_header X-XSS-Protection "1; mode=block";
                add_header Strict-Transport-Security "max-age=31536000; includeSubDomains";
                
                # CDN headers
                add_header X-Cache-Status $upstream_cache_status;
                add_header X-Cache-TTL $upstream_response_time;
              '';
            };

            "/metrics" = mkIf cfg.monitoring.prometheus.enable {
              proxyPass = "http://127.0.0.1:${toString cfg.monitoring.prometheus.port}${cfg.monitoring.prometheus.path}";
            };
          };

          extraConfig = ''
            # Rate limiting
            limit_req_zone $binary_remote_addr zone=cdn_limit:10m rate=${toString cfg.security.rateLimit.requests}r/${cfg.security.rateLimit.window};
            limit_req zone=cdn_limit burst=${toString cfg.security.rateLimit.burst} nodelay;
            
            # Geographic blocking
            ${lib.optionalString (cfg.security.geoBlock.allow != []) ''
              if ($geoip_country_code !~ ^(${concatStringsSep "|" cfg.security.geoBlock.allow})$) {
                return 403;
              }
            ''}
            
            ${lib.optionalString (cfg.security.geoBlock.deny != []) ''
              if ($geoip_country_code ~ ^(${concatStringsSep "|" cfg.security.geoBlock.deny})$) {
                return 403;
              }
            ''}
          '';
        };
      };

      # Upstream configuration for Varnish
      upstreams = {
        varnish_backend = {
          servers = {
            "127.0.0.1:${toString cfg.varnish.port}" = {};
          };
        };
      };

      # Extra configuration for HTTP versions and optimization
      appendHttpConfig = ''
        # HTTP/2 and HTTP/3 support
        ${lib.optionalString (cfg.optimization.httpVersion == "h2") ''
          listen 443 ssl http2;
        ''}
        
        ${lib.optionalString (cfg.optimization.httpVersion == "h3") ''
          listen 443 ssl http3;
        ''}
        
        # TLS configuration
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_prefer_server_ciphers off;
        ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
        ssl_session_cache shared:SSL:10m;
        ssl_session_timeout 1d;
        
        # Compression
        ${lib.optionalString cfg.optimization.compression.gzip ''
          gzip on;
          gzip_comp_level ${toString cfg.optimization.compression.level};
          gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;
        ''}
        
        ${lib.optionalString cfg.optimization.compression.brotli ''
          brotli on;
          brotli_comp_level ${toString cfg.optimization.compression.level};
          brotli_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;
        ''}
        
        # Image optimization
        ${lib.optionalString cfg.optimization.imageOptimization ''
          # WebP support
          map $http_accept $webp_suffix {
            default   "";
            "~*webp"  ".webp";
          }
        ''}
      '';
    };

    # Varnish cache configuration
    services.varnish = {
      enable = true;
      config = generateVarnishConfig;
      httpAddress = "127.0.0.1";
      httpPort = cfg.varnish.port;
      storageFile = "/var/lib/varnish/cdn_storage.bin";
      storageSize = "${toString cfg.varnish.storageSize}G";
    };

    # CDN management API service
    systemd.services.cdn-api = mkIf cfg.api.enable {
      description = "CDN Management API Service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.python3}/bin/python3 ${cdnLib.api.generateScript cfg}";
        Restart = "on-failure";
        RestartSec = "5s";
        User = "cdn";
        Group = "cdn";
        Environment = [
          "CDN_CONFIG_FILE=/etc/cdn/config.json"
          "CDN_API_PORT=${toString cfg.api.port}"
          "CDN_API_TOKEN=${cfg.api.authToken}"
        ];
      };
    };

    # Edge node health monitoring
    systemd.services.cdn-health-monitor = {
      description = "CDN Edge Node Health Monitor";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.python3}/bin/python3 ${cdnLib.health.generateMonitorScript cfg}";
        Restart = "on-failure";
        RestartSec = "10s";
        User = "cdn";
        Group = "cdn";
      };
    };

    # Cache warming service
    systemd.services.cdn-cache-warmer = {
      description = "CDN Cache Warming Service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.python3}/bin/python3 ${cdnLib.cache.generateWarmerScript cfg}";
        User = "cdn";
        Group = "cdn";
      };
    };

    # Cache invalidation service
    systemd.services.cdn-invalidation = {
      description = "CDN Cache Invalidation Service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.python3}/bin/python3 ${cdnLib.cache.generateInvalidationScript cfg}";
        Restart = "on-failure";
        RestartSec = "5s";
        User = "cdn";
        Group = "cdn";
      };
    };

    # Analytics collector service
    systemd.services.cdn-analytics = {
      description = "CDN Analytics Collector";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.python3}/bin/python3 ${cdnLib.analytics.generateCollectorScript cfg}";
        Restart = "on-failure";
        RestartSec = "10s";
        User = "cdn";
        Group = "cdn";
      };
    };

    # Users and groups
    users.users.cdn = {
      isSystemUser = true;
      group = "cdn";
      description = "CDN service user";
    };

    users.groups.cdn = {};

    # Configuration files
    environment.etc = {
      "cdn/config.json".text = builtins.toJSON {
        inherit (cfg) domain origins edgeNodes caching security optimization monitoring api;
      };

      "cdn/varnish.vcl".source = pkgs.writeText "varnish.vcl" generateVarnishConfig;

      "cdn/nginx-cdn.conf".source = pkgs.writeText "nginx-cdn.conf" generateNginxConfig;
    };

    # Prometheus metrics endpoint
    services.prometheus.exporters.nginx = mkIf cfg.monitoring.prometheus.enable {
      enable = true;
      port = cfg.monitoring.prometheus.port;
    };

    # Open required firewall ports
    networking.firewall.allowedTCPPorts = [
      80    # HTTP
      443   # HTTPS
      cfg.api.port
    ] ++ lib.optional cfg.monitoring.prometheus.enable cfg.monitoring.prometheus.port;

    # Ensure required packages are available
    environment.systemPackages = with pkgs; [
      nginx
      varnish
      python3
      geoip
      curl
      jq
    ];

    # Varnish configuration module
    varnish = {
      port = mkDefault 8080;
      storageSize = mkDefault 10;
    };
  };
}

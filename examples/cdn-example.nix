# CDN Example Configuration
# This example demonstrates how to configure a self-hosted CDN with edge caching

{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Import CDN libraries for advanced configuration
  cdnConfig = import ../lib/cdn-config.nix { inherit lib; };
  cdnGeo = import ../lib/cdn-geo.nix { inherit lib; };

in
{
  # Enable the CDN module
  services.gateway.cdn = {
    enable = true;
    domain = "cdn.example.com";

    # Origin servers (your application backends)
    origins = [
      {
        name = "primary-origin";
        host = "api.example.com";
        port = 443;
        tls = true;
        healthCheck = {
          path = "/health";
          interval = "30s";
          timeout = "5s";
        };
        weight = 5; # Higher weight for primary
      }
      {
        name = "secondary-origin";
        host = "api-backup.example.com";
        port = 443;
        tls = true;
        healthCheck = {
          path = "/health";
          interval = "30s";
          timeout = "5s";
        };
        weight = 1; # Lower weight for backup
      }
    ];

    # Edge nodes for global distribution
    edgeNodes = [
      {
        region = "us-east";
        location = "New York, NY";
        capacity = 200; # 200 GB cache
        publicIPs = [
          "203.0.113.10" # Anycast IP for US East
        ];
        privateIPs = [
          "10.0.1.10"
          "10.0.1.11"
        ];
      }
      {
        region = "eu-west";
        location = "London, UK";
        capacity = 150; # 150 GB cache
        publicIPs = [
          "203.0.113.20" # Anycast IP for EU West
        ];
        privateIPs = [
          "10.0.2.10"
          "10.0.2.11"
        ];
      }
      {
        region = "ap-southeast";
        location = "Singapore";
        capacity = 100; # 100 GB cache
        publicIPs = [
          "203.0.113.30" # Anycast IP for Asia Pacific
        ];
        privateIPs = [
          "10.0.3.10"
          "10.0.3.11"
        ];
      }
    ];

    # Caching configuration
    caching = {
      defaultTtl = "1h"; # Default cache time
      maxTtl = "24h"; # Maximum cache time
      rules = [
        # Static assets - cache for a week
        {
          path = "/static/*";
          ttl = "7d";
          compression = true;
          cacheByQuery = false;
        }
        # CSS and JS - cache for a day
        {
          path = "/assets/*.css";
          ttl = "1d";
          compression = true;
        }
        {
          path = "/assets/*.js";
          ttl = "1d";
          compression = true;
        }
        # Images - cache for a week
        {
          path = "/images/*";
          ttl = "7d";
          compression = true;
        }
        # API responses - cache for 5 minutes
        {
          path = "/api/v1/public/*";
          ttl = "5m";
          cacheByQuery = true; # Cache based on query params
          compression = true;
        }
        # Dynamic content - don't cache
        {
          path = "/api/v1/private/*";
          ttl = "0s"; # No caching
          cacheByQuery = false;
        }
      ];
    };

    # Security configuration
    security = {
      # Web Application Firewall
      waf = {
        enable = true;
        rules = [
          "OWASP-Core-Ruleset"
          "custom-rules"
        ];
      };

      # Rate limiting
      rateLimit = {
        requests = 1000; # 1000 requests per window
        window = "1m"; # per minute
        burst = 2000; # burst allowance
      };

      # Geographic access control
      geoBlock = {
        allow = [
          "US"
          "CA"
          "GB"
          "DE"
          "FR"
          "IT"
          "ES"
          "NL"
          "SE"
          "NO"
          "DK"
          "FI"
          "PL"
          "AT"
          "CH"
          "BE"
          "PT"
          "IE"
          "SG"
          "JP"
          "KR"
          "AU"
          "NZ"
          "HK"
          "TW"
          "IN"
          "TH"
          "MY"
          "ID"
          "PH"
        ];
        deny = [
          "CN" # Block China (example)
          "RU" # Block Russia (example)
        ];
      };
    };

    # Content optimization
    optimization = {
      imageOptimization = true; # Enable automatic image optimization
      compression = {
        brotli = true; # Enable Brotli compression
        gzip = true; # Enable Gzip compression
      };
      httpVersion = "h2"; # Use HTTP/2
    };

    # Monitoring and logging
    monitoring = {
      prometheus = {
        enable = true;
        port = 9090;
      };
      logging = {
        level = "info";
        format = "json"; # Structured logging
      };
    };

    # Cache invalidation API
    invalidation = {
      enable = true;
      port = 8080;
      authToken = "your-secure-invalidation-token-here";
    };
  };

  # Additional configuration for DNS integration
  services.gateway.dns = {
    enable = true;
    zones = {
      "example.com" = {
        records = [
          # CDN domain pointing to edge nodes
          "cdn IN CNAME cdn.example.com."
        ];
      };
    };
  };

  # Load balancing for origin servers
  services.gateway.loadBalancing = {
    enable = true;
    upstreams = {
      api_backends = {
        protocol = "http";
        algorithm = "least_conn";
        servers = [
          {
            address = "api1.example.com";
            port = 443;
            weight = 1;
          }
          {
            address = "api2.example.com";
            port = 443;
            weight = 1;
          }
        ];
      };
    };
    virtualServers = {
      api_lb = {
        port = 443;
        protocol = "http";
        upstream = "api_backends";
        domain = "api.example.com";
      };
    };
  };

  # SSL/TLS configuration
  security.acme = {
    acceptTerms = true;
    defaults.email = "admin@example.com";
  };

  services.nginx.virtualHosts."cdn.example.com" = {
    enableACME = true;
    forceSSL = true;
    # CDN configuration is handled by the cdn module
  };

  # Firewall configuration
  networking.firewall = {
    allowedTCPPorts = [
      80 # HTTP
      443 # HTTPS
      8080 # Cache invalidation API
      9090 # Prometheus metrics
    ];
  };

  # Monitoring with Grafana + Prometheus
  services.grafana = {
    enable = true;
    settings = {
      server.http_port = 3000;
      security.admin_password = "admin";
    };
  };

  services.prometheus = {
    enable = true;
    exporters.nginx = {
      enable = true;
      port = 9090;
    };
    scrapeConfigs = [
      {
        job_name = "cdn";
        static_configs = [
          {
            targets = [ "localhost:9090" ];
          }
        ];
      }
    ];
  };

  # Log aggregation
  services.gateway.logAggregation = {
    enable = true;
    inputs = [
      {
        name = "cdn_access";
        path = "/var/log/nginx/cdn.access.log";
        format = "json";
      }
      {
        name = "cdn_error";
        path = "/var/log/nginx/cdn.error.log";
        format = "text";
      }
    ];
  };

  # Backup configuration for CDN cache and configuration
  services.gateway.backup = {
    enable = true;
    paths = [
      "/var/cache/nginx/cdn"
      "/etc/gateway/cdn"
      "/var/log/nginx"
    ];
    schedule = "daily";
  };

  # Example systemd timer for cache warming
  systemd.timers.cdn-cache-warmer = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
    };
  };

  systemd.services.cdn-cache-warmer = {
    script = ''
      # Cache warming script
      # This would prefetch popular content into the CDN cache

      echo "Warming CDN cache..."

      # Example: warm static assets
      curl -s "http://localhost/static/main.css" > /dev/null
      curl -s "http://localhost/static/main.js" > /dev/null
      curl -s "http://localhost/images/logo.png" > /dev/null

      echo "Cache warming completed"
    '';
    serviceConfig = {
      Type = "oneshot";
      User = "nginx";
    };
  };

  # Example health monitoring
  services.gateway.healthMonitoring = {
    enable = true;
    checks = {
      cdn_origins = {
        type = "http";
        targets = [
          "https://api.example.com/health"
          "https://api-backup.example.com/health"
        ];
        interval = "30s";
        timeout = "5s";
      };
      cdn_edge_nodes = {
        type = "http";
        targets = [
          "http://203.0.113.10/health"
          "http://203.0.113.20/health"
          "http://203.0.113.30/health"
        ];
        interval = "60s";
        timeout = "10s";
      };
    };
  };
}

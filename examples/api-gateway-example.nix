# Example API Gateway Configuration
# This example demonstrates how to configure the self-hosted API gateway
# with various authentication, rate limiting, and routing features.

{
  config,
  pkgs,
  lib,
  ...
}:

{
  # Enable the API gateway service
  services.gateway.api-gateway = {
    enable = true;
    port = 8080;

    # TLS configuration (optional)
    tls = {
      enable = true;
      certificate = "/etc/ssl/certs/api-gateway.crt";
      key = "/etc/ssl/private/api-gateway.key";
    };

    # Define API routes
    routes = [
      # User management API
      {
        path = "/api/v1/users";
        methods = [
          "GET"
          "POST"
          "PUT"
          "DELETE"
        ];
        backend = "http://user-service.internal:3000";
        auth = {
          type = "oauth2";
          provider = "keycloak";
        };
        rateLimit = {
          requests = 100;
          window = "1m";
        };
      }

      # Product catalog API
      {
        path = "/api/v1/products";
        methods = [
          "GET"
          "POST"
        ];
        backend = "http://product-service.internal:4000";
        auth = {
          type = "apiKey";
        };
        rateLimit = {
          requests = 200;
          window = "1m";
        };
      }

      # Analytics API (read-only)
      {
        path = "/api/v1/analytics";
        methods = [ "GET" ];
        backend = "http://analytics-service.internal:5000";
        auth = {
          type = "jwt";
        };
        rateLimit = {
          requests = 50;
          window = "1m";
        };
      }

      # Public health check (no auth required)
      {
        path = "/health";
        backend = "http://health-service.internal:6000";
        rateLimit = {
          requests = 1000;
          window = "1m";
        };
      }
    ];

    # Authentication configuration
    authentication = {
      # OAuth2 providers
      oauth2 = {
        providers = {
          keycloak = {
            issuer = "https://auth.example.com/realms/api-gateway";
            clientId = "api-gateway-client";
            clientSecret = "your-client-secret-here";
            scopes = [
              "openid"
              "profile"
              "email"
            ];
          };

          google = {
            issuer = "https://accounts.google.com";
            clientId = "your-google-client-id";
            clientSecret = "your-google-client-secret";
            scopes = [
              "openid"
              "profile"
              "email"
            ];
          };
        };
      };

      # API key authentication
      apiKeys = {
        enable = true;
        database = "/var/lib/api-gateway/api-keys.db";
      };

      # JWT authentication
      jwt = {
        enable = true;
        secret = "your-jwt-secret-key";
      };
    };

    # Rate limiting configuration
    rateLimiting = {
      # Use Redis for distributed rate limiting
      redis = {
        host = "redis.internal";
        port = 6379;
        password = "redis-password"; # optional
        database = 1;
      };

      # Default rate limits
      defaultLimits = {
        requests = 100;
        window = "1m";
      };
    };

    # CORS configuration
    cors = {
      enable = true;
      allowedOrigins = [
        "https://app.example.com"
        "https://admin.example.com"
      ];
      allowedMethods = [
        "GET"
        "POST"
        "PUT"
        "DELETE"
        "OPTIONS"
        "PATCH"
      ];
      allowedHeaders = [
        "Content-Type"
        "Authorization"
        "X-API-Key"
        "X-Request-ID"
      ];
    };

    # Logging configuration
    logging = {
      enable = true;
      format = "json";
      level = "info";
    };

    # Monitoring configuration
    monitoring = {
      enable = true;
      metrics = true;
      healthChecks = true;
    };

    # Plugin configuration
    plugins = {
      rateLimiting = {
        enable = true;
        config = {
          redis = {
            host = "redis.internal";
            port = 6379;
          };
          limits = {
            requests = 100;
            window = "1m";
          };
        };
      };

      authentication = {
        enable = true;
        config = {
          type = "oauth2";
          providers = {
            keycloak = {
              issuer = "https://auth.example.com";
              client_id = "api-gateway";
              client_secret = "secret";
            };
          };
        };
      };

      cors = {
        enable = true;
        config = {
          allowedOrigins = [ "https://app.example.com" ];
          allowedMethods = [
            "GET"
            "POST"
            "PUT"
            "DELETE"
            "OPTIONS"
          ];
          allowedHeaders = [
            "Content-Type"
            "Authorization"
            "X-API-Key"
          ];
        };
      };

      logging = {
        enable = true;
        config = {
          format = "json";
          level = "info";
          fields = [
            "time"
            "remote_addr"
            "request"
            "status"
            "body_bytes_sent"
            "request_time"
          ];
        };
      };

      monitoring = {
        enable = true;
        config = {
          metrics = true;
          healthChecks = true;
          tracing = false;
        };
      };

      security = {
        enable = true;
        config = {
          requestFiltering = true;
          responseFiltering = false;
          threatProtection = true;
        };
      };
    };
  };

  # Additional services for the example

  # Redis for rate limiting
  services.redis.servers.api-gateway = {
    enable = true;
    port = 6379;
    bind = "127.0.0.1";
  };

  # Example backend services (using simple HTTP servers for demo)
  systemd.services.user-service = {
    description = "Example User Service";
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 -m http.server 3000";
      WorkingDirectory = "/tmp";
    };
  };

  systemd.services.product-service = {
    description = "Example Product Service";
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 -m http.server 4000";
      WorkingDirectory = "/tmp";
    };
  };

  # Firewall configuration
  networking.firewall.allowedTCPPorts = [
    8080 # API Gateway
    3000 # User service
    4000 # Product service
  ];

  # SSL certificate generation (for demo purposes)
  security.acme = {
    acceptTerms = true;
    defaults.email = "admin@example.com";
  };

  services.nginx.virtualHosts."api.example.com" = {
    enableACME = true;
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:8080";
      proxyWebsockets = true;
    };
  };
}

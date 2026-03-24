{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.gateway.api-gateway;
  enabled = cfg.enable or false;

  # Import API gateway libraries
  apiGatewayConfig = import ../lib/api-gateway-config.nix { inherit lib; };
  apiGatewayPlugins = import ../lib/api-gateway-plugins.nix { inherit lib; };

  # Validate configuration
  validatedRoutes = map apiGatewayConfig.validateRoute cfg.routes;
  validatedAuth = apiGatewayConfig.validateAuth cfg.authentication;

  # Merge with defaults
  finalConfig = lib.recursiveUpdate apiGatewayConfig.defaultConfig cfg;

  # Generate OpenResty configuration
  nginxConfig = apiGatewayConfig.generateNginxConfig finalConfig;

  # Generate Lua modules
  luaModules = apiGatewayConfig.generateLuaModules finalConfig;

  # Generate plugin modules
  pluginModules =
    apiGatewayPlugins.generatePluginModules
      cfg.plugins or apiGatewayPlugins.defaultPlugins;

  # Create OpenResty package with Lua modules
  openrestyWithModules = pkgs.openresty.override {
    modules = with pkgs.nginxModules; [
      lua
      develkit
      lua-resty-core
      lua-resty-lrucache
      lua-resty-jwt
      lua-resty-redis
      lua-resty-limit-traffic
    ];
  };

  # Create API gateway package
  apiGatewayPackage = pkgs.stdenv.mkDerivation {
    name = "api-gateway";
    version = "1.0.0";

    src = ./.;

    buildInputs = [ openrestyWithModules ];

    phases = [ "installPhase" ];

    installPhase = ''
      mkdir -p $out
      mkdir -p $out/lua
      mkdir -p $out/conf

      # Install Lua modules
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (name: content: ''
          echo '${content}' > $out/lua/${name}.lua
        '') luaModules
      )}

      # Install plugin modules
      mkdir -p $out/lua/plugins
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (name: content: ''
          echo '${content}' > $out/lua/plugins/${name}.lua
        '') pluginModules
      )}

      # Install nginx configuration
      echo '${nginxConfig}' > $out/conf/nginx.conf
    '';
  };

in
{
  options.services.gateway.api-gateway = {
    enable = lib.mkEnableOption "API Gateway service";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port for the API gateway to listen on";
    };

    tls = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable TLS/SSL for the API gateway";
      };

      certificate = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to SSL certificate file";
      };

      key = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to SSL private key file";
      };
    };

    routes = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            path = lib.mkOption {
              type = lib.types.str;
              description = "URL path pattern for the route";
            };

            methods = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [
                "GET"
                "POST"
                "PUT"
                "DELETE"
              ];
              description = "Allowed HTTP methods for this route";
            };

            backend = lib.mkOption {
              type = lib.types.str;
              description = "Backend service URL to proxy requests to";
            };

            auth = lib.mkOption {
              type = lib.types.nullOr (
                lib.types.submodule {
                  options = {
                    type = lib.mkOption {
                      type = lib.types.enum [
                        "oauth2"
                        "jwt"
                        "apiKey"
                        "basic"
                      ];
                      description = "Authentication type";
                    };

                    provider = lib.mkOption {
                      type = lib.types.nullOr lib.types.str;
                      default = null;
                      description = "OAuth2 provider name";
                    };
                  };
                }
              );
              default = null;
              description = "Authentication configuration for this route";
            };

            rateLimit = lib.mkOption {
              type = lib.types.nullOr (
                lib.types.submodule {
                  options = {
                    requests = lib.mkOption {
                      type = lib.types.int;
                      default = 100;
                      description = "Maximum requests per time window";
                    };

                    window = lib.mkOption {
                      type = lib.types.str;
                      default = "1m";
                      description = "Time window for rate limiting (e.g., '1m', '1h')";
                    };
                  };
                }
              );
              default = null;
              description = "Rate limiting configuration for this route";
            };

            plugins = lib.mkOption {
              type = lib.types.attrsOf lib.types.bool;
              default = { };
              description = "Enable/disable specific plugins for this route";
            };
          };
        }
      );
      default = [ ];
      description = "List of API routes to configure";
    };

    authentication = {
      oauth2 = {
        providers = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                issuer = lib.mkOption {
                  type = lib.types.str;
                  description = "OAuth2 issuer URL";
                };

                clientId = lib.mkOption {
                  type = lib.types.str;
                  description = "OAuth2 client ID";
                };

                clientSecret = lib.mkOption {
                  type = lib.types.str;
                  description = "OAuth2 client secret";
                };

                scopes = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [
                    "openid"
                    "profile"
                  ];
                  description = "OAuth2 scopes to request";
                };
              };
            }
          );
          default = { };
          description = "OAuth2 provider configurations";
        };
      };

      apiKeys = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable API key authentication";
        };

        database = lib.mkOption {
          type = lib.types.path;
          default = "/var/lib/api-gateway/keys.db";
          description = "Path to API keys database";
        };
      };

      jwt = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable JWT authentication";
        };

        secret = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "JWT signing secret";
        };
      };
    };

    rateLimiting = {
      redis = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.submodule {
            options = {
              host = lib.mkOption {
                type = lib.types.str;
                default = "localhost";
                description = "Redis host for distributed rate limiting";
              };

              port = lib.mkOption {
                type = lib.types.port;
                default = 6379;
                description = "Redis port";
              };

              password = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Redis password";
              };

              database = lib.mkOption {
                type = lib.types.int;
                default = 0;
                description = "Redis database number";
              };
            };
          }
        );
        default = null;
        description = "Redis configuration for distributed rate limiting";
      };

      defaultLimits = {
        requests = lib.mkOption {
          type = lib.types.int;
          default = 100;
          description = "Default maximum requests per time window";
        };

        window = lib.mkOption {
          type = lib.types.str;
          default = "1m";
          description = "Default time window for rate limiting";
        };
      };
    };

    cors = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable CORS support";
      };

      allowedOrigins = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "*" ];
        description = "Allowed CORS origins";
      };

      allowedMethods = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "GET"
          "POST"
          "PUT"
          "DELETE"
          "OPTIONS"
        ];
        description = "Allowed CORS methods";
      };

      allowedHeaders = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "Content-Type"
          "Authorization"
          "X-API-Key"
        ];
        description = "Allowed CORS headers";
      };
    };

    logging = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable request logging";
      };

      format = lib.mkOption {
        type = lib.types.enum [
          "json"
          "combined"
        ];
        default = "json";
        description = "Log format";
      };

      level = lib.mkOption {
        type = lib.types.enum [
          "debug"
          "info"
          "notice"
          "warn"
          "error"
        ];
        default = "info";
        description = "Log level";
      };
    };

    monitoring = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable monitoring and metrics";
      };

      metrics = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Prometheus metrics endpoint";
      };

      healthChecks = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable health check endpoint";
      };
    };

    plugins = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Enable this plugin";
            };

            config = lib.mkOption {
              type = lib.types.attrs;
              default = { };
              description = "Plugin-specific configuration";
            };
          };
        }
      );
      default = apiGatewayPlugins.defaultPlugins;
      description = "Plugin configurations";
    };
  };

  config = lib.mkIf enabled {
    # Install OpenResty with required modules
    services.nginx = {
      enable = true;
      package = openrestyWithModules;

      # Use our custom configuration
      configFile = "${apiGatewayPackage}/conf/nginx.conf";

      # Add Lua package path
      appendConfig = ''
        lua_package_path "${apiGatewayPackage}/lua/?.lua;;";
      '';
    };

    # Create necessary directories
    systemd.tmpfiles.rules = [
      "d /var/lib/api-gateway 0755 nginx nginx -"
      "d /var/log/api-gateway 0755 nginx nginx -"
    ];

    # Open firewall port
    networking.firewall.allowedTCPPorts = [ cfg.port ];

    # Integration with existing monitoring
    services.prometheus.exporters.nginx = lib.mkIf cfg.monitoring.enable {
      enable = true;
      nginxConfig = "${apiGatewayPackage}/conf/nginx.conf";
    };

    # Integration with existing logging
    services.gateway.log-aggregation = lib.mkIf cfg.logging.enable {
      enable = true;
      files = [ "/var/log/api-gateway/*.log" ];
    };

    # Health monitoring integration
    services.gateway.health-monitoring = lib.mkIf cfg.monitoring.healthChecks {
      enable = true;
      checks = [
        {
          name = "api-gateway";
          url = "http://localhost:${toString cfg.port}/health";
          interval = "30s";
        }
      ];
    };
  };
}

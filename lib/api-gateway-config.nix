{
  lib,
  ...
}:

let
  # Default API gateway configuration
  defaultConfig = {
    enable = false;
    port = 8080;
    tls = {
      enable = false;
      certificate = null;
      key = null;
    };
    routes = [ ];
    authentication = {
      oauth2 = {
        providers = { };
      };
      apiKeys = {
        enabled = false;
        database = "/var/lib/api-gateway/keys.db";
      };
      jwt = {
        enabled = false;
        secret = null;
      };
    };
    rateLimiting = {
      redis = null;
      defaultLimits = {
        requests = 100;
        window = "1m";
      };
    };
    cors = {
      enable = true;
      allowedOrigins = [ "*" ];
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
    logging = {
      enable = true;
      format = "json";
      level = "info";
    };
    monitoring = {
      enable = true;
      metrics = true;
      healthChecks = true;
    };
  };

  # Validate route configuration
  validateRoute =
    route:
    let
      requiredFields = [
        "path"
        "backend"
      ];
      hasRequired = lib.all (field: route ? ${field}) requiredFields;
    in
    if !hasRequired then
      throw "Route configuration missing required fields: ${lib.concatStringsSep ", " requiredFields}"
    else
      route;

  # Validate authentication configuration
  validateAuth =
    auth:
    if auth.oauth2.providers != { } then
      let
        providers = lib.attrValues auth.oauth2.providers;
        validateProvider =
          provider:
          if !(provider ? issuer && provider ? clientId && provider ? clientSecret) then
            throw "OAuth2 provider missing required fields: issuer, clientId, clientSecret"
          else
            provider;
      in
      lib.forEach providers validateProvider
    else
      auth;

  # Generate OpenResty configuration
  generateNginxConfig =
    cfg:
    let
      routesConfig = lib.concatStringsSep "\n" (
        map (route: ''
          location ${route.path} {
            ${lib.optionalString (route ? methods) ''
              if ($request_method !~ ^(${lib.concatStringsSep "|" route.methods})$) {
                return 405;
              }
            ''}

            ${lib.optionalString (route ? auth && route.auth.type == "oauth2") ''
              # OAuth2 authentication
              access_by_lua_block {
                local oauth = require("oauth2")
                oauth.authenticate("${route.auth.provider}")
              }
            ''}

            ${lib.optionalString (route ? auth && route.auth.type == "apiKey") ''
              # API Key authentication
              access_by_lua_block {
                local api_key = require("api_key")
                api_key.authenticate()
              }
            ''}

            ${lib.optionalString (route ? rateLimit) ''
              # Rate limiting
              limit_req zone=api_${route.path} burst=${toString (route.rateLimit.requests * 2)} nodelay;
            ''}

            proxy_pass ${route.backend};
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
          }
        '') cfg.routes
      );

      corsConfig = lib.optionalString cfg.cors.enable ''
        # CORS configuration
        location / {
          if ($request_method = 'OPTIONS') {
            add_header Access-Control-Allow-Origin "${lib.concatStringsSep ", " cfg.cors.allowedOrigins}";
            add_header Access-Control-Allow-Methods "${lib.concatStringsSep ", " cfg.cors.allowedMethods}";
            add_header Access-Control-Allow-Headers "${lib.concatStringsSep ", " cfg.cors.allowedHeaders}";
            add_header Access-Control-Max-Age 86400;
            return 204;
          }
        }
      '';

      rateLimitConfig = lib.optionalString (cfg.rateLimiting.redis != null) ''
        # Rate limiting zones
        limit_req_zone $binary_remote_addr zone=api_default:${
          toString (cfg.rateLimiting.defaultLimits.requests * 1024)
        } rate=${toString cfg.rateLimiting.defaultLimits.requests}r/${cfg.rateLimiting.defaultLimits.window};
      '';

      loggingConfig = lib.optionalString cfg.logging.enable ''
        # Logging configuration
        log_format ${cfg.logging.format} escape=json
          '{'
            '"time": "$time_iso8601",'
            '"remote_addr": "$remote_addr",'
            '"request": "$request",'
            '"status": "$status",'
            '"body_bytes_sent": "$body_bytes_sent",'
            '"http_referer": "$http_referer",'
            '"http_user_agent": "$http_user_agent",'
            '"request_time": "$request_time"'
          '}';

        access_log /var/log/api-gateway/access.log ${cfg.logging.format};
        error_log /var/log/api-gateway/error.log ${cfg.logging.level};
      '';

      monitoringConfig = lib.optionalString cfg.monitoring.enable ''
        # Health check endpoint
        location /health {
          access_log off;
          return 200 "healthy\n";
          add_header Content-Type text/plain;
        }

        ${lib.optionalString cfg.monitoring.metrics ''
          # Metrics endpoint
          location /metrics {
            access_log off;
            stub_status on;
            allow 127.0.0.1;
            deny all;
          }
        ''}
      '';
    in
    ''
      ${rateLimitConfig}

      upstream backend_default {
        server 127.0.0.1:8080;
        keepalive 32;
      }

      server {
        listen ${toString cfg.port} ${lib.optionalString cfg.tls.enable "ssl"};
        ${lib.optionalString cfg.tls.enable ''
          ssl_certificate ${cfg.tls.certificate};
          ssl_certificate_key ${cfg.tls.key};
        ''}

        ${loggingConfig}
        ${corsConfig}
        ${monitoringConfig}
        ${routesConfig}

        # Default location for unmatched routes
        location / {
          return 404;
        }
      }
    '';

  # Generate Lua authentication modules
  generateLuaModules =
    cfg:
    let
      oauth2Module = lib.optionalString (cfg.authentication.oauth2.providers != { }) ''
        local cjson = require "cjson"
        local jwt = require "resty.jwt"

        local _M = {}

        function _M.authenticate(provider_name)
          local provider = ngx.var.oauth2_providers[provider_name]
          if not provider then
            ngx.log(ngx.ERR, "Unknown OAuth2 provider: " .. provider_name)
            ngx.exit(ngx.HTTP_UNAUTHORIZED)
            return
          end

          local auth_header = ngx.var.http_authorization
          if not auth_header or not auth_header:match("^Bearer ") then
            ngx.exit(ngx.HTTP_UNAUTHORIZED)
            return
          end

          local token = auth_header:sub(8)
          local jwt_obj = jwt:verify(provider.client_secret, token)

          if not jwt_obj.verified then
            ngx.log(ngx.ERR, "JWT verification failed")
            ngx.exit(ngx.HTTP_UNAUTHORIZED)
            return
          end

          -- Set user context
          ngx.ctx.user = jwt_obj.payload
        end

        return _M
      '';

      apiKeyModule = lib.optionalString cfg.authentication.apiKeys.enabled ''
        local _M = {}

        function _M.authenticate()
          local api_key = ngx.var.http_x_api_key
          if not api_key then
            ngx.exit(ngx.HTTP_UNAUTHORIZED)
            return
          end

          -- TODO: Implement API key validation against database
          -- For now, accept any key
          ngx.ctx.api_key = api_key
        end

        return _M
      '';
    in
    {
      oauth2 = oauth2Module;
      api_key = apiKeyModule;
    };

in
{
  inherit
    defaultConfig
    validateRoute
    validateAuth
    generateNginxConfig
    generateLuaModules
    ;
}

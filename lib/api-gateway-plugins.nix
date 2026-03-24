{
  lib,
  ...
}:

let
  # Plugin system for API gateway extensions
  defaultPlugins = {
    rateLimiting = {
      enable = true;
      config = {
        redis = null;
        limits = {
          requests = 100;
          window = "1m";
        };
      };
    };

    authentication = {
      enable = true;
      config = {
        type = "none"; # none, basic, oauth2, jwt, apiKey
        providers = { };
      };
    };

    cors = {
      enable = true;
      config = {
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

    transformation = {
      enable = false;
      config = {
        requestTransform = null;
        responseTransform = null;
      };
    };
  };

  # Plugin execution order
  pluginOrder = [
    "security"
    "authentication"
    "rateLimiting"
    "cors"
    "transformation"
    "logging"
    "monitoring"
  ];

  # Validate plugin configuration
  validatePlugin =
    name: plugin:
    let
      requiredFields = [
        "enable"
        "config"
      ];
      hasRequired = lib.all (field: plugin ? ${field}) requiredFields;
    in
    if !hasRequired then
      throw "Plugin ${name} missing required fields: ${lib.concatStringsSep ", " requiredFields}"
    else
      plugin;

  # Generate plugin chain for route
  generatePluginChain =
    route: plugins:
    let
      enabledPlugins = lib.filterAttrs (_: p: p.enable) plugins;
      orderedPlugins = lib.mapAttrsToList (name: plugin: {
        inherit name plugin;
      }) enabledPlugins;

      sortedPlugins = lib.sort (
        a: b:
        let
          aIndex = lib.findFirstIndex (x: x == a.name) 999 pluginOrder;
          bIndex = lib.findFirstIndex (x: x == b.name) 999 pluginOrder;
        in
        aIndex < bIndex
      ) orderedPlugins;

      generatePluginCode =
        pluginData:
        let
          name = pluginData.name;
          plugin = pluginData.plugin;
        in
        if name == "rateLimiting" then
          lib.optionalString plugin.enable ''
            -- Rate limiting plugin
            local rate_limit = require("plugins.rate_limiting")
            rate_limit.check(${lib.generators.toLua plugin.config})
          ''
        else if name == "authentication" then
          lib.optionalString plugin.enable ''
            -- Authentication plugin
            local auth = require("plugins.authentication")
            auth.authenticate(${lib.generators.toLua plugin.config})
          ''
        else if name == "cors" then
          lib.optionalString plugin.enable ''
            -- CORS plugin
            local cors = require("plugins.cors")
            cors.handle(${lib.generators.toLua plugin.config})
          ''
        else if name == "logging" then
          lib.optionalString plugin.enable ''
            -- Logging plugin
            local logging = require("plugins.logging")
            logging.log(${lib.generators.toLua plugin.config})
          ''
        else if name == "monitoring" then
          lib.optionalString plugin.enable ''
            -- Monitoring plugin
            local monitoring = require("plugins.monitoring")
            monitoring.track(${lib.generators.toLua plugin.config})
          ''
        else if name == "security" then
          lib.optionalString plugin.enable ''
            -- Security plugin
            local security = require("plugins.security")
            security.filter(${lib.generators.toLua plugin.config})
          ''
        else if name == "transformation" then
          lib.optionalString plugin.enable ''
            -- Transformation plugin
            local transformation = require("plugins.transformation")
            transformation.apply(${lib.generators.toLua plugin.config})
          ''
        else
          "";
    in
    lib.concatStringsSep "\n" (map generatePluginCode sortedPlugins);

  # Generate Lua plugin modules
  generatePluginModules =
    plugins:
    let
      rateLimitingModule = ''
        local _M = {}

        function _M.check(config)
          if config.redis then
            -- Redis-based rate limiting
            local redis = require "resty.redis"
            local red = redis:new()
            red:set_timeout(1000)
            local ok, err = red:connect(config.redis.host, config.redis.port)
            if not ok then
              ngx.log(ngx.ERR, "failed to connect to redis: ", err)
              return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
            end

            local key = ngx.var.binary_remote_addr
            local limit = config.limits.requests
            local window = config.limits.window

            local current = red:get(key)
            if current and tonumber(current) >= limit then
              return ngx.exit(ngx.HTTP_TOO_MANY_REQUESTS)
            end

            red:incr(key)
            red:expire(key, 60) -- 1 minute window
          else
            -- Local rate limiting using shared dict
            local limit_req = require "resty.limit.req"
            local lim, err = limit_req.new("api_limit", config.limits.requests, config.limits.requests)
            if not lim then
              ngx.log(ngx.ERR, "failed to instantiate a resty.limit.req object: ", err)
              return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
            end

            local delay, err = lim:incoming(ngx.var.binary_remote_addr, true)
            if not delay then
              if err == "rejected" then
                return ngx.exit(ngx.HTTP_TOO_MANY_REQUESTS)
              end
              ngx.log(ngx.ERR, "failed to limit req: ", err)
              return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
            end
          end
        end

        return _M
      '';

      authenticationModule = ''
        local _M = {}

        function _M.authenticate(config)
          if config.type == "oauth2" then
            local oauth2 = require("oauth2")
            oauth2.authenticate(config.providers)
          elseif config.type == "jwt" then
            local jwt = require("resty.jwt")
            local auth_header = ngx.var.http_authorization
            if not auth_header or not auth_header:match("^Bearer ") then
              return ngx.exit(ngx.HTTP_UNAUTHORIZED)
            end

            local token = auth_header:sub(8)
            local jwt_obj = jwt:verify(config.secret, token)

            if not jwt_obj.verified then
              return ngx.exit(ngx.HTTP_UNAUTHORIZED)
            end

            ngx.ctx.user = jwt_obj.payload
          elseif config.type == "apiKey" then
            local api_key = require("api_key")
            api_key.authenticate()
          elseif config.type == "basic" then
            -- Basic auth implementation
            local auth_header = ngx.var.http_authorization
            if not auth_header or not auth_header:match("^Basic ") then
              ngx.header["WWW-Authenticate"] = 'Basic realm="API Gateway"'
              return ngx.exit(ngx.HTTP_UNAUTHORIZED)
            end

            -- Decode and validate credentials
            local credentials = ngx.decode_base64(auth_header:sub(7))
            local username, password = credentials:match("([^:]+):(.+)")

            -- TODO: Validate against user database
            if not (username and password) then
              return ngx.exit(ngx.HTTP_UNAUTHORIZED)
            end
          end
        end

        return _M
      '';

      corsModule = ''
        local _M = {}

        function _M.handle(config)
          if ngx.var.request_method == "OPTIONS" then
            ngx.header["Access-Control-Allow-Origin"] = table.concat(config.allowedOrigins, ", ")
            ngx.header["Access-Control-Allow-Methods"] = table.concat(config.allowedMethods, ", ")
            ngx.header["Access-Control-Allow-Headers"] = table.concat(config.allowedHeaders, ", ")
            ngx.header["Access-Control-Max-Age"] = "86400"
            ngx.exit(ngx.HTTP_NO_CONTENT)
          end

          -- Set CORS headers for actual requests
          ngx.header["Access-Control-Allow-Origin"] = table.concat(config.allowedOrigins, ", ")
          ngx.header["Access-Control-Allow-Headers"] = table.concat(config.allowedHeaders, ", ")
        end

        return _M
      '';

      loggingModule = ''
        local _M = {}

        function _M.log(config)
          local log_entry = {}

          for _, field in ipairs(config.fields) do
            if field == "time" then
              log_entry.time = ngx.time()
            elseif field == "remote_addr" then
              log_entry.remote_addr = ngx.var.remote_addr
            elseif field == "request" then
              log_entry.request = ngx.var.request
            elseif field == "status" then
              log_entry.status = ngx.var.status
            elseif field == "body_bytes_sent" then
              log_entry.body_bytes_sent = ngx.var.body_bytes_sent
            elseif field == "request_time" then
              log_entry.request_time = ngx.var.request_time
            end
          end

          -- Write to log file
          local cjson = require "cjson"
          ngx.log(ngx.NOTICE, cjson.encode(log_entry))
        end

        return _M
      '';

      monitoringModule = ''
        local _M = {}

        function _M.track(config)
          if config.metrics then
            -- Increment request counter
            local metrics = ngx.shared.metrics
            if metrics then
              metrics:incr("requests_total", 1, 0)
              metrics:incr("requests_" .. ngx.var.status, 1, 0)
            end
          end

          if config.tracing then
            -- Add tracing headers
            ngx.header["X-Request-ID"] = ngx.var.request_id or ngx.md5(ngx.var.remote_addr .. ngx.time())
          end
        end

        return _M
      '';

      securityModule = ''
        local _M = {}

        function _M.filter(config)
          if config.requestFiltering then
            -- Basic security checks
            local uri = ngx.var.request_uri

            -- SQL injection patterns
            if uri:match("[';]\\s*(\\b(select|union|insert|update|delete|drop|create|alter)\\b)") then
              return ngx.exit(ngx.HTTP_FORBIDDEN)
            end

            -- XSS patterns
            if uri:match("<script") or uri:match("javascript:") then
              return ngx.exit(ngx.HTTP_FORBIDDEN)
            end
          end

          if config.threatProtection then
            -- Additional threat protection logic
            local user_agent = ngx.var.http_user_agent or ""
            if user_agent:match("sqlmap") or user_agent:match("nmap") then
              return ngx.exit(ngx.HTTP_FORBIDDEN)
            end
          end
        end

        return _M
      '';

      transformationModule = ''
        local _M = {}

        function _M.apply(config)
          if config.requestTransform then
            -- Request transformation logic
            -- TODO: Implement request body/header transformation
          end

          if config.responseTransform then
            -- Response transformation logic
            -- TODO: Implement response body/header transformation
          end
        end

        return _M
      '';
    in
    {
      rate_limiting = rateLimitingModule;
      authentication = authenticationModule;
      cors = corsModule;
      logging = loggingModule;
      monitoring = monitoringModule;
      security = securityModule;
      transformation = transformationModule;
    };

in
{
  inherit
    defaultPlugins
    pluginOrder
    validatePlugin
    generatePluginChain
    generatePluginModules
    ;
}

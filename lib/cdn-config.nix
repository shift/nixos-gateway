# CDN Configuration Library
# Provides utilities for CDN configuration validation, generation, and management

{ lib, ... }:

let
  inherit (lib) types mkOption;

  # Validate CDN configuration
  validateCDNConfig =
    config:
    let
      # Check origins
      originValidation = lib.all (
        origin: origin.name != "" && origin.host != "" && origin.port > 0 && origin.port <= 65535
      ) config.origins;

      # Check edge nodes
      edgeNodeValidation = lib.all (
        node: node.region != "" && node.location != "" && node.capacity > 0
      ) config.edgeNodes;

      # Check caching rules
      cacheRuleValidation = lib.all (rule: rule.path != "" && rule.ttl != "") config.caching.rules;

      # Check domain
      domainValidation =
        config.domain != ""
        && lib.hasSuffix ".${lib.last (lib.splitString "." config.domain)}" config.domain;

    in
    {
      valid = originValidation && edgeNodeValidation && cacheRuleValidation && domainValidation;
      errors = lib.flatten [
        (if !originValidation then [ "Invalid origin configuration" ] else [ ])
        (if !edgeNodeValidation then [ "Invalid edge node configuration" ] else [ ])
        (if !cacheRuleValidation then [ "Invalid caching rules" ] else [ ])
        (if !domainValidation then [ "Invalid domain name" ] else [ ])
      ];
    };

  # Generate NGINX upstream configuration
  generateUpstreamConfig =
    origins:
    lib.concatStringsSep "\n" (
      map (origin: ''
        upstream ${origin.name} {
          ${
            if origin.tls then
              "server ${origin.host}:${toString origin.port} resolve;"
            else
              "server ${origin.host}:${toString origin.port};"
          }
          keepalive 32;
        }
      '') origins
    );

  # Generate cache configuration
  generateCacheConfig =
    caching:
    let
      defaultRules = [
        {
          path = "/static/*";
          ttl = "7d";
          compression = true;
        }
        {
          path = "/assets/*";
          ttl = "1d";
          compression = true;
        }
        {
          path = "/api/*";
          ttl = "5m";
          compression = false;
        }
      ];
      allRules = caching.rules ++ defaultRules;
    in
    ''
      # Cache zones
      proxy_cache_path /var/cache/nginx/cdn levels=1:2 keys_zone=cdn_cache:10m max_size=10g inactive=60m use_temp_path=off;

      # Default cache settings
      proxy_cache cdn_cache;
      proxy_cache_key $scheme$request_method$host$request_uri;
      proxy_cache_valid 200 302 ${caching.defaultTtl};
      proxy_cache_valid 404 1m;
      proxy_cache_use_stale error timeout invalid_header updating http_500 http_502 http_503 http_504;

      # Custom cache rules
      ${lib.concatStringsSep "\n" (
        map (rule: ''
          location ~ ${rule.path} {
            proxy_cache_valid 200 302 ${rule.ttl};
            ${if !rule.cacheByQuery then "proxy_cache_key $scheme$request_method$host$uri;" else ""}
            ${if !rule.compression then "gzip off; brotli off;" else ""}
          }
        '') allRules
      )}
    '';

  # Generate security configuration
  generateSecurityConfig =
    security:
    let
      rateLimitConfig =
        if security.rateLimit != { } then
          ''
            limit_req_zone $binary_remote_addr zone=cdn_req:10m rate=${toString security.rateLimit.requests}r/${security.rateLimit.window};
            limit_req_zone $binary_remote_addr zone=cdn_burst:10m rate=${
              toString (security.rateLimit.requests * 2)
            }r/${security.rateLimit.window};
            limit_req zone=cdn_req burst=${toString security.rateLimit.burst} nodelay;
          ''
        else
          "";

      geoBlockConfig =
        if security.geoBlock != { } then
          ''
            map $geoip2_data_country_code $allowed_country {
              default no;
              ${lib.concatStringsSep "\n  " (map (code: "${code} yes;") security.geoBlock.allow)}
            }

            map $geoip2_data_country_code $blocked_country {
              default no;
              ${lib.concatStringsSep "\n  " (map (code: "${code} yes;") security.geoBlock.deny)}
            }
          ''
        else
          "";

      wafConfig =
        if security.waf.enable then
          ''
            # WAF rules would be implemented here
            # This is a placeholder for actual WAF integration
          ''
        else
          "";
    in
    rateLimitConfig + geoBlockConfig + wafConfig;

  # Generate optimization configuration
  generateOptimizationConfig = optimization: ''
    # Compression settings
    ${
      if optimization.compression.brotli then
        ''
          brotli on;
          brotli_comp_level 6;
          brotli_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;
        ''
      else
        ""
    }

    ${
      if optimization.compression.gzip then
        ''
          gzip on;
          gzip_vary on;
          gzip_min_length 1024;
          gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;
        ''
      else
        ""
    }

    # HTTP version
    ${if optimization.httpVersion == "h3" then "http3 on;" else "http2 on;"}

    # Image optimization (placeholder)
    ${if optimization.imageOptimization then "# Image optimization would be implemented here" else ""}
  '';

  # Generate monitoring configuration
  generateMonitoringConfig = monitoring: ''
    # Logging configuration
    ${
      if monitoring.logging.format == "json" then
        ''
          log_format cdn_json escape=json '{'
            '"time":"$time_iso8601",'
            '"remote_addr":"$remote_addr",'
            '"request":"$request",'
            '"status":$status,'
            '"body_bytes_sent":$body_bytes_sent,'
            '"request_time":$request_time,'
            '"upstream_response_time":"$upstream_response_time",'
            '"cache_status":"$upstream_cache_status"'
          '}';
          access_log /var/log/nginx/cdn.access.log cdn_json;
        ''
      else
        ''
          access_log /var/log/nginx/cdn.access.log;
        ''
    }

    error_log /var/log/nginx/cdn.error.log ${monitoring.logging.level};

    # Prometheus metrics (if enabled)
    ${
      if monitoring.prometheus.enable then
        ''
          location /metrics {
            stub_status on;
            access_log off;
            allow 127.0.0.1;
            deny all;
          }
        ''
      else
        ""
    }
  '';

  # Calculate cache hit rate (utility function)
  calculateCacheHitRate =
    stats: if stats.totalRequests == 0 then 0.0 else (stats.cacheHits * 100.0) / stats.totalRequests;

  # Generate cache invalidation script
  generateInvalidationScript = config: ''
    #!/bin/bash
    # CDN Cache Invalidation Script

    set -e

    # Configuration
    CDN_DOMAIN="${config.domain}"
    INVALIDATION_PORT="${toString config.invalidation.port}"
    AUTH_TOKEN="${config.invalidation.authToken}"

    # Function to purge a single URL
    purge_url() {
      local url="$1"
      curl -X PURGE \
        -H "Authorization: Bearer $AUTH_TOKEN" \
        -H "Host: $CDN_DOMAIN" \
        "http://localhost:$INVALIDATION_PORT$url" \
        --max-time 10 \
        --silent \
        --show-error
    }

    # Function to purge by pattern
    purge_pattern() {
      local pattern="$1"
      # This would need more sophisticated implementation
      echo "Pattern purging not yet implemented for: $pattern"
    }

    # Main logic
    case "$1" in
      url)
        purge_url "$2"
        ;;
      pattern)
        purge_pattern "$2"
        ;;
      all)
        # Purge all cache
        nginx -s reload
        ;;
      *)
        echo "Usage: $0 {url <url>|pattern <pattern>|all}"
        exit 1
        ;;
    esac
  '';

in
{
  # Public API
  inherit
    validateCDNConfig
    generateUpstreamConfig
    generateCacheConfig
    generateSecurityConfig
    generateOptimizationConfig
    generateMonitoringConfig
    calculateCacheHitRate
    generateInvalidationScript
    ;
}

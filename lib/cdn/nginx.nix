{ lib, pkgs }:

let
  inherit (lib)
    concatStringsSep
    optionalString
    mapAttrsToList
    ;

in {
  generateConfig = cfg: 
    let
      # Origin server configurations
      originBackends = concatStringsSep "\n    " (mapAttrsToList (name: origin: ''
      server ${origin.host}:${toString origin.port} {
        keepalive 32;
        ${optionalString origin.tls "ssl_verify off;"}
        health_check interval=${origin.healthCheck.interval} timeout=${origin.healthCheck.timeout} status=${toString origin.healthCheck.expectedStatus};
      }
    '') (lib.listToAttrs (map (o: { name = o.name; value = o; }) cfg.origins)));

      # Cache rule configurations
      cacheRules = concatStringsSep "\n      " (map (rule: ''
      if ($request_uri ~* "^${rule.path}$") {
        set $cache_ttl ${rule.ttl};
        set $cache_compression ${if rule.compression then "on" else "off"};
        set $cache_by_query ${if rule.cacheByQuery then "on" else "off"};
        ${optionalString (rule.vary != []) ''set $cache_vary "${concatStringsSep "," rule.vary}";''}
        ${optionalString rule.bypass "return 404; # Bypass cache"}
      }
    '') cfg.caching.rules);

      # Security configurations
      wafConfig = optionalString cfg.security.waf.enable ''
        # ModSecurity WAF configuration
        modsecurity on;
        modsecurity_rules_file /etc/nginx/modsecurity/main.conf;
        
        ${concatStringsSep "\n        " (map (rule: ''
        include /etc/nginx/modsecurity/rules/${rule}.conf;
        '') cfg.security.waf.rules)}
      '';

      rateLimitConfig = ''
        # Rate limiting
        limit_req_zone $binary_remote_addr zone=cdn_rate_limit:10m rate=${toString cfg.security.rateLimit.requests}r/${cfg.security.rateLimit.window};
        limit_req_status 429;
      '';

      geoConfig = ''
        # Geographic configuration
        geo $geoip_country_code {
          default ZZ;
          ${concatStringsSep "\n    " (map (country: ''
          ${country} ${country};
          '') cfg.security.geoBlock.allow)}
        }
      '';

      # Optimization configurations
      compressionConfig = ''
        # Compression settings
        ${optionalString cfg.optimization.compression.gzip ''
        gzip on;
        gzip_comp_level ${toString cfg.optimization.compression.level};
        gzip_min_length 1024;
        gzip_proxied any;
        gzip_vary on;
        gzip_types
          application/atom+xml
          application/javascript
          application/json
          application/rss+xml
          application/vnd.ms-fontobject
          application/x-font-ttf
          application/x-web-app-manifest+json
          application/xhtml+xml
          application/xml
          font/opentype
          image/svg+xml
          image/x-icon
          text/css
          text/plain
          text/x-component;
        ''}
        
        ${optionalString cfg.optimization.compression.brotli ''
        brotli on;
        brotli_comp_level ${toString cfg.optimization.compression.level};
        brotli_min_length 1024;
        brotli_types
          application/atom+xml
          application/javascript
          application/json
          application/rss+xml
          application/vnd.ms-fontobject
          application/x-font-ttf
          application/x-web-app-manifest+json
          application/xhtml+xml
          application/xml
          font/opentype
          image/svg+xml
          image/x-icon
          text/css
          text/plain
          text/x-component;
        ''}
      '';

      httpConfig = ''
        # HTTP version configuration
        ${optionalString (cfg.optimization.httpVersion == "h2") ''
        listen 443 ssl http2;
        listen [::]:443 ssl http2;
        ''}
        
        ${optionalString (cfg.optimization.httpVersion == "h3") ''
        listen 443 ssl http3;
        listen [::]:443 ssl http3;
        add_header Alt-Svc 'h3=":443"; ma=86400';
        ''}
        
        # TLS configuration
        ssl_certificate /etc/ssl/certs/${cfg.domain}.crt;
        ssl_certificate_key /etc/ssl/private/${cfg.domain}.key;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_prefer_server_ciphers off;
        ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
        ssl_session_cache shared:SSL:10m;
        ssl_session_timeout 1d;
        ssl_session_tickets off;
        
        # OCSP Stapling
        ssl_stapling on;
        ssl_stapling_verify on;
        resolver 8.8.8.8 8.8.4.4 valid=300s;
        resolver_timeout 5s;
        
        # Security headers
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
        add_header X-Frame-Options DENY always;
        add_header X-Content-Type-Options nosniff always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;
        add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; frame-ancestors 'none';" always;
      '';

      imageOptimizationConfig = optionalString cfg.optimization.imageOptimization ''
        # Image optimization
        map $http_accept $webp_suffix {
          default   "";
          "~*webp"  ".webp";
        }
        
        location ~* ^/images/.+\.(png|jpg|jpeg|gif)$ {
          add_header Vary Accept;
          try_files $uri$webp_suffix $uri =404;
          
          # Image caching
          expires 30d;
          add_header Cache-Control "public, immutable";
          
          # Image compression settings
          gzip_static on;
          brotli_static on;
        }
      '';

    in ''
      # CDN Nginx Configuration
      # Generated for domain: ${cfg.domain}
      
      upstream origin_servers {
        least_conn;
        ${originBackends}
      }
      
      # Rate limiting zones
      ${rateLimitConfig}
      
      # Geographic configuration
      ${geoConfig}
      
      server {
        listen 80;
        listen [::]:80;
        server_name ${cfg.domain};
        return 301 https://$server_name$request_uri;
      }
      
      server {
        ${httpConfig}
        server_name ${cfg.domain} www.${cfg.domain};
        
        # WAF configuration
        ${wafConfig}
        
        # Rate limiting
        limit_req zone=cdn_rate_limit burst=${toString cfg.security.rateLimit.burst} nodelay;
        
        # Geographic blocking
        ${optionalString (cfg.security.geoBlock.allow != []) ''
        if ($geoip_country_code !~ ^(${concatStringsSep "|" cfg.security.geoBlock.allow})$) {
          return 403;
        }
        ''}
        
        ${optionalString (cfg.security.geoBlock.deny != []) ''
        if ($geoip_country_code ~ ^(${concatStringsSep "|" cfg.security.geoBlock.deny})$) {
          return 403;
        }
        ''}
        
        # Main location - proxy to Varnish
        location / {
          proxy_pass http://127.0.0.1:8080;
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header X-CDN-Edge $server_addr;
          proxy_set_header X-CDN-Region $geoip_country_code;
          
          # Proxy settings
          proxy_http_version 1.1;
          proxy_set_header Connection "";
          proxy_buffering on;
          proxy_buffer_size 4k;
          proxy_buffers 8 4k;
          proxy_busy_buffers_size 8k;
          proxy_read_timeout 60s;
          proxy_send_timeout 60s;
          
          # Cache bypass headers
          proxy_cache_bypass $cookie_nocache $arg_nocache $arg_comment;
          proxy_no_cache $cookie_nocache $arg_nocache $arg_comment;
        }
        
        # API location
        ${optionalString cfg.api.enable ''
        location /api/ {
          proxy_pass http://127.0.0.1:${toString cfg.api.port}/;
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          
          # API authentication
          if ($http_authorization != "Bearer ${cfg.api.authToken}") {
            return 401;
          }
        }
        ''}
        
        # Metrics endpoint
        ${optionalString cfg.monitoring.prometheus.enable ''
        location ${cfg.monitoring.prometheus.path} {
          proxy_pass http://127.0.0.1:${toString cfg.monitoring.prometheus.port}${cfg.monitoring.prometheus.path};
          allow 127.0.0.1;
          allow ::1;
          deny all;
        }
        ''}
        
        # Health check endpoint
        location /health {
          access_log off;
          return 200 "healthy\n";
          add_header Content-Type text/plain;
        }
        
        # Image optimization
        ${imageOptimizationConfig}
        
        # Compression configuration
        ${compressionConfig}
        
        # Logging configuration
        ${optionalString cfg.monitoring.logging.access ''
        access_log /var/log/nginx/cdn_access.log ${cfg.monitoring.logging.format};
        ''}
        
        ${optionalString (cfg.monitoring.logging.level != "error") ''
        error_log /var/log/nginx/cdn_error.log ${cfg.monitoring.logging.level};
        ''}
      }
    '';

  # Generate site-specific configurations for edge nodes
  generateEdgeNodeConfig = cfg: nodeName: node: ''
    # Edge Node Configuration: ${nodeName}
    # Region: ${node.region}
    # Location: ${node.location}
    
    server {
      listen 80;
      listen [::]:80;
      server_name edge-${nodeName}.${cfg.domain};
      return 301 https://$server_name$request_uri;
    }
    
    server {
      listen 443 ssl http2;
      listen [::]:443 ssl http2;
      server_name edge-${nodeName}.${cfg.domain};
      
      # Edge-specific TLS
      ssl_certificate /etc/ssl/certs/edge-${nodeName}.${cfg.domain}.crt;
      ssl_certificate_key /etc/ssl/private/edge-${nodeName}.${cfg.domain}.key;
      
      # Edge node optimizations
      location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-CDN-Edge-Node ${nodeName};
        proxy_set_header X-CDN-Region ${node.region};
        proxy_set_header X-CDN-Location ${node.location};
      }
    }
  '';
}

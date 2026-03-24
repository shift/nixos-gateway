{ lib, pkgs }:

let
  inherit (lib)
    optionalString
    concatStringsSep
    ;

in {
  generateScript = cfg: pkgs.writeScriptBin "cdn-api" ''
    #!/usr/bin/env python3
    """
    CDN Management API Server
    For NixOS Gateway Configuration Framework
    """
    
    import json
    import os
    import time
    import logging
    import hashlib
    import subprocess
    from datetime import datetime, timedelta
    from typing import Dict, List, Optional, Any
    from dataclasses import dataclass, asdict
    
    from flask import Flask, request, jsonify, abort
    from flask_cors import CORS
    import requests
    import redis
    import yaml
    
    # Configuration
    CONFIG_FILE = os.getenv('CDN_CONFIG_FILE', '/etc/cdn/config.json')
    API_PORT = int(os.getenv('CDN_API_PORT', '8080'))
    API_TOKEN = os.getenv('CDN_API_TOKEN', 'secure-token')
    
    # Load configuration
    def load_config():
        try:
            with open(CONFIG_FILE, 'r') as f:
                return json.load(f)
        except Exception as e:
            logging.error(f"Failed to load config: {e}")
            return {}
    
    config = load_config()
    
    # Setup Flask app
    app = Flask(__name__)
    CORS(app)
    
    # Setup logging
    logging.basicConfig(
        level=logging.getLevelName(os.getenv('LOG_LEVEL', 'INFO')),
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    
    # Redis connection for caching
    try:
        redis_client = redis.Redis(host='localhost', port=6379, db=0, decode_responses=True)
        redis_client.ping()
    except:
        redis_client = None
        logging.warning("Redis not available, running without caching")
    
    # Authentication decorator
    def require_auth(f):
        def decorated(*args, **kwargs):
            auth_header = request.headers.get('Authorization')
            if not auth_header or not auth_header.startswith('Bearer '):
                abort(401, description="Missing or invalid authorization header")
            
            token = auth_header[7:]  # Remove 'Bearer ' prefix
            if token != API_TOKEN:
                abort(401, description="Invalid token")
            
            return f(*args, **kwargs)
        return decorated
    
    # Cache helpers
    def cache_get(key: str, default=None):
        if redis_client:
            try:
                value = redis_client.get(key)
                return json.loads(value) if value else default
            except:
                pass
        return default
    
    def cache_set(key: str, value: Any, ttl: int = 300):
        if redis_client:
            try:
                redis_client.setex(key, ttl, json.dumps(value))
            except:
                pass
    
    # API Routes
    
    @app.route('/api/v1/status', methods=['GET'])
    @require_auth
    def get_status():
        """Get CDN overall status"""
        return jsonify({
            "status": "healthy",
            "timestamp": datetime.utcnow().isoformat(),
            "version": "1.0.0",
            "domain": config.get('domain', 'unknown'),
            "origins_count": len(config.get('origins', [])),
            "edge_nodes_count": len(config.get('edgeNodes', {})),
            "uptime": "0s"  # Would be calculated from service start time
        })
    
    @app.route('/api/v1/cache/stats', methods=['GET'])
    @require_auth
    def get_cache_stats():
        """Get cache statistics"""
        cache_key = "cdn:cache:stats"
        cached_stats = cache_get(cache_key)
        
        if cached_stats:
            return jsonify(cached_stats)
        
        # Get stats from varnish
        try:
            varnishstats = subprocess.run(['varnishstat', '-j'], 
                                        capture_output=True, text=True)
            if varnishstats.returncode == 0:
                stats = json.loads(varnishstats.stdout)
                
                # Extract relevant metrics
                cache_stats = {
                    "cache_hits": stats.get("MAIN.cache_hit", 0),
                    "cache_misses": stats.get("MAIN.cache_miss", 0),
                    "cache_hit_ratio": 0,
                    "total_requests": stats.get("MAIN.client_req", 0),
                    "bytes_served": stats.get("MAIN.s_bodybytes", 0),
                    "timestamp": datetime.utcnow().isoformat()
                }
                
                # Calculate hit ratio
                hits = cache_stats["cache_hits"]
                misses = cache_stats["cache_misses"]
                if hits + misses > 0:
                    cache_stats["cache_hit_ratio"] = hits / (hits + misses)
                
                # Cache for 60 seconds
                cache_set(cache_key, cache_stats, 60)
                return jsonify(cache_stats)
                
        except Exception as e:
            logging.error(f"Failed to get varnish stats: {e}")
        
        # Fallback stats
        return jsonify({
            "cache_hits": 0,
            "cache_misses": 0,
            "cache_hit_ratio": 0,
            "total_requests": 0,
            "bytes_served": 0,
            "timestamp": datetime.utcnow().isoformat(),
            "error": "Unable to retrieve stats"
        })
    
    @app.route('/api/v1/cache/purge', methods=['POST'])
    @require_auth
    def purge_cache():
        """Purge cache entries"""
        data = request.get_json() or {}
        
        # Get purge parameters
        url = data.get('url')
        host = data.get('host', config.get('domain'))
        pattern = data.get('pattern')
        
        if not url and not pattern:
            abort(400, description="Either 'url' or 'pattern' is required")
        
        try:
            if url:
                # Purge specific URL
                cmd = ['varnishadm', 'ban', f'obj.http.X-URL ~ {url} && obj.http.X-Host ~ {host}']
            else:
                # Purge by pattern
                cmd = ['varnishadm', 'ban', f'obj.http.X-URL ~ {pattern}']
            
            result = subprocess.run(cmd, capture_output=True, text=True)
            
            if result.returncode == 0:
                response = {
                    "status": "success",
                    "message": "Cache purged successfully",
                    "url": url,
                    "pattern": pattern,
                    "host": host,
                    "timestamp": datetime.utcnow().isoformat()
                }
                
                # Clear cache stats
                cache_set("cdn:cache:stats", None, 0)
                
                # Send webhook notifications
                send_webhook('cache_purged', response)
                
                return jsonify(response)
            else:
                abort(500, description=f"Purge failed: {result.stderr}")
                
        except Exception as e:
            logging.error(f"Cache purge failed: {e}")
            abort(500, description=f"Purge failed: {str(e)}")
    
    @app.route('/api/v1/edge-nodes', methods=['GET'])
    @require_auth
    def get_edge_nodes():
        """Get edge node status"""
        edge_nodes = config.get('edgeNodes', {})
        nodes_status = {}
        
        for node_name, node_config in edge_nodes.items():
            # Check health
            health_url = f"https://edge-{node_name}.{config.get('domain')}/health"
            try:
                response = requests.get(health_url, timeout=5)
                healthy = response.status_code == 200
            except:
                healthy = False
            
            # Get metrics
            metrics_url = f"https://edge-{node_name}.{config.get('domain')}/edge-metrics"
            try:
                response = requests.get(metrics_url, timeout=5, headers={'Authorization': f'Bearer {API_TOKEN}'})
                metrics = response.json() if response.status_code == 200 else {}
            except:
                metrics = {}
            
            nodes_status[node_name] = {
                "name": node_name,
                "region": node_config.get('region'),
                "location": node_config.get('location'),
                "capacity": node_config.get('capacity'),
                "healthy": healthy,
                "last_check": datetime.utcnow().isoformat(),
                "metrics": metrics
            }
        
        return jsonify({
            "nodes": nodes_status,
            "total_nodes": len(nodes_status),
            "healthy_nodes": sum(1 for node in nodes_status.values() if node['healthy'])
        })
    
    @app.route('/api/v1/origins', methods=['GET'])
    @require_auth
    def get_origins():
        """Get origin server status"""
        origins = config.get('origins', [])
        origins_status = []
        
        for origin in origins:
            # Check health
            health_url = f"{'https' if origin.get('tls') else 'http'}://{origin['host']}:{origin['port']}{origin['healthCheck']['path']}"
            try:
                response = requests.get(health_url, timeout=5)
                healthy = response.status_code == origin['healthCheck'].get('expectedStatus', 200)
            except:
                healthy = False
            
            origins_status.append({
                "name": origin['name'],
                "host": origin['host'],
                "port": origin['port'],
                "tls": origin.get('tls', False),
                "healthy": healthy,
                "last_check": datetime.utcnow().isoformat(),
                "health_check": origin['healthCheck']
            })
        
        return jsonify({
            "origins": origins_status,
            "total_origins": len(origins_status),
            "healthy_origins": sum(1 for origin in origins_status if origin['healthy'])
        })
    
    @app.route('/api/v1/analytics/traffic', methods=['GET'])
    @require_auth
    def get_traffic_analytics():
        """Get traffic analytics"""
        # Default to last 24 hours
        time_range = request.args.get('time_range', '24h')
        
        # Parse time range
        if time_range.endswith('h'):
            hours = int(time_range[:-1])
        elif time_range.endswith('d'):
            hours = int(time_range[:-1]) * 24
        else:
            hours = 24
        
        start_time = datetime.utcnow() - timedelta(hours=hours)
        
        # This would typically query a database or time series database
        # For now, return mock data
        analytics = {
            "time_range": time_range,
            "start_time": start_time.isoformat(),
            "end_time": datetime.utcnow().isoformat(),
            "total_requests": 1000000,
            "unique_visitors": 50000,
            "bandwidth_served": "1.5TB",
            "cache_hit_ratio": 0.85,
            "average_response_time": "45ms",
            "top_countries": [
                {"country": "US", "requests": 400000, "percentage": 40},
                {"country": "GB", "requests": 200000, "percentage": 20},
                {"country": "DE", "requests": 150000, "percentage": 15},
                {"country": "FR", "requests": 100000, "percentage": 10},
                {"country": "CA", "requests": 80000, "percentage": 8}
            ],
            "top_content_types": [
                {"type": "image/jpeg", "requests": 300000, "percentage": 30},
                {"type": "text/html", "requests": 200000, "percentage": 20},
                {"type": "application/javascript", "requests": 150000, "percentage": 15},
                {"type": "text/css", "requests": 100000, "percentage": 10}
            ]
        }
        
        return jsonify(analytics)
    
    @app.route('/api/v1/config', methods=['GET'])
    @require_auth
    def get_config():
        """Get current CDN configuration"""
        return jsonify(config)
    
    @app.route('/api/v1/config/reload', methods=['POST'])
    @require_auth
    def reload_config():
        """Reload CDN configuration"""
        try:
            # Reload nginx
            subprocess.run(['nginx', '-s', 'reload'], check=True)
            
            # Reload varnish
            subprocess.run(['varnishreload'], check=True)
            
            response = {
                "status": "success",
                "message": "Configuration reloaded successfully",
                "timestamp": datetime.utcnow().isoformat()
            }
            
            # Send webhook notifications
            send_webhook('config_reloaded', response)
            
            return jsonify(response)
            
        except subprocess.CalledProcessError as e:
            logging.error(f"Config reload failed: {e}")
            abort(500, description=f"Config reload failed: {str(e)}")
    
    # Webhook functionality
    def send_webhook(event: str, data: dict):
        """Send webhook notifications"""
        webhooks = config.get('api', {}).get('webhooks', [])
        
        for webhook in webhooks:
            if event in webhook.get('events', []):
                try:
                    payload = {
                        "event": event,
                        "timestamp": datetime.utcnow().isoformat(),
                        "data": data
                    }
                    
                    # Add signature if secret provided
                    secret = webhook.get('secret')
                    if secret:
                        signature = hashlib.sha256(f"{json.dumps(payload)}{secret}".encode()).hexdigest()
                        headers = {'X-Webhook-Signature': signature}
                    else:
                        headers = {}
                    
                    requests.post(
                        webhook['url'],
                        json=payload,
                        headers=headers,
                        timeout=10
                    )
                    
                except Exception as e:
                    logging.error(f"Failed to send webhook to {webhook['url']}: {e}")
    
    # Health check endpoint
    @app.route('/health', methods=['GET'])
    def health_check():
        """API health check"""
        return jsonify({
            "status": "healthy",
            "timestamp": datetime.utcnow().isoformat(),
            "version": "1.0.0"
        })
    
    # Error handlers
    @app.errorhandler(400)
    def bad_request(error):
        return jsonify({
            "error": "Bad Request",
            "message": str(error.description),
            "status_code": 400
        }), 400
    
    @app.errorhandler(401)
    def unauthorized(error):
        return jsonify({
            "error": "Unauthorized",
            "message": str(error.description),
            "status_code": 401
        }), 401
    
    @app.errorhandler(500)
    def internal_error(error):
        return jsonify({
            "error": "Internal Server Error",
            "message": str(error.description),
            "status_code": 500
        }), 500
    
    if __name__ == '__main__':
        app.run(
            host='0.0.0.0',
            port=API_PORT,
            debug=False
        )
  '';

  # Generate configuration file for API
  generateConfigFile = cfg: pkgs.writeText "cdn-api-config.json" (builtins.toJSON {
    inherit (cfg) domain origins edgeNodes caching security optimization monitoring;
    
    api = {
      enable = true;
      port = cfg.api.port;
      authToken = cfg.api.authToken;
      webhooks = cfg.api.webhooks;
    };
  });

  # Generate systemd service for API
  generateSystemdService = cfg: {
    name = "cdn-api";
    description = "CDN Management API Service";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" "nginx.service" "varnish.service" ];
    requires = [ "network.target" ];
    
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.python3.withPackages (p: [p.flask p.flask-cors p.requests p.redis])}/bin/python3 ${generateScript cfg}";
      ExecReload = "/bin/kill -HUP $MAINPID";
      Restart = "on-failure";
      RestartSec = "5s";
      User = "cdn";
      Group = "cdn";
      
      # Security settings
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ "/var/log/cdn" "/tmp" ];
      
      # Resource limits
      MemoryLimit = "512M";
      CPUQuota = "50%";
      
      # Environment variables
      Environment = [
        "CDN_CONFIG_FILE=/etc/cdn/config.json"
        "CDN_API_PORT=${toString cfg.api.port}"
        "CDN_API_TOKEN=${cfg.api.authToken}"
        "PYTHONPATH=/etc/cdn/api"
      ];
    };
    
    # Path requirements
    path = with pkgs; [
      python3
      varnish
      nginx
      curl
      jq
    ];
  };

  # Generate OpenAPI documentation
  generateOpenAPISpec = cfg: {
    openapi = "3.0.0";
    info = {
      title = "CDN Management API";
      description = "API for managing NixOS Gateway CDN";
      version = "1.0.0";
    };
    
    servers = [
      {
        url = "https://${cfg.domain}/api/v1";
        description = "Production server";
      }
    ];
    
    paths = {
      "/status" = {
        get = {
          summary = "Get CDN status";
          operationId = "getStatus";
          responses = {
            "200" = {
              description = "CDN status information";
              content = {
                "application/json" = {
                  schema = {
                    type = "object";
                    properties = {
                      status = { type = "string"; };
                      timestamp = { type = "string"; format = "date-time"; };
                      domain = { type = "string"; };
                      origins_count = { type = "integer"; };
                      edge_nodes_count = { type = "integer"; };
                    };
                  };
                };
              };
            };
          };
        };
      };
      
      "/cache/stats" = {
        get = {
          summary = "Get cache statistics";
          operationId = "getCacheStats";
          responses = {
            "200" = {
              description = "Cache statistics";
              content = {
                "application/json" = {
                  schema = {
                    type = "object";
                    properties = {
                      cache_hits = { type = "integer"; };
                      cache_misses = { type = "integer"; };
                      cache_hit_ratio = { type = "number"; };
                      total_requests = { type = "integer"; };
                      bytes_served = { type = "integer"; };
                      timestamp = { type = "string"; format = "date-time"; };
                    };
                  };
                };
              };
            };
          };
        };
      };
      
      "/cache/purge" = {
        post = {
          summary = "Purge cache entries";
          operationId = "purgeCache";
          requestBody = {
            required = true;
            content = {
              "application/json" = {
                schema = {
                  type = "object";
                  properties = {
                    url = { type = "string"; description = "Specific URL to purge"; };
                    pattern = { type = "string"; description = "Pattern to match for purging"; };
                    host = { type = "string"; description = "Host to filter by"; };
                  };
                  oneOf = [
                    { required = ["url"]; }
                    { required = ["pattern"]; }
                  ];
                };
              };
            };
          };
          responses = {
            "200" = {
              description = "Cache purged successfully";
              content = {
                "application/json" = {
                  schema = {
                    type = "object";
                    properties = {
                      status = { type = "string"; };
                      message = { type = "string"; };
                      timestamp = { type = "string"; format = "date-time"; };
                    };
                  };
                };
              };
            };
          };
        };
      };
    };
    
    components = {
      securitySchemes = {
        BearerAuth = {
          type = "http";
          scheme = "bearer";
          bearerFormat = "JWT";
        };
      };
    };
    
    security = [
      { BearerAuth = []; }
    ];
  };
}

{ lib, pkgs }:

let
  inherit (lib)
    optionalString
    concatStringsSep
    ;

in {
  generateConfig = nodeName: node: cfg: 
    let
      # Node-specific nginx configuration
      nginxConfig = pkgs.writeText "edge-node-${nodeName}.conf" ''
        # Edge Node Configuration: ${nodeName}
        # Region: ${node.region}
        # Location: ${node.location}
        # Capacity: ${toString node.capacity}GB
        # Max Connections: ${toString node.maxConnections}
        
        worker_processes auto;
        worker_rlimit_nofile 1048576;
        
        events {
          worker_connections ${toString node.maxConnections};
          use epoll;
          multi_accept on;
        }
        
        http {
          # Basic settings
          sendfile on;
          tcp_nopush on;
          tcp_nodelay on;
          keepalive_timeout 65;
          types_hash_max_size 2048;
          
          # Connection limits
          client_max_body_size 100M;
          client_body_buffer_size 128k;
          client_header_buffer_size 1k;
          large_client_header_buffers 4 4k;
          
          # Performance tuning for this edge node
          worker_processes auto;
          worker_connections ${toString node.maxConnections};
          worker_rlimit_nofile 1048576;
          
          # Rate limiting per edge node
          limit_req_zone $binary_remote_addr zone=edge_${nodeName}_limit:10m rate=${toString (node.maxConnections / 10)}r/s;
          
          # Upstream to origin
          upstream origin_servers {
            least_conn;
            ${concatStringsSep "\n        " (map (origin: ''
            server ${origin.host}:${toString node.port} max_fails=3 fail_timeout=30s;
            '') cfg.origins)}
          }
          
          # Server configuration
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
            
            # SSL configuration
            ssl_certificate /etc/ssl/certs/edge-${nodeName}.${cfg.domain}.crt;
            ssl_certificate_key /etc/ssl/private/edge-${nodeName}.${cfg.domain}.key;
            ssl_protocols TLSv1.2 TLSv1.3;
            ssl_prefer_server_ciphers off;
            
            # Edge node specific headers
            add_header X-Edge-Node "${nodeName}";
            add_header X-Region "${node.region}";
            add_header X-Location "${node.location}";
            add_header X-Capacity "${toString node.capacity}GB";
            
            # Rate limiting
            limit_req zone=edge_${nodeName}_limit burst=${toString (node.maxConnections / 5)} nodelay;
            
            # Main location
            location / {
              proxy_pass http://origin_servers;
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_set_header X-Edge-Node "${nodeName}";
              
              # Connection settings
              proxy_http_version 1.1;
              proxy_set_header Connection "";
              proxy_buffering on;
              proxy_buffers 8 16k;
              proxy_buffer_size 32k;
              proxy_busy_buffers_size 64k;
              
              # Timeouts
              proxy_connect_timeout 5s;
              proxy_read_timeout 60s;
              proxy_send_timeout 60s;
            }
            
            # Health check
            location /health {
              access_log off;
              return 200 "healthy\n";
              add_header Content-Type text/plain;
            }
            
            # Node-specific metrics
            location /edge-metrics {
              access_log off;
              allow 127.0.0.1;
              allow ::1;
              deny all;
              
              # Custom metrics endpoint
              return 200 '{
                "node": "${nodeName}",
                "region": "${node.region}",
                "location": "${node.location}",
                "capacity": ${toString node.capacity},
                "max_connections": ${toString node.maxConnections},
                "active_connections": $connections_active,
                "requests": $request_counter,
                "cache_hits": $cache_hits_counter
              }';
              add_header Content-Type application/json;
            }
          }
          
          # Logging
          access_log /var/log/nginx/edge-${nodeName}-access.log;
          error_log /var/log/nginx/edge-${nodeName}-error.log;
          
          # Custom status counters
          status_zone server_zone;
          status_zone upstream_zone;
        }
      '';

      # Node-specific varnish configuration
      varnishConfig = pkgs.writeText "edge-node-${nodeName}.vcl" ''
        # Edge Node VCL: ${nodeName}
        vcl 4.1;
        
        # Node-specific backend configuration
        backend default {
          .host = "${if node.address != "" then node.address else "127.0.0.1"}";
          .port = "8080";
          .max_connections = ${toString node.maxConnections};
        }
        
        sub vcl_recv {
          # Add node identification
          set req.http.X-Edge-Node = "${nodeName}";
          set req.http.X-Region = "${node.region}";
          set req.http.X-Location = "${node.location}";
          
          # Node-specific capacity management
          if (obj.hits > ${toString (node.capacity * 1000)}) {
            set beresp.ttl = beresp.ttl / 2; # Reduce TTL under high load
          }
          
          # Health check
          if (req.url == "/health") {
            return (synth(200, "OK"));
          }
        }
        
        sub vcl_deliver {
          # Add node info to response
          set resp.http.X-Edge-Node = "${nodeName}";
          set resp.http.X-Region = "${node.region}";
          set resp.http.X-Location = "${node.location}";
          set resp.http.X-Capacity = "${toString node.capacity}GB";
          
          if (obj.hits > 0) {
            set resp.http.X-Cache = "HIT-EDGE-${nodeName}";
          } else {
            set resp.http.X-Cache = "MISS-EDGE-${nodeName}";
          }
        }
      '';

    in {
      # Configuration files
      nginx = nginxConfig;
      varnish = varnishConfig;
      
      # Systemd service for edge node
      systemdService = {
        name = "cdn-edge-${nodeName}";
        description = "CDN Edge Node ${nodeName} (${node.region})";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" "nginx.service" ];
        requires = [ "nginx.service" ];
        
        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.nginx}/bin/nginx -c ${nginxConfig}";
          ExecReload = "${pkgs.nginx}/bin/nginx -s reload -c ${nginxConfig}";
          Restart = "on-failure";
          RestartSec = "5s";
          User = "cdn";
          Group = "cdn";
          
          # Resource limits based on capacity
          MemoryMax = "${toString (node.capacity * 50)}M"; # 50MB per GB of cache
          CPUQuota = "${toString (node.maxConnections / 100)}%"; # Scale CPU with connections
        };
        
        # Environment variables
        environment = {
          EDGE_NODE = nodeName;
          EDGE_REGION = node.region;
          EDGE_LOCATION = node.location;
          EDGE_CAPACITY = toString node.capacity;
          EDGE_MAX_CONNECTIONS = toString node.maxConnections;
        };
      };
      
      # Monitoring configuration
      monitoring = {
        prometheusConfig = {
          job_name = "cdn-edge-${nodeName}";
          static_configs = [{
            targets = [ "${node.address}:9113" ]; # nginx-exporter
          }];
          labels = {
            edge_node = nodeName;
            region = node.region;
            location = node.location;
          };
        };
        
        healthCheck = {
          endpoint = "https://edge-${nodeName}.${cfg.domain}/health";
          interval = "30s";
          timeout = "5s";
          expected_status = 200;
        };
      };
      
      # Firewall rules
      firewallRules = [
        { port = 80; protocol = "tcp"; }
        { port = 443; protocol = "tcp"; }
        { port = 8080; protocol = "tcp"; } # varnish
        { port = 9113; protocol = "tcp"; } # nginx-exporter
      ];
      
      # Performance metrics
      metrics = {
        node = nodeName;
        region = node.region;
        location = node.location;
        capacityGB = node.capacity;
        maxConnections = node.maxConnections;
        estimatedThroughput = node.maxConnections * 1000; # requests per second
        estimatedBandwidth = node.bandwidth;
        memoryRequirement = node.capacity * 50; # MB
        cpuRequirement = node.maxConnections / 100; # percentage
      };
    };

  # Generate deployment manifest for edge node
  generateDeploymentManifest = nodeName: node: cfg: {
    name = "cdn-edge-${nodeName}";
    image = "nginx:alpine";
    
    replicas = 1;
    
    ports = [
      { name = "http"; containerPort = 80; }
      { name = "https"; containerPort = 443; }
      { name = "varnish"; containerPort = 8080; }
      { name = "metrics"; containerPort = 9113; }
    ];
    
    resources = {
      requests = {
        cpu = "${toString (node.maxConnections / 100)}m";
        memory = "${toString (node.capacity * 50)}Mi";
      };
      limits = {
        cpu = "${toString (node.maxConnections / 50)}m";
        memory = "${toString (node.capacity * 100)}Mi";
      };
    };
    
    environment = {
      EDGE_NODE = nodeName;
      EDGE_REGION = node.region;
      EDGE_LOCATION = node.location;
      EDGE_CAPACITY = toString node.capacity;
      EDGE_MAX_CONNECTIONS = toString node.maxConnections;
    };
    
    labels = {
      app = "cdn-edge";
      node = nodeName;
      region = node.region;
      location = node.location;
    };
    
    annotations = {
      "prometheus.io/scrape" = "true";
      "prometheus.io/port" = "9113";
      "prometheus.io/path" = "/metrics";
    };
  };

  # Generate DNS records for edge node
  generateDNSRecords = nodeName: node: cfg: [
    {
      name = "edge-${nodeName}";
      type = "A";
      value = node.address;
      ttl = 300;
    }
    {
      name = "edge-${nodeName}";
      type = "TXT";
      value = "region=${node.region};location=${node.location};capacity=${toString node.capacity}";
      ttl = 300;
    }
  ];

  # Generate health check configuration
  generateHealthCheck = nodeName: node: cfg: {
    name = "cdn-edge-${nodeName}";
    endpoint = "https://edge-${nodeName}.${cfg.domain}/health";
    interval = "30s";
    timeout = "5s";
    expected_status = 200;
    expected_content = "healthy";
    
    alerts = [
      {
        condition = "failure == 3";
        severity = "warning";
        message = "CDN Edge Node ${nodeName} is unhealthy";
      }
      {
        condition = "failure == 5";
        severity = "critical";
        message = "CDN Edge Node ${nodeName} is down";
      }
    ];
  };
}

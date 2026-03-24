{ lib, pkgs }:

let
  inherit (lib)
    optionalString
    concatStringsSep
    ;

in {
  generateMonitorScript = cfg: pkgs.writeScriptBin "cdn-health-monitor" ''
    #!/usr/bin/env python3
    """
    CDN Health Monitoring Service
    Monitors edge nodes, origins, and overall CDN health
    """
    
    import json
    import os
    import time
    import logging
    import requests
    import subprocess
    import socket
    from datetime import datetime, timedelta
    from typing import Dict, List, Optional, Any
    
    # Configuration
    CONFIG_FILE = os.getenv('CDN_CONFIG_FILE', '/etc/cdn/config.json')
    CHECK_INTERVAL = int(os.getenv('CHECK_INTERVAL', '30'))  # seconds
    LOG_LEVEL = os.getenv('LOG_LEVEL', 'INFO')
    
    # Setup logging
    logging.basicConfig(
        level=getattr(logging, LOG_LEVEL),
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    
    # Load configuration
    def load_config():
        try:
            with open(CONFIG_FILE, 'r') as f:
                return json.load(f)
        except Exception as e:
            logging.error(f"Failed to load config: {e}")
            return {}
    
    config = load_config()
    
    class HealthChecker:
        def __init__(self, config):
            self.config = config
            self.status_history = {}
            self.alert_threshold = {
                'origin': 3,  # 3 consecutive failures
                'edge_node': 3,
                'cache': 2
            }
        
        def check_origin_health(self, origin: Dict) -> Dict:
            """Check origin server health"""
            health_config = origin.get('healthCheck', {})
            protocol = 'https' if origin.get('tls') else 'http'
            url = f"{protocol}://{origin['host']}:{origin['port']}{health_config.get('path', '/health')}"
            expected_status = health_config.get('expectedStatus', 200)
            timeout = health_config.get('timeout', '5s').rstrip('s')
            
            start_time = time.time()
            try:
                response = requests.get(
                    url,
                    timeout=int(timeout),
                    verify=False  # Skip SSL verification for health checks
                )
                response_time = (time.time() - start_time) * 1000  # ms
                
                healthy = response.status_code == expected_status
                
                return {
                    'name': origin['name'],
                    'healthy': healthy,
                    'response_time': response_time,
                    'status_code': response.status_code,
                    'expected_status': expected_status,
                    'timestamp': datetime.utcnow().isoformat(),
                    'error': None if healthy else f"Status {response.status_code} != {expected_status}"
                }
                
            except requests.exceptions.Timeout:
                return {
                    'name': origin['name'],
                    'healthy': False,
                    'response_time': None,
                    'status_code': None,
                    'expected_status': expected_status,
                    'timestamp': datetime.utcnow().isoformat(),
                    'error': f"Timeout after {timeout}s"
                }
            except requests.exceptions.ConnectionError as e:
                return {
                    'name': origin['name'],
                    'healthy': False,
                    'response_time': None,
                    'status_code': None,
                    'expected_status': expected_status,
                    'timestamp': datetime.utcnow().isoformat(),
                    'error': f"Connection error: {str(e)}"
                }
            except Exception as e:
                return {
                    'name': origin['name'],
                    'healthy': False,
                    'response_time': None,
                    'status_code': None,
                    'expected_status': expected_status,
                    'timestamp': datetime.utcnow().isoformat(),
                    'error': f"Unexpected error: {str(e)}"
                }
        
        def check_edge_node_health(self, node_name: str, node_config: Dict) -> Dict:
            """Check edge node health"""
            domain = self.config.get('domain', 'unknown')
            health_url = f"https://edge-{node_name}.{domain}/health"
            
            start_time = time.time()
            try:
                response = requests.get(health_url, timeout=5, verify=False)
                response_time = (time.time() - start_time) * 1000  # ms
                
                healthy = response.status_code == 200
                
                # Get additional metrics
                metrics_url = f"https://edge-{node_name}.{domain}/edge-metrics"
                metrics = {}
                try:
                    metrics_response = requests.get(metrics_url, timeout=5, verify=False)
                    if metrics_response.status_code == 200:
                        metrics = metrics_response.json()
                except:
                    pass
                
                return {
                    'name': node_name,
                    'region': node_config.get('region'),
                    'location': node_config.get('location'),
                    'healthy': healthy,
                    'response_time': response_time,
                    'status_code': response.status_code,
                    'timestamp': datetime.utcnow().isoformat(),
                    'metrics': metrics,
                    'error': None if healthy else f"Status {response.status_code} != 200"
                }
                
            except requests.exceptions.Timeout:
                return {
                    'name': node_name,
                    'region': node_config.get('region'),
                    'location': node_config.get('location'),
                    'healthy': False,
                    'response_time': None,
                    'status_code': None,
                    'timestamp': datetime.utcnow().isoformat(),
                    'error': "Timeout after 5s"
                }
            except Exception as e:
                return {
                    'name': node_name,
                    'region': node_config.get('region'),
                    'location': node_config.get('location'),
                    'healthy': False,
                    'response_time': None,
                    'status_code': None,
                    'timestamp': datetime.utcnow().isoformat(),
                    'error': f"Health check failed: {str(e)}"
                }
        
        def check_cache_health(self) -> Dict:
            """Check Varnish cache health"""
            try:
                # Check varnish daemon
                result = subprocess.run(['varnishadm', 'ping'], capture_output=True, text=True, timeout=10)
                varnish_healthy = result.returncode == 0 and 'pong' in result.stdout.lower()
                
                # Get cache stats
                cache_stats = {}
                try:
                    stats_result = subprocess.run(['varnishstat', '-j'], capture_output=True, text=True, timeout=10)
                    if stats_result.returncode == 0:
                        stats = json.loads(stats_result.stdout)
                        cache_stats = {
                            'cache_hit': stats.get('MAIN.cache_hit', 0),
                            'cache_miss': stats.get('MAIN.cache_miss', 0),
                            'client_req': stats.get('MAIN.client_req', 0),
                            'uptime': stats.get('MAIN.uptime', 0)
                        }
                except:
                    pass
                
                # Calculate hit ratio
                hits = cache_stats.get('cache_hit', 0)
                misses = cache_stats.get('cache_miss', 0)
                hit_ratio = hits / (hits + misses) if (hits + misses) > 0 else 0
                
                return {
                    'healthy': varnish_healthy,
                    'timestamp': datetime.utcnow().isoformat(),
                    'stats': cache_stats,
                    'hit_ratio': hit_ratio,
                    'error': None if varnish_healthy else "Varnish daemon not responding"
                }
                
            except Exception as e:
                return {
                    'healthy': False,
                    'timestamp': datetime.utcnow().isoformat(),
                    'stats': {},
                    'hit_ratio': 0,
                    'error': f"Cache health check failed: {str(e)}"
                }
        
        def check_nginx_health(self) -> Dict:
            """Check Nginx health"""
            try:
                # Check nginx daemon
                result = subprocess.run(['nginx', '-t'], capture_output=True, text=True, timeout=10)
                nginx_config_ok = result.returncode == 0
                
                # Check if nginx is running
                try:
                    response = requests.get(f"http://localhost/health", timeout=5)
                    nginx_responding = response.status_code == 200
                except:
                    nginx_responding = False
                
                return {
                    'healthy': nginx_config_ok and nginx_responding,
                    'config_valid': nginx_config_ok,
                    'responding': nginx_responding,
                    'timestamp': datetime.utcnow().isoformat(),
                    'error': None if nginx_config_ok and nginx_responding else "Nginx not healthy"
                }
                
            except Exception as e:
                return {
                    'healthy': False,
                    'config_valid': False,
                    'responding': False,
                    'timestamp': datetime.utcnow().isoformat(),
                    'error': f"Nginx health check failed: {str(e)}"
                }
        
        def check_service_port(self, host: str, port: int, timeout: int = 5) -> Dict:
            """Check if a service is listening on a port"""
            try:
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                sock.settimeout(timeout)
                result = sock.connect_ex((host, port))
                sock.close()
                
                return {
                    'host': host,
                    'port': port,
                    'listening': result == 0,
                    'timestamp': datetime.utcnow().isoformat(),
                    'error': None if result == 0 else f"Port {port} not accessible on {host}"
                }
            except Exception as e:
                return {
                    'host': host,
                    'port': port,
                    'listening': False,
                    'timestamp': datetime.utcnow().isoformat(),
                    'error': f"Port check failed: {str(e)}"
                }
        
        def update_status_history(self, component_type: str, component_name: str, healthy: bool):
            """Update status history for alerting"""
            key = f"{component_type}:{component_name}"
            
            if key not in self.status_history:
                self.status_history[key] = []
            
            # Add current status
            self.status_history[key].append({
                'healthy': healthy,
                'timestamp': datetime.utcnow()
            })
            
            # Keep only last 10 entries
            self.status_history[key] = self.status_history[key][-10:]
            
            return self.status_history[key]
        
        def should_alert(self, component_type: str, component_name: str, healthy: bool) -> bool:
            """Determine if an alert should be triggered"""
            if healthy:
                return False
            
            history = self.update_status_history(component_type, component_name, healthy)
            threshold = self.alert_threshold.get(component_type, 3)
            
            # Check if we've exceeded the failure threshold
            consecutive_failures = 0
            for status in reversed(history):
                if not status['healthy']:
                    consecutive_failures += 1
                else:
                    break
            
            return consecutive_failures >= threshold
        
        def send_alert(self, component_type: str, component_name: str, status: Dict):
            """Send alert (placeholder - would integrate with alerting system)"""
            alert = {
                'alert_type': 'health_check_failure',
                'component_type': component_type,
                'component_name': component_name,
                'severity': 'warning' if component_type == 'edge_node' else 'critical',
                'message': f"{component_type.title()} {component_name} is unhealthy",
                'details': status,
                'timestamp': datetime.utcnow().isoformat()
            }
            
            # Log alert
            logging.warning(f"ALERT: {json.dumps(alert)}")
            
            # Here you could integrate with:
            # - Slack notifications
            # - Email alerts
            # - PagerDuty
            # - Prometheus Alertmanager
            # etc.
        
        def run_health_checks(self) -> Dict:
            """Run all health checks and return results"""
            results = {
                'timestamp': datetime.utcnow().isoformat(),
                'origins': [],
                'edge_nodes': [],
                'cache': None,
                'nginx': None,
                'summary': {
                    'total_origins': 0,
                    'healthy_origins': 0,
                    'total_edge_nodes': 0,
                    'healthy_edge_nodes': 0,
                    'cache_healthy': False,
                    'nginx_healthy': False,
                    'overall_healthy': False
                }
            }
            
            # Check origins
            origins = self.config.get('origins', [])
            results['summary']['total_origins'] = len(origins)
            
            for origin in origins:
                origin_status = self.check_origin_health(origin)
                results['origins'].append(origin_status)
                
                if origin_status['healthy']:
                    results['summary']['healthy_origins'] += 1
                else:
                    if self.should_alert('origin', origin['name'], False):
                        self.send_alert('origin', origin['name'], origin_status)
            
            # Check edge nodes
            edge_nodes = self.config.get('edgeNodes', {})
            results['summary']['total_edge_nodes'] = len(edge_nodes)
            
            for node_name, node_config in edge_nodes.items():
                node_status = self.check_edge_node_health(node_name, node_config)
                results['edge_nodes'].append(node_status)
                
                if node_status['healthy']:
                    results['summary']['healthy_edge_nodes'] += 1
                else:
                    if self.should_alert('edge_node', node_name, False):
                        self.send_alert('edge_node', node_name, node_status)
            
            # Check cache
            cache_status = self.check_cache_health()
            results['cache'] = cache_status
            results['summary']['cache_healthy'] = cache_status['healthy']
            
            if not cache_status['healthy'] and self.should_alert('cache', 'varnish', False):
                self.send_alert('cache', 'varnish', cache_status)
            
            # Check nginx
            nginx_status = self.check_nginx_health()
            results['nginx'] = nginx_status
            results['summary']['nginx_healthy'] = nginx_status['healthy']
            
            if not nginx_status['healthy'] and self.should_alert('nginx', 'daemon', False):
                self.send_alert('nginx', 'daemon', nginx_status)
            
            # Calculate overall health
            results['summary']['overall_healthy'] = (
                results['summary']['healthy_origins'] > 0 and
                results['summary']['healthy_edge_nodes'] > 0 and
                results['summary']['cache_healthy'] and
                results['summary']['nginx_healthy']
            )
            
            return results
        
        def save_results(self, results: Dict):
            """Save health check results to file"""
            try:
                with open('/var/log/cdn/health-status.json', 'w') as f:
                    json.dump(results, f, indent=2)
            except Exception as e:
                logging.error(f"Failed to save health results: {e}")
    
    def main():
        """Main monitoring loop"""
        logging.info("Starting CDN Health Monitor")
        
        health_checker = HealthChecker(config)
        
        # Create log directory
        os.makedirs('/var/log/cdn', exist_ok=True)
        
        while True:
            try:
                logging.debug("Running health checks...")
                results = health_checker.run_health_checks()
                
                # Log summary
                summary = results['summary']
                logging.info(f"Health Check - Origins: {summary['healthy_origins']}/{summary['total_origins']}, "
                           f"Edge Nodes: {summary['healthy_edge_nodes']}/{summary['total_edge_nodes']}, "
                           f"Cache: {'OK' if summary['cache_healthy'] else 'FAIL'}, "
                           f"Nginx: {'OK' if summary['nginx_healthy'] else 'FAIL'}, "
                           f"Overall: {'OK' if summary['overall_healthy'] else 'FAIL'}")
                
                # Save results
                health_checker.save_results(results)
                
                # Sleep until next check
                time.sleep(CHECK_INTERVAL)
                
            except KeyboardInterrupt:
                logging.info("Health monitor stopped by user")
                break
            except Exception as e:
                logging.error(f"Unexpected error in health monitor: {e}")
                time.sleep(10)  # Wait before retrying
    
    if __name__ == '__main__':
        main()
  '';

  # Generate Prometheus exporter configuration
  generatePrometheusConfig = cfg: {
    job_name = "cdn-health-monitor";
    static_configs = [{
      targets = [ "localhost:8080" ]; # Health monitor metrics
      labels = {
        service = "cdn-health";
        component = "monitoring";
      };
    }];
    
    scrape_interval = "30s";
    scrape_timeout = "10s";
    metrics_path = "/metrics";
  };

  # Generate Grafana dashboard configuration
  generateGrafanaDashboard = cfg: {
    dashboard = {
      title = "CDN Health Monitoring";
      tags = [ "cdn" "monitoring" "health" ];
      timezone = "browser";
      
      panels = [
        {
          title = "Overall Status";
          type = "stat";
          targets = [{
            expr = "cdn_health_overall";
            legendFormat = "Overall Health";
          }];
          fieldConfig = {
            defaults = {
              color = { mode = "palette-classic"; };
              custom = {
                displayMode = "list";
                orientation = "horizontal";
              };
              mappings = [
                { 
                  options = { "0" = { text = "UNHEALTHY"; color = "red"; } };
                  type = "value";
                }
                { 
                  options = { "1" = { text = "HEALTHY"; color = "green"; } };
                  type = "value";
                }
              ];
            };
          };
        }
        
        {
          title = "Origin Servers Status";
          type = "table";
          targets = [{
            expr = "cdn_origin_health";
            format = "table";
            instant = true;
          }];
          transformations = [
            { id = "organize"; options = { 
              excludeByName = { Time = true; };
              renameByName = {
                origin_name = "Origin";
                healthy = "Status";
                response_time = "Response Time (ms)";
              };
            }};
          ];
        }
        
        {
          title = "Edge Nodes Status";
          type = "table";
          targets = [{
            expr = "cdn_edge_node_health";
            format = "table";
            instant = true;
          }];
          transformations = [
            { id = "organize"; options = { 
              excludeByName = { Time = true; };
              renameByName = {
                node_name = "Edge Node";
                region = "Region";
                healthy = "Status";
                response_time = "Response Time (ms)";
              };
            }};
          ];
        }
        
        {
          title = "Cache Hit Ratio";
          type = "stat";
          targets = [{
            expr = "cdn_cache_hit_ratio";
            legendFormat = "Cache Hit Ratio";
          }];
          fieldConfig = {
            defaults = {
              unit = "percentunit";
              min = 0;
              max = 1;
              thresholds = {
                steps = [
                  { color = "red"; value = 0; }
                  { color = "yellow"; value = 0.7; }
                  { color = "green"; value = 0.9; }
                ];
              };
            };
          };
        }
        
        {
          title = "Response Times";
          type = "graph";
          targets = [
            {
              expr = "cdn_origin_response_time";
              legendFormat = "{{origin_name}}";
            }
            {
              expr = "cdn_edge_node_response_time";
              legendFormat = "{{node_name}}";
            }
          ];
          yAxes = [
            { label = "Response Time (ms)"; }
          ];
        }
        
        {
          title = "Health Check Alerts";
          type = "table";
          targets = [{
            expr = "cdn_health_alerts";
            format = "table";
            instant = true;
          }];
        }
      ];
      
      time = {
        from = "now-1h";
        to = "now";
      };
      
      refresh = "30s";
    };
  };

  # Generate systemd service for health monitor
  generateSystemdService = cfg: {
    name = "cdn-health-monitor";
    description = "CDN Health Monitoring Service";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" "nginx.service" "varnish.service" ];
    requires = [ "network.target" ];
    
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.python3.withPackages (p: [p.requests])}/bin/python3 ${generateMonitorScript cfg}";
      Restart = "on-failure";
      RestartSec = "10s";
      User = "cdn";
      Group = "cdn";
      
      # Security settings
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ "/var/log/cdn" ];
      
      # Environment variables
      Environment = [
        "CDN_CONFIG_FILE=/etc/cdn/config.json"
        "CHECK_INTERVAL=30"
        "LOG_LEVEL=INFO"
      ];
    };
    
    # Path requirements
    path = with pkgs; [
      python3
      varnish
      nginx
      curl
    ];
  };
}

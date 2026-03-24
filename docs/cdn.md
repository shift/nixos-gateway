# Self-Hosted CDN with Edge Caching

This document describes the NixOS Gateway Framework's self-hosted Content Delivery Network (CDN) implementation with edge caching capabilities.

## Overview

The CDN module provides a complete content delivery solution that replaces cloud-based CDNs like Azure Front Door, AWS CloudFront, and GCP Cloud CDN. It features global edge distribution, intelligent caching, and comprehensive security controls.

## Architecture

### Components

1. **Edge Nodes**: Globally distributed caching servers
2. **Origin Servers**: Your application backends
3. **Control Plane**: Configuration and management
4. **Monitoring**: Performance and health tracking

### Data Flow

```
Client Request → Edge Node → Cache Hit?
                      ↓
                 Cache Miss → Origin Server
                      ↓
                 Cache Response ← Edge Node ← Client
```

## Configuration

### Basic Setup

```nix
services.gateway.cdn = {
  enable = true;
  domain = "cdn.example.com";

  origins = [
    {
      name = "primary";
      host = "api.example.com";
      port = 443;
      tls = true;
    }
  ];

  caching = {
    defaultTtl = "1h";
    rules = [
      {
        path = "/static/*";
        ttl = "7d";
      }
    ];
  };
};
```

### Advanced Configuration

#### Origins

```nix
origins = [
  {
    name = "primary";
    host = "api.example.com";
    port = 443;
    tls = true;
    healthCheck = {
      path = "/health";
      interval = "30s";
      timeout = "5s";
    };
    weight = 5;
  }
];
```

#### Edge Nodes

```nix
edgeNodes = [
  {
    region = "us-east";
    location = "New York";
    capacity = 100;  # GB
    publicIPs = [ "1.2.3.4" ];
    privateIPs = [ "10.0.0.1" ];
  }
];
```

#### Caching Rules

```nix
caching = {
  defaultTtl = "1h";
  maxTtl = "24h";
  rules = [
    {
      path = "/static/*";
      ttl = "7d";
      compression = true;
    }
    {
      path = "/api/*";
      ttl = "5m";
      cacheByQuery = false;
    }
  ];
};
```

#### Security

```nix
security = {
  waf = {
    enable = true;
    rules = [ "OWASP-Core-Ruleset" ];
  };
  rateLimit = {
    requests = 1000;
    window = "1m";
    burst = 2000;
  };
  geoBlock = {
    allow = [ "US" "CA" "GB" ];
    deny = [ "CN" ];
  };
};
```

#### Optimization

```nix
optimization = {
  imageOptimization = true;
  compression = {
    brotli = true;
    gzip = true;
  };
  httpVersion = "h2";
};
```

#### Monitoring

```nix
monitoring = {
  prometheus = {
    enable = true;
    port = 9090;
  };
  logging = {
    level = "info";
    format = "json";
  };
};
```

#### Cache Invalidation

```nix
invalidation = {
  enable = true;
  port = 8080;
  authToken = "secure-token";
};
```

## Cache Invalidation

### API Usage

```bash
# Invalidate a specific URL
curl -X PURGE \
  -H "Authorization: Bearer your-token" \
  http://localhost:8080/path/to/content

# Invalidate by pattern (future feature)
curl -X PURGE \
  -H "Authorization: Bearer your-token" \
  -d '{"pattern": "/static/*"}' \
  http://localhost:8080/invalidate/pattern

# Clear entire cache
curl -X PURGE \
  -H "Authorization: Bearer your-token" \
  http://localhost:8080/invalidate/all
```

### Programmatic Invalidation

```python
import requests

def invalidate_cache(url, token):
    headers = {'Authorization': f'Bearer {token}'}
    response = requests.request('PURGE', f'http://localhost:8080{url}', headers=headers)
    return response.status_code == 200
```

## Monitoring

### Metrics

The CDN exposes Prometheus metrics at `http://localhost:9090/metrics`:

- `nginx_http_requests_total`: Total HTTP requests
- `nginx_http_requests_duration_seconds`: Request duration
- `nginx_cache_hit`: Cache hit ratio
- `nginx_upstream_response_time`: Origin response time

### Health Checks

Health endpoints are available at:
- `/health`: CDN health status
- `/metrics`: Prometheus metrics

### Logging

Structured JSON logs include:
- Request/response details
- Cache status (HIT/MISS)
- Geographic information
- Performance metrics

## Geographic Distribution

### Edge Node Management

Edge nodes are configured with:

```nix
edgeNodes = [
  {
    region = "us-east";
    location = "New York";
    capacity = 100;
    publicIPs = [ "1.2.3.4" ];
    privateIPs = [ "10.0.0.1" ];
  }
];
```

### Geographic Routing

The system automatically routes requests to the nearest edge node based on:

1. Client IP geolocation
2. Network performance
3. Edge node capacity
4. Health status

### DNS Configuration

Configure DNS for geographic routing:

```nix
services.gateway.dns = {
  enable = true;
  zones = {
    "example.com" = {
      records = [
        "cdn IN CNAME cdn.example.com."
      ];
    };
  };
};
```

## Security Features

### Web Application Firewall (WAF)

```nix
waf = {
  enable = true;
  rules = [ "OWASP-Core-Ruleset" ];
};
```

### Rate Limiting

```nix
rateLimit = {
  requests = 1000;  # per window
  window = "1m";
  burst = 2000;
};
```

### Geographic Blocking

```nix
geoBlock = {
  allow = [ "US" "CA" "GB" ];
  deny = [ "CN" ];
};
```

## Performance Optimization

### Content Optimization

- **Image optimization**: Automatic format conversion and compression
- **Minification**: CSS, JavaScript, and HTML minification
- **Compression**: Brotli and Gzip support
- **HTTP/2**: Modern protocol support

### Cache Strategies

- **Hierarchical caching**: Edge → Regional → Origin
- **Cache warming**: Proactive content prefetching
- **Stale-while-revalidate**: Improved cache efficiency
- **Cache hierarchies**: Multi-level cache organization

## Integration

### DNS Integration

```nix
services.gateway.dns = {
  # DNS configuration for CDN domains
};
```

### Load Balancing

```nix
services.gateway.loadBalancing = {
  # Origin server load balancing
};
```

### Monitoring

```nix
services.gateway.monitoring = {
  # Centralized monitoring
};
```

### Security

```nix
services.gateway.security = {
  # Additional security layers
};
```

## Deployment

### Single Node

For testing or small deployments:

```nix
services.gateway.cdn = {
  enable = true;
  # Basic configuration
};
```

### Multi-Node

For production with edge distribution:

```nix
# Node 1: US East
services.gateway.cdn = {
  enable = true;
  edgeNodes = [{
    region = "us-east";
    # ... configuration
  }];
};

# Node 2: EU West
services.gateway.cdn = {
  enable = true;
  edgeNodes = [{
    region = "eu-west";
    # ... configuration
  }];
};
```

### Anycast Setup

For optimal routing:

```nix
# Configure BGP anycast on edge nodes
services.gateway.byoi-bgp = {
  enable = true;
  anycastIPs = [ "1.2.3.4" ];
};
```

## Troubleshooting

### Common Issues

1. **Cache not working**
   - Check NGINX configuration: `nginx -t`
   - Verify cache directory permissions
   - Check cache size limits

2. **High origin load**
   - Review cache hit rates
   - Adjust TTL settings
   - Implement cache warming

3. **Geographic routing issues**
   - Verify GeoIP database updates
   - Check edge node health
   - Review DNS configuration

### Debug Mode

Enable debug logging:

```nix
monitoring = {
  logging = {
    level = "debug";
  };
};
```

### Cache Inspection

Check cache status:

```bash
# View cache contents
find /var/cache/nginx/cdn -type f | head -10

# Check cache hit ratio
curl -H "X-Cache-Status: HIT" http://cdn.example.com/
```

## Performance Benchmarks

### Expected Performance

- **Cache hit rate**: 95%+ for optimized content
- **Latency**: <50ms globally for cached content
- **Throughput**: 10,000+ concurrent connections per edge node
- **Origin offload**: 90%+ reduction in origin requests

### Monitoring Queries

```promql
# Cache hit rate
rate(nginx_cache_hit_total[5m]) / rate(nginx_http_requests_total[5m])

# Response time percentiles
histogram_quantile(0.95, rate(nginx_http_request_duration_seconds_bucket[5m]))

# Origin response time
rate(nginx_upstream_response_time_sum[5m]) / rate(nginx_upstream_response_time_count[5m])
```

## API Reference

### Cache Invalidation API

#### Endpoints

- `PURGE /path`: Invalidate specific path
- `PURGE /invalidate/pattern`: Invalidate by pattern
- `PURGE /invalidate/all`: Clear entire cache

#### Authentication

Bearer token authentication:

```
Authorization: Bearer <token>
```

### Management API (Future)

RESTful API for configuration management:

- `GET /api/v1/config`: Get current configuration
- `PUT /api/v1/config`: Update configuration
- `GET /api/v1/stats`: Get performance statistics
- `POST /api/v1/invalidate`: Programmatic invalidation

## Examples

See `examples/cdn-example.nix` for a complete configuration example.

## Migration from Cloud CDN

### AWS CloudFront

1. Export CloudFront distributions
2. Map origins and behaviors to NixOS configuration
3. Configure edge nodes in target regions
4. Update DNS to point to new CDN
5. Test and validate performance

### Azure Front Door

1. Export Front Door configuration
2. Map routing rules to caching rules
3. Configure WAF rules
4. Set up geographic routing
5. Migrate custom domains

### GCP Cloud CDN

1. Export backend services and buckets
2. Configure origin servers
3. Set up cache invalidation
4. Configure load balancing
5. Update DNS records

## Best Practices

### Cache Configuration

1. **Set appropriate TTLs**: Balance freshness vs performance
2. **Use cache hierarchies**: Edge → Regional → Origin
3. **Implement cache warming**: For popular content
4. **Monitor cache efficiency**: Track hit rates and adjust

### Security

1. **Enable WAF**: Protect against common attacks
2. **Configure rate limiting**: Prevent abuse
3. **Use HTTPS**: Encrypt all traffic
4. **Regular updates**: Keep security rules current

### Monitoring

1. **Set up alerts**: For cache misses, high latency
2. **Monitor origin health**: Track backend performance
3. **Log analysis**: Review access patterns
4. **Capacity planning**: Monitor resource usage

### Deployment

1. **Start small**: Test with single edge node
2. **Gradual rollout**: Add regions incrementally
3. **Monitor performance**: Validate improvements
4. **Plan for scale**: Design for growth

## Support

For issues and questions:

- Check the troubleshooting guide
- Review logs in `/var/log/nginx/`
- Monitor metrics in Prometheus/Grafana
- Consult the configuration examples

## Contributing

To contribute improvements:

1. Test changes thoroughly
2. Update documentation
3. Add comprehensive tests
4. Follow the existing code patterns
5. Submit pull requests with detailed descriptions
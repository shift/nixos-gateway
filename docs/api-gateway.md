# API Gateway

The NixOS Gateway Framework includes a self-hosted API gateway that provides comprehensive request routing, authentication, rate limiting, and API management capabilities. This replaces cloud services like Azure API Management, GCP API Gateway, and AWS API Gateway.

## Features

### Request Routing
- HTTP/HTTPS request routing based on path, method, and headers
- Load balancing across multiple backend services
- URL rewriting and path transformation
- Support for REST, GraphQL, and WebSocket APIs
- Custom routing rules and middleware chains

### Authentication and Authorization
- OAuth 2.0 and OpenID Connect support
- JWT token validation and generation
- API key authentication
- Basic authentication with user databases
- Role-based access control (RBAC)
- Integration with existing identity providers

### Rate Limiting and Throttling
- Request rate limiting per client/IP
- Burst rate handling with token bucket algorithms
- Distributed rate limiting for clustered deployments
- Custom rate limit policies per API endpoint
- Rate limit violation responses and logging

### API Management
- API versioning and lifecycle management
- API documentation generation (OpenAPI/Swagger)
- API analytics and monitoring
- API catalog and discovery
- API transformation and aggregation
- Mock API responses for development

### Security Features
- Request/response filtering and validation
- CORS (Cross-Origin Resource Sharing) configuration
- SSL/TLS termination and certificate management
- DDoS protection and anomaly detection
- API threat protection (SQL injection, XSS prevention)

### Observability
- Request/response logging with structured data
- Metrics collection for API performance
- Health checks for backend services
- Distributed tracing integration
- Alerting for API failures and performance issues

## Architecture

The API gateway is built on OpenResty (Nginx + Lua) and provides:

- **Core Engine**: OpenResty with LuaJIT for high-performance request processing
- **Plugin System**: Extensible middleware system for custom functionality
- **Configuration Layer**: Declarative NixOS configuration with validation
- **Integration Layer**: Seamless integration with existing NixOS Gateway modules

## Configuration

### Basic Setup

```nix
services.gateway.api-gateway = {
  enable = true;
  port = 8080;

  routes = [
    {
      path = "/api/v1/users";
      methods = ["GET" "POST"];
      backend = "http://user-service:3000";
      auth = {
        type = "oauth2";
        provider = "keycloak";
      };
      rateLimit = {
        requests = 100;
        window = "1m";
      };
    }
  ];
};
```

### Authentication Configuration

#### OAuth 2.0
```nix
authentication.oauth2.providers = {
  keycloak = {
    issuer = "https://keycloak.example.com";
    clientId = "api-gateway";
    clientSecret = "secret";
  };
};
```

#### JWT
```nix
authentication.jwt = {
  enable = true;
  secret = "your-jwt-secret";
};
```

#### API Keys
```nix
authentication.apiKeys = {
  enable = true;
  database = "/var/lib/api-gateway/keys.db";
};
```

### Rate Limiting

#### Local Rate Limiting
```nix
rateLimiting.defaultLimits = {
  requests = 100;
  window = "1m";
};
```

#### Distributed Rate Limiting with Redis
```nix
rateLimiting.redis = {
  host = "redis.example.com";
  port = 6379;
  password = "redis-password";
};
```

### CORS Configuration
```nix
cors = {
  enable = true;
  allowedOrigins = ["https://app.example.com"];
  allowedMethods = ["GET" "POST" "PUT" "DELETE" "OPTIONS"];
  allowedHeaders = ["Content-Type" "Authorization" "X-API-Key"];
};
```

### Monitoring and Logging
```nix
monitoring = {
  enable = true;
  metrics = true;
  healthChecks = true;
};

logging = {
  enable = true;
  format = "json";
  level = "info";
};
```

## Plugin System

The API gateway includes a comprehensive plugin system for extending functionality:

### Available Plugins

- **Rate Limiting**: Request throttling and burst control
- **Authentication**: Multiple authentication mechanisms
- **CORS**: Cross-origin resource sharing support
- **Logging**: Structured request/response logging
- **Monitoring**: Metrics collection and health checks
- **Security**: Request filtering and threat protection
- **Transformation**: Request/response transformation

### Custom Plugins

Plugins are written in Lua and can be added to the `plugins` directory:

```lua
-- plugins/custom_plugin.lua
local _M = {}

function _M.process(config)
  -- Custom processing logic
  ngx.log(ngx.INFO, "Custom plugin executed")
end

return _M
```

## Integration with Existing Modules

The API gateway integrates seamlessly with other NixOS Gateway modules:

### Monitoring Integration
- Automatic Prometheus metrics collection
- Health check endpoints for backend services
- Integration with existing monitoring dashboards

### Security Integration
- Leverages existing firewall and IDS configurations
- Shares authentication providers with other services
- Integrates with threat intelligence feeds

### Logging Integration
- Structured logging compatible with existing log aggregation
- Request tracing across the entire gateway stack
- Audit logging for security events

## Testing

The API gateway includes comprehensive testing:

### Unit Tests
```bash
test-api-gateway
```

### Integration Tests
```bash
systemctl start api-gateway-integration-test
```

### Load Testing
```bash
systemctl start api-gateway-load-test
```

### Security Testing
```bash
systemctl start api-gateway-security-test
```

## Performance

The API gateway is designed for high performance:

- **Throughput**: 1000+ concurrent connections
- **Latency**: Sub-millisecond routing latency
- **Memory**: Efficient LuaJIT-based processing
- **Scalability**: Horizontal scaling with Redis-backed rate limiting

## Security Considerations

- All traffic is encrypted in transit (TLS 1.3)
- Authentication tokens are validated on every request
- Rate limiting prevents abuse and DoS attacks
- Request filtering blocks common attack vectors
- Comprehensive audit logging for compliance

## Examples

See `examples/api-gateway-example.nix` for a complete configuration example including:

- Multiple authentication providers
- Complex routing rules
- Rate limiting configuration
- CORS setup
- Monitoring integration
- Backend service configuration

## Troubleshooting

### Common Issues

1. **Gateway not starting**: Check nginx configuration syntax
2. **Authentication failures**: Verify OAuth2/JWT configuration
3. **Rate limiting not working**: Check Redis connectivity
4. **CORS errors**: Verify CORS configuration
5. **Performance issues**: Monitor Lua memory usage

### Debug Mode

Enable debug logging:
```nix
logging.level = "debug";
```

### Health Checks

Check gateway health:
```bash
curl http://localhost:8080/health
```

View metrics:
```bash
curl http://localhost:8080/metrics
```

## API Documentation

The gateway automatically generates OpenAPI documentation for configured routes. Access the documentation at:

```
http://localhost:8080/docs
```

## Migration from Cloud Gateways

When migrating from cloud API gateways:

1. Export existing API definitions
2. Configure equivalent routes in NixOS
3. Set up authentication providers
4. Configure rate limiting policies
5. Test thoroughly in staging environment
6. Update client applications with new endpoints

## Best Practices

1. **Use HTTPS**: Always enable TLS in production
2. **Implement Rate Limiting**: Protect backend services from abuse
3. **Monitor Performance**: Set up alerts for latency and error rates
4. **Regular Updates**: Keep OpenResty and Lua modules updated
5. **Backup Configuration**: Version control all gateway configurations
6. **Test Thoroughly**: Use the included test suite before deployment

## Support

For issues and questions:

- Check the troubleshooting guide
- Review the example configurations
- Run the diagnostic tests
- Check nginx and OpenResty logs
- Consult the NixOS Gateway documentation
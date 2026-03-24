# Service Mesh Implementation

## Overview

The NixOS Gateway Framework includes a comprehensive self-hosted service mesh implementation based on Istio, providing secure microservice communication, advanced traffic management, and full observability capabilities.

## Architecture

### Components

- **Control Plane**: Istio control plane (istiod) manages configuration and certificates
- **Data Plane**: Envoy proxies provide service-to-service communication
- **Ingress/Egress Gateways**: Manage north-south traffic
- **Service Discovery**: Automatic service registration and discovery
- **Certificate Management**: Automatic mTLS certificate generation and rotation

### Integration Points

- **Distributed Tracing**: Integration with Jaeger/OpenTelemetry
- **Monitoring**: Prometheus metrics and Grafana dashboards
- **Security**: Zero-trust networking with authorization policies
- **Traffic Management**: Intelligent routing and load balancing

## Configuration

### Basic Setup

```nix
services.gateway.serviceMesh = {
  enable = true;
  mesh = {
    name = "istio";
    version = "1.20.0";
    type = "istio";
    namespace = "istio-system";
  };
};
```

### Sidecar Injection

Enable automatic sidecar injection for namespaces:

```nix
services.gateway.serviceMesh.sidecarInjection = {
  enable = true;
  namespaces = [ "default" "production" ];
};
```

### Traffic Management

#### Virtual Services

Define routing rules for services:

```nix
services.gateway.serviceMesh.trafficManagement.virtualServices = [{
  name = "web-service";
  hosts = [ "web-service.default.svc.cluster.local" ];
  http = [{
    match = [{
      uri = {
        prefix = "/api";
      };
    }];
    route = [{
      destination = {
        host = "api-service";
        subset = "v1";
      };
      weight = 100;
    }];
  }];
}];
```

#### Destination Rules

Configure load balancing and circuit breaking:

```nix
services.gateway.serviceMesh.trafficManagement.destinationRules = [{
  name = "api-service";
  host = "api-service";
  subsets = [
    { name = "v1"; labels = { version = "v1"; }; }
    { name = "v2"; labels = { version = "v2"; }; }
  ];
}];
```

#### Gateways

Configure ingress gateways:

```nix
services.gateway.serviceMesh.trafficManagement.gateways = [{
  name = "api-gateway";
  selector = { istio = "ingressgateway"; };
  servers = [{
    port = 80;
    name = "http";
    hosts = [ "api.example.com" ];
  }];
}];
```

### Security Policies

#### Peer Authentication

Configure mTLS settings:

```nix
services.gateway.serviceMesh.security.peerAuthentication = [{
  name = "default-strict";
  selector = {
    matchLabels = {
      app = "api-service";
    };
  };
  mtls = "STRICT";
}];
```

#### Authorization Policies

Define access control rules:

```nix
services.gateway.serviceMesh.security.authorizationPolicies = [{
  name = "api-access";
  selector = {
    matchLabels = {
      app = "api-service";
    };
  };
  action = "ALLOW";
  rules = [{
    from = [{
      source = {
        principals = [ "cluster.local/ns/default/sa/web-service" ];
      };
    }];
    to = [{
      operation = {
        methods = [ "GET" "POST" ];
        paths = [ "/api/*" ];
      };
    }];
  }];
}];
```

### Observability

Enable comprehensive observability:

```nix
services.gateway.serviceMesh.observability = {
  enable = true;
  tracing = {
    enable = true;
    sampling = 0.1;  # 10% sampling rate
  };
  metrics = {
    enable = true;
    prometheus = true;
  };
};
```

### Integration

Integrate with existing gateway services:

```nix
services.gateway.serviceMesh.integration = {
  tracing = true;      # Integrate with gateway tracing
  monitoring = true;   # Integrate with gateway monitoring
  zeroTrust = true;    # Integrate with zero trust security
};
```

## Usage Examples

### Microservice Deployment

Deploy services with automatic sidecar injection:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-service
  namespace: default
  labels:
    app: api-service
    version: v1
spec:
  replicas: 3
  selector:
    matchLabels:
      app: api-service
  template:
    metadata:
      labels:
        app: api-service
        version: v1
        security.istio.io/tlsMode: istio
        service.istio.io/canonical-name: api-service
    spec:
      containers:
      - name: api
        image: my-api:latest
        ports:
        - containerPort: 8080
```

### Canary Deployments

Implement canary deployments:

```nix
services.gateway.serviceMesh.trafficManagement.virtualServices = [{
  name = "api-canary";
  hosts = [ "api.example.com" ];
  http = [{
    route = [
      {
        destination = {
          host = "api-service";
          subset = "v1";
        };
        weight = 90;
      }
      {
        destination = {
          host = "api-service";
          subset = "v2";
        };
        weight = 10;
      }
    ];
  }];
}];
```

### Circuit Breaker

Configure circuit breaker patterns:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: api-circuit-breaker
spec:
  host: api-service
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        http1MaxPendingRequests: 10
        maxRequestsPerConnection: 10
    outlierDetection:
      consecutive5xxErrors: 3
      interval: 10s
      baseEjectionTime: 30s
      maxEjectionPercent: 50
```

## Monitoring and Troubleshooting

### Metrics

Key metrics to monitor:

- `istio_requests_total`: Total requests through the mesh
- `istio_request_duration_milliseconds`: Request latency
- `envoy_cluster_upstream_cx_active`: Active connections
- `istio_tcp_connections_opened_total`: TCP connections

### Tracing

Distributed tracing provides end-to-end visibility:

```bash
# View traces in Jaeger
kubectl port-forward svc/jaeger-query -n istio-system 16686:16686
# Open http://localhost:16686
```

### Debugging

Common debugging commands:

```bash
# Check sidecar injection
kubectl get pods -o jsonpath='{.items[*].spec.containers[*].name}'

# View Envoy configuration
kubectl exec -it <pod> -c istio-proxy -- pilot-agent request GET config_dump

# Check mTLS status
kubectl exec -it <pod> -c istio-proxy -- pilot-agent request GET server_info

# View authorization policies
kubectl get authorizationpolicies
```

## Security Considerations

### mTLS Configuration

Always enable STRICT mTLS in production:

```nix
services.gateway.serviceMesh.security.peerAuthentication = [{
  name = "strict-mtls";
  mtls = "STRICT";
}];
```

### Authorization Policies

Implement least-privilege access:

```nix
services.gateway.serviceMesh.security.authorizationPolicies = [
  {
    name = "deny-all";
    action = "DENY";
    rules = [{}];  # Empty rules = deny all
  }
  {
    name = "allow-specific";
    action = "ALLOW";
    rules = [{
      from = [{
        source = {
          principals = [ "cluster.local/ns/production/sa/frontend" ];
        };
      }];
      to = [{
        operation = {
          methods = [ "GET" ];
          paths = [ "/api/public/*" ];
        };
      }];
    }];
  }
];
```

### Certificate Management

Istio automatically manages certificates, but monitor expiry:

```bash
# Check certificate expiry
kubectl get secret -n istio-system istio.default -o jsonpath='{.data.cert-chain\.pem}' | base64 -d | openssl x509 -noout -dates
```

## Performance Tuning

### Resource Limits

Configure appropriate resource limits:

```yaml
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
  components:
    pilot:
      k8s:
        resources:
          requests:
            cpu: 500m
            memory: 2Gi
```

### Traffic Optimization

Optimize Envoy configuration:

```nix
services.gateway.serviceMesh = {
  # Additional Envoy configuration
  envoyConfig = {
    concurrency = 2;
    connectionLimit = 1024;
  };
};
```

## Testing

### Unit Tests

Run service mesh unit tests:

```bash
nix build .#checks.x86_64-linux.service-mesh-unit-tests
```

### Integration Tests

Run comprehensive integration tests:

```bash
nix build .#checks.x86_64-linux.service-mesh-integration-tests
```

### Chaos Engineering

Test resilience with fault injection:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: chaos-test
spec:
  hosts:
  - api-service
  http:
  - fault:
      delay:
        percentage:
          value: 50
        fixedDelay: 5s
      abort:
        percentage:
          value: 10
        httpStatus: 503
    route:
    - destination:
        host: api-service
```

## Troubleshooting

### Common Issues

1. **Sidecar not injected**: Check namespace labels and mutating webhook
2. **Traffic not routing**: Verify virtual service and destination rule configuration
3. **mTLS failures**: Check peer authentication policies
4. **High latency**: Monitor Envoy metrics and adjust circuit breaker settings

### Logs

Access service mesh logs:

```bash
# Control plane logs
kubectl logs -n istio-system deployment/istiod

# Data plane logs
kubectl logs <pod> -c istio-proxy

# Gateway logs
kubectl logs -n istio-system deployment/istio-ingressgateway
```

## Migration Guide

### From No Service Mesh

1. Enable service mesh in configuration
2. Label namespaces for injection
3. Deploy services with sidecar injection
4. Configure traffic management rules
5. Enable security policies
6. Set up observability

### From Other Service Meshes

1. Export existing configuration
2. Translate to Istio resources
3. Update application manifests
4. Test in staging environment
5. Gradual rollout to production

## Best Practices

- Always use STRICT mTLS in production
- Implement comprehensive authorization policies
- Monitor service mesh metrics continuously
- Use canary deployments for updates
- Regularly rotate certificates
- Test fault scenarios regularly
- Keep Istio version up to date</content>
<parameter name="filePath">docs/service-mesh.md
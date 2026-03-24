{ config, lib, pkgs, ... }:

let
  inherit (lib) mkOption types;

  # Test configuration for service mesh
  testConfig = {
    services.gateway.serviceMesh = {
      enable = true;
      mesh = {
        name = "istio";
        version = "1.20.0";
        type = "istio";
        namespace = "istio-system";
      };

      sidecarInjection = {
        enable = true;
        namespaces = [ "default" "test-namespace" ];
      };

      trafficManagement = {
        virtualServices = [{
          name = "test-service";
          hosts = [ "test-service.default.svc.cluster.local" ];
          http = [{
            route = [{
              destination = {
                host = "test-service";
                subset = "v1";
              };
              weight = 100;
            }];
          }];
        }];

        destinationRules = [{
          name = "test-service";
          host = "test-service";
          subsets = [
            { name = "v1"; labels = { version = "v1"; }; }
            { name = "v2"; labels = { version = "v2"; }; }
          ];
        }];

        gateways = [{
          name = "test-gateway";
          servers = [{
            port = 80;
            name = "http";
            hosts = [ "*" ];
          }];
        }];
      };

      security = {
        peerAuthentication = [{
          name = "default";
          mtls = "STRICT";
        }];

        authorizationPolicies = [{
          name = "allow-test-service";
          action = "ALLOW";
          rules = [{
            to = [{
              operation = {
                methods = [ "GET" "POST" ];
              };
            }];
          }];
        }];
      };

      observability = {
        enable = true;
        tracing = {
          enable = true;
          sampling = 0.1;
        };
        metrics = {
          enable = true;
          prometheus = true;
        };
      };

      integration = {
        tracing = true;
        monitoring = true;
        zeroTrust = true;
      };
    };
  };

  # Test scenarios
  testScenarios = {
    basicConnectivity = {
      name = "basic-connectivity";
      description = "Test basic service-to-service connectivity through mesh";
      steps = [
        "Deploy test services with sidecar injection"
        "Verify Envoy sidecars are injected"
        "Test HTTP connectivity between services"
        "Verify mTLS encryption"
      ];
    };

    trafficManagement = {
      name = "traffic-management";
      description = "Test intelligent traffic routing and load balancing";
      steps = [
        "Deploy multiple versions of test service"
        "Configure virtual service with traffic splitting"
        "Verify traffic distribution"
        "Test canary deployment scenarios"
      ];
    };

    securityPolicies = {
      name = "security-policies";
      description = "Test security policy enforcement";
      steps = [
        "Configure peer authentication policies"
        "Test mTLS requirements"
        "Configure authorization policies"
        "Verify policy enforcement"
      ];
    };

    observability = {
      name = "observability";
      description = "Test metrics, logs, and traces collection";
      steps = [
        "Verify Prometheus metrics collection"
        "Check Jaeger trace collection"
        "Validate Grafana dashboards"
        "Test log aggregation"
      ];
    };

    faultInjection = {
      name = "fault-injection";
      description = "Test chaos engineering capabilities";
      steps = [
        "Configure fault injection rules"
        "Test delay injection"
        "Test abort injection"
        "Verify circuit breaker behavior"
      ];
    };
  };

in {
  name = "service-mesh";

  nodes = {
    gateway = { config, ... }: testConfig;

    client = { config, ... }: {
      environment.systemPackages = with pkgs; [
        curl
        kubectl
        istioctl
      ];
    };
  };

  testScript = ''
    start_all()

    # Wait for Istio control plane
    gateway.wait_for_unit("istio-control-plane.service")
    gateway.wait_for_unit("istiod.service")

    # Test Istio installation
    gateway.succeed("kubectl get pods -n istio-system")
    gateway.succeed("kubectl get svc -n istio-system")

    # Test sidecar injection
    gateway.succeed("kubectl label namespace default istio-injection=enabled")
    gateway.succeed("kubectl apply -f ${./test-manifests/test-service.yaml}")

    # Wait for test service deployment
    gateway.wait_until_succeeds("kubectl get pods -l app=test-service -o jsonpath='{.items[*].status.phase}' | grep -q Running")

    # Verify sidecar injection
    gateway.succeed("kubectl get pods -l app=test-service -o jsonpath='{.items[*].spec.containers[*].name}' | grep -q istio-proxy")

    # Test basic connectivity
    client.succeed("curl -f http://test-service.default.svc.cluster.local/health")

    # Test traffic management
    gateway.succeed("kubectl apply -f ${./test-manifests/virtual-service.yaml}")
    gateway.succeed("kubectl apply -f ${./test-manifests/destination-rule.yaml}")

    # Verify traffic splitting
    client.succeed("curl -f http://test-service.default.svc.cluster.local/version | grep -E '(v1|v2)'")

    # Test security policies
    gateway.succeed("kubectl apply -f ${./test-manifests/peer-authentication.yaml}")
    gateway.succeed("kubectl apply -f ${./test-manifests/authorization-policy.yaml}")

    # Verify mTLS
    client.succeed("curl -f --cacert /etc/ssl/certs/ca-certificates.crt https://test-service.default.svc.cluster.local/secure")

    # Test observability
    gateway.succeed("kubectl get svc -n istio-system | grep prometheus")
    gateway.succeed("kubectl get svc -n istio-system | grep jaeger")

    # Verify metrics collection
    client.succeed("curl -f http://prometheus.istio-system.svc.cluster.local:9090/api/v1/query?query=istio_requests_total")

    # Test fault injection
    gateway.succeed("kubectl apply -f ${./test-manifests/fault-injection.yaml}")

    # Verify fault injection works
    client.fail("curl -f --max-time 5 http://test-service.default.svc.cluster.local/delay")

    print("All service mesh tests passed!")
  '';

  # Test manifests
  testManifests = {
    "test-service.yaml" = ''
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: test-service
        labels:
          app: test-service
      spec:
        replicas: 2
        selector:
          matchLabels:
            app: test-service
        template:
          metadata:
            labels:
              app: test-service
              version: v1
          spec:
            containers:
            - name: test-service
              image: nginx:alpine
              ports:
              - containerPort: 80
              livenessProbe:
                httpGet:
                  path: /health
                  port: 80
              readinessProbe:
                httpGet:
                  path: /health
                  port: 80
    '';

    "virtual-service.yaml" = ''
      apiVersion: networking.istio.io/v1beta1
      kind: VirtualService
      metadata:
        name: test-service
      spec:
        hosts:
        - test-service
        http:
        - route:
          - destination:
              host: test-service
              subset: v1
            weight: 80
          - destination:
              host: test-service
              subset: v2
            weight: 20
    '';

    "destination-rule.yaml" = ''
      apiVersion: networking.istio.io/v1beta1
      kind: DestinationRule
      metadata:
        name: test-service
      spec:
        host: test-service
        subsets:
        - name: v1
          labels:
            version: v1
        - name: v2
          labels:
            version: v2
    '';

    "peer-authentication.yaml" = ''
      apiVersion: security.istio.io/v1beta1
      kind: PeerAuthentication
      metadata:
        name: default
        namespace: default
      spec:
        mtls:
          mode: STRICT
    '';

    "authorization-policy.yaml" = ''
      apiVersion: security.istio.io/v1beta1
      kind: AuthorizationPolicy
      metadata:
        name: allow-test-service
        namespace: default
      spec:
        selector:
          matchLabels:
            app: test-service
        action: ALLOW
        rules:
        - to:
          - operation:
              methods: ["GET", "POST"]
    '';

    "fault-injection.yaml" = ''
      apiVersion: networking.istio.io/v1beta1
      kind: VirtualService
      metadata:
        name: test-service-fault
      spec:
        hosts:
        - test-service
        http:
        - match:
          - uri:
              prefix: "/delay"
          fault:
            delay:
              percentage:
                value: 100
              fixedDelay: 10s
          route:
          - destination:
              host: test-service
    '';
  };
}</content>
<parameter name="filePath">tests/service-mesh-test.nix
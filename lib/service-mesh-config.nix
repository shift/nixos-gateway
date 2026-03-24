{ lib }:

let
  inherit (lib) mkOption types;

  # Generate Istio operator configuration
  generateIstioOperator = cfg: {
    apiVersion = "install.istio.io/v1alpha1";
    kind = "IstioOperator";
    metadata = {
      namespace = cfg.mesh.namespace;
      name = "istio-control-plane";
    };
    spec = {
      profile = "default";
      components = {
        pilot = {
          enabled = true;
          k8s = {
            env = [
              {
                name = "PILOT_TRACE_SAMPLING";
                value = toString (cfg.observability.tracing.sampling * 100);
              }
            ];
          };
        };
        ingressGateways = [
          {
            name = "istio-ingressgateway";
            enabled = true;
            k8s = {
              service = {
                type = "LoadBalancer";
                ports = [
                  {
                    name = "status-port";
                    port = 15021;
                    targetPort = 15021;
                  }
                  {
                    name = "http2";
                    port = 80;
                    targetPort = 8080;
                  }
                  {
                    name = "https";
                    port = 443;
                    targetPort = 8443;
                  }
                  {
                    name = "tcp";
                    port = 31400;
                    targetPort = 31400;
                  }
                  {
                    name = "tls";
                    port = 15443;
                    targetPort = 15443;
                  }
                ];
              };
            };
          }
        ];
        egressGateways = [
          {
            name = "istio-egressgateway";
            enabled = true;
          }
        ];
      };
      values = {
        global = {
          proxy = {
            tracer = "zipkin";
          };
          disablePolicyChecks = false;
          enableTracing = cfg.observability.tracing.enable;
          istioNamespace = cfg.mesh.namespace;
        };
        pilot = {
          traceSampling = cfg.observability.tracing.sampling * 100;
        };
        telemetry = {
          enabled = cfg.observability.enable;
          v2 = {
            enabled = cfg.observability.enable;
            prometheus = {
              enabled = cfg.observability.metrics.prometheus;
            };
          };
        };
      };
    };
  };

  # Generate sidecar injector configuration
  generateSidecarInjector = cfg: {
    apiVersion = "admissionregistration.k8s.io/v1";
    kind = "MutatingWebhookConfiguration";
    metadata = {
      name = "istio-sidecar-injector";
      labels = {
        app = "sidecar-injector";
        "istio.io/rev" = "default";
      };
    };
    webhooks = [
      {
        name = "sidecar-injector.istio.io";
        clientConfig = {
          service = {
            name = "istiod";
            namespace = cfg.mesh.namespace;
            path = "/inject";
          };
          caBundle = ""; # Will be filled by cert-manager
        };
        sideEffects = "None";
        admissionReviewVersions = [
          "v1beta1"
          "v1"
        ];
        rules = [
          {
            operations = [ "CREATE" ];
            apiGroups = [ "" ];
            apiVersions = [ "v1" ];
            resources = [ "pods" ];
          }
        ];
        namespaceSelector = {
          matchLabels = {
            "istio-injection" = "enabled";
          };
        };
      }
    ];
  };

  # Generate traffic management resources
  generateTrafficManagement =
    trafficCfg:
    let
      virtualServices = map (vs: {
        apiVersion = "networking.istio.io/v1beta1";
        kind = "VirtualService";
        metadata = {
          name = vs.name;
          namespace = "default";
        };
        spec = {
          inherit (vs) hosts http;
        };
      }) trafficCfg.virtualServices;

      destinationRules = map (dr: {
        apiVersion = "networking.istio.io/v1beta1";
        kind = "DestinationRule";
        metadata = {
          name = dr.name;
          namespace = "default";
        };
        spec = {
          inherit (dr) host subsets;
        };
      }) trafficCfg.destinationRules;

      gateways = map (gw: {
        apiVersion = "networking.istio.io/v1beta1";
        kind = "Gateway";
        metadata = {
          name = gw.name;
          namespace = "default";
        };
        spec = {
          inherit (gw) selector servers;
        };
      }) trafficCfg.gateways;

    in
    {
      virtualServices = builtins.toJSON virtualServices;
      destinationRules = builtins.toJSON destinationRules;
      gateways = builtins.toJSON gateways;
    };

  # Generate Grafana dashboards
  generateGrafanaDashboards = {
    "istio-service-dashboard.json" = {
      dashboard = {
        title = "Istio Service Dashboard";
        tags = [
          "istio"
          "service-mesh"
        ];
        panels = [
          {
            title = "Service Request Rate";
            type = "graph";
            targets = [
              {
                expr = "rate(istio_requests_total[5m])";
                legendFormat = "{{destination_service_name}}";
              }
            ];
          }
          {
            title = "Service Response Time";
            type = "graph";
            targets = [
              {
                expr = "histogram_quantile(0.95, rate(istio_request_duration_milliseconds_bucket[5m]))";
                legendFormat = "{{destination_service_name}}";
              }
            ];
          }
        ];
      };
    };
    "istio-mesh-dashboard.json" = {
      dashboard = {
        title = "Istio Mesh Dashboard";
        tags = [
          "istio"
          "service-mesh"
        ];
        panels = [
          {
            title = "Active Connections";
            type = "graph";
            targets = [
              {
                expr = "envoy_cluster_upstream_cx_active";
                legendFormat = "{{cluster_name}}";
              }
            ];
          }
          {
            title = "HTTP Error Rate";
            type = "graph";
            targets = [
              {
                expr = "rate(istio_requests_total{response_code=~\"5..\"}[5m]) / rate(istio_requests_total[5m]) * 100";
                legendFormat = "{{destination_service_name}}";
              }
            ];
          }
        ];
      };
    };
  };

  # Generate complete Istio manifests
  generateIstioManifests =
    cfg:
    let
      operator = generateIstioOperator cfg;
      injector = generateSidecarInjector cfg;
    in
    {
      "istio-operator.yaml" = builtins.toJSON operator;
      "sidecar-injector.yaml" = builtins.toJSON injector;
    };

in
{
  inherit
    generateIstioOperator
    generateSidecarInjector
    generateTrafficManagement
    generateGrafanaDashboards
    generateIstioManifests
    ;
}

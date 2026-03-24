{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.gateway.serviceMesh;
  meshTester = import ../lib/mesh-tester.nix { inherit lib pkgs; };

  # Istio configuration helpers
  istioConfig = import ../lib/service-mesh-config.nix { inherit lib; };
  istioPolicies = import ../lib/service-mesh-policies.nix { inherit lib; };

  # Service mesh types
  meshType = types.submodule {
    options = {
      name = mkOption {
        type = types.str;
        description = "Service mesh name";
      };
      version = mkOption {
        type = types.str;
        description = "Service mesh version";
      };
      type = mkOption {
        type = types.enum [
          "istio"
          "linkerd"
        ];
        default = "istio";
        description = "Service mesh implementation";
      };
      namespace = mkOption {
        type = types.str;
        default = "istio-system";
        description = "Kubernetes namespace for mesh control plane";
      };
    };
  };

  # Virtual service configuration
  virtualServiceType = types.submodule {
    options = {
      name = mkOption {
        type = types.str;
        description = "Virtual service name";
      };
      hosts = mkOption {
        type = types.listOf types.str;
        description = "List of hostnames";
      };
      http = mkOption {
        type = types.listOf (
          types.submodule {
            options = {
              match = mkOption {
                type = types.listOf (
                  types.submodule {
                    options = {
                      uri = mkOption {
                        type = types.attrs;
                        description = "URI match criteria";
                      };
                    };
                  }
                );
                default = [ ];
              };
              route = mkOption {
                type = types.listOf (
                  types.submodule {
                    options = {
                      destination = mkOption {
                        type = types.submodule {
                          options = {
                            host = mkOption { type = types.str; };
                            subset = mkOption {
                              type = types.str;
                              default = "";
                            };
                          };
                        };
                      };
                      weight = mkOption {
                        type = types.int;
                        default = 100;
                      };
                    };
                  }
                );
              };
            };
          }
        );
        default = [ ];
      };
    };
  };

  # Destination rule configuration
  destinationRuleType = types.submodule {
    options = {
      name = mkOption {
        type = types.str;
        description = "Destination rule name";
      };
      host = mkOption {
        type = types.str;
        description = "Target service host";
      };
      subsets = mkOption {
        type = types.listOf (
          types.submodule {
            options = {
              name = mkOption { type = types.str; };
              labels = mkOption {
                type = types.attrsOf types.str;
                default = { };
              };
            };
          }
        );
        default = [ ];
      };
    };
  };

in
{
  options.services.gateway.serviceMesh = {
    enable = mkEnableOption "Service Mesh";

    mesh = mkOption {
      type = meshType;
      default = {
        name = "istio";
        version = "1.20.0";
        type = "istio";
        namespace = "istio-system";
      };
      description = "Service mesh configuration";
    };

    sidecarInjection = {
      enable = mkEnableOption "Automatic sidecar injection";
      namespaces = mkOption {
        type = types.listOf types.str;
        default = [ "default" ];
        description = "Namespaces with automatic sidecar injection";
      };
      annotations = mkOption {
        type = types.attrsOf types.str;
        default = {
          "sidecar.istio.io/status" = "injected";
        };
        description = "Annotations for injected pods";
      };
    };

    trafficManagement = {
      virtualServices = mkOption {
        type = types.listOf virtualServiceType;
        default = [ ];
        description = "Virtual service definitions";
      };

      destinationRules = mkOption {
        type = types.listOf destinationRuleType;
        default = [ ];
        description = "Destination rule definitions";
      };

      gateways = mkOption {
        type = types.listOf (
          types.submodule {
            options = {
              name = mkOption { type = types.str; };
              selector = mkOption {
                type = types.attrsOf types.str;
                default = {
                  istio = "ingressgateway";
                };
              };
              servers = mkOption {
                type = types.listOf (
                  types.submodule {
                    options = {
                      port = mkOption { type = types.int; };
                      name = mkOption { type = types.str; };
                      hosts = mkOption { type = types.listOf types.str; };
                    };
                  }
                );
                default = [ ];
              };
            };
          }
        );
        default = [ ];
        description = "Gateway definitions";
      };
    };

    security = {
      peerAuthentication = mkOption {
        type = types.listOf (
          types.submodule {
            options = {
              name = mkOption { type = types.str; };
              selector = mkOption {
                type = types.attrsOf types.str;
                default = { };
              };
              mtls = mkOption {
                type = types.enum [
                  "STRICT"
                  "PERMISSIVE"
                  "DISABLE"
                ];
                default = "STRICT";
              };
            };
          }
        );
        default = [ ];
        description = "Peer authentication policies";
      };

      authorizationPolicies = mkOption {
        type = types.listOf (
          types.submodule {
            options = {
              name = mkOption { type = types.str; };
              selector = mkOption {
                type = types.attrsOf types.str;
                default = { };
              };
              action = mkOption {
                type = types.enum [
                  "ALLOW"
                  "DENY"
                ];
                default = "ALLOW";
              };
              rules = mkOption {
                type = types.listOf (
                  types.submodule {
                    options = {
                      from = mkOption {
                        type = types.listOf (
                          types.submodule {
                            options = {
                              source = mkOption {
                                type = types.submodule {
                                  options = {
                                    principals = mkOption {
                                      type = types.listOf types.str;
                                      default = [ ];
                                    };
                                  };
                                };
                              };
                            };
                          }
                        );
                        default = [ ];
                      };
                      to = mkOption {
                        type = types.listOf (
                          types.submodule {
                            options = {
                              operation = mkOption {
                                type = types.submodule {
                                  options = {
                                    methods = mkOption {
                                      type = types.listOf types.str;
                                      default = [ ];
                                    };
                                  };
                                };
                              };
                            };
                          }
                        );
                        default = [ ];
                      };
                    };
                  }
                );
                default = [ ];
              };
            };
          }
        );
        default = [ ];
        description = "Authorization policies";
      };
    };

    observability = {
      enable = mkEnableOption "Service mesh observability";

      tracing = {
        enable = mkEnableOption "Distributed tracing integration";
        sampling = mkOption {
          type = types.float;
          default = 0.1;
          description = "Trace sampling rate";
        };
      };

      metrics = {
        enable = mkEnableOption "Metrics collection";
        prometheus = mkEnableOption "Prometheus integration";
      };
    };

    integration = {
      tracing = mkEnableOption "Integration with gateway tracing";
      monitoring = mkEnableOption "Integration with gateway monitoring";
      zeroTrust = mkEnableOption "Integration with zero trust security";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    # Istio control plane deployment
    (mkIf (cfg.mesh.type == "istio") {
      # Istio base installation
      services.kubernetes.addons.istio = {
        enable = true;
        version = cfg.mesh.version;
        namespace = cfg.mesh.namespace;

        # Istio operator configuration
        operator = {
          enable = true;
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
              };
              pilot = {
                traceSampling = cfg.observability.tracing.sampling * 100;
              };
            };
          };
        };
      };

      # Generate Istio manifests
      environment.etc."istio/manifests" = {
        source = istioConfig.generateIstioManifests cfg;
      };
    })

    # Sidecar injection configuration
    (mkIf cfg.sidecarInjection.enable {
      services.kubernetes.addons.istio-injection = {
        enable = true;
        namespaces = cfg.sidecarInjection.namespaces;
        annotations = cfg.sidecarInjection.annotations;
      };
    })

    # Traffic management resources
    {
      environment.etc."istio/traffic-management" = {
        source = istioConfig.generateTrafficManagement cfg.trafficManagement;
      };
    }

    # Security policies
    {
      environment.etc."istio/security" = {
        source = istioPolicies.generateSecurityPolicies cfg.security;
      };
    }

    # Observability integration
    (mkIf cfg.observability.enable {
      # Prometheus integration
      services.prometheus = mkIf cfg.observability.metrics.prometheus {
        enable = true;
        scrapeConfigs = [
          {
            job_name = "istio-mesh";
            kubernetes_sd_configs = [
              {
                role = "endpoints";
                namespaces = {
                  names = [ cfg.mesh.namespace ];
                };
              }
            ];
            relabel_configs = [
              {
                source_labels = [ "__meta_kubernetes_service_annotation_prometheus_io_scrape" ];
                regex = "true";
                action = "keep";
              }
            ];
          }
        ];
      };

      # Grafana dashboards
      services.grafana = {
        enable = true;
        provision = {
          dashboards = [
            {
              name = "istio";
              options.path = istioConfig.generateGrafanaDashboards;
            }
          ];
        };
      };
    })

    # Integration with existing gateway services
    (mkIf cfg.integration.tracing {
      services.gateway.tracing = {
        enable = mkDefault true;
        collector.endpoint = "http://istiod.${cfg.mesh.namespace}:15014";
      };
    })

    (mkIf cfg.integration.monitoring {
      services.gateway.monitoring = {
        enable = mkDefault true;
        exporters = {
          istio = {
            enable = true;
            port = 15090;
          };
        };
      };
    })

    (mkIf cfg.integration.zeroTrust {
      services.gateway.zeroTrust = {
        enable = mkDefault true;
        meshIntegration = {
          enable = true;
          namespace = cfg.mesh.namespace;
        };
      };
    })

    # Service mesh testing framework
    {
      services.gateway.serviceMeshCompatibility = {
        enable = true;
        framework.meshes = [
          {
            name = cfg.mesh.name;
            version = cfg.mesh.version;
            type = if cfg.mesh.type == "istio" then "envoy-proxy" else "rust-proxy";
            components = [
              "control-plane"
              "data-plane"
              "ingress"
              "egress"
            ];
            features = [
              "mTLS"
              "traffic-management"
              "observability"
            ];
          }
        ];

        testScenarios = [
          {
            name = "basic-connectivity";
            mesh = cfg.mesh.name;
            description = "Test basic service-to-service connectivity through mesh";
          }
          {
            name = "mutual-tls";
            mesh = cfg.mesh.name;
            description = "Verify mTLS encryption between services";
          }
          {
            name = "traffic-routing";
            mesh = cfg.mesh.name;
            description = "Test intelligent traffic routing and load balancing";
          }
          {
            name = "observability";
            mesh = cfg.mesh.name;
            description = "Verify metrics, logs, and traces collection";
          }
        ];
      };
    }
  ]);
}

# Container Network Policies

**Status: Pending**

## Description
Implement container network policy testing to validate gateway functionality in containerized environments.

## Requirements

### Current State
- No container testing
- Limited container validation
- No network policy testing

### Improvements Needed

#### 1. Container Testing Framework
- Multi-container orchestration
- Network policy validation
- Service mesh testing
- Container security testing

#### 2. Network Policy Scenarios
- Policy enforcement validation
- Traffic control testing
- Isolation verification
- Service discovery testing

#### 3. Container Integration
- Kubernetes integration
- Docker Compose testing
- Service mesh validation
- Container networking

#### 4. Security and Compliance
- Container security scanning
- Network policy compliance
- Runtime security testing
- Image vulnerability scanning

## Implementation Details

### Files to Create
- `tests/container-network-policies.nix` - Container network policy tests
- `lib/container-tester.nix` - Container testing utilities

### Container Network Policies Configuration
```nix
services.gateway.containerNetworkPolicies = {
  enable = true;
  
  framework = {
    orchestration = {
      type: "kubernetes";
      
      cluster = {
        name: "test-cluster";
        namespace: "gateway-tests";
        
        nodes = [
          {
            name: "test-node-1";
            role: "control-plane";
            resources = {
              cpu: "2";
              memory: "4GB";
            };
          }
          {
            name: "test-node-2";
            role: "worker";
            resources = {
              cpu: "4";
              memory: "8GB";
            };
          }
          {
            name: "test-node-3";
            role: "worker";
            resources = {
              cpu: "4";
              memory: "8GB";
            };
          }
        ];
      };
      
      networking = {
        type: "calico";
        
        policies = {
          enable = true;
          
          default = {
            type: "deny-all";
            description: "Deny all traffic by default";
          };
          
          gateway = {
            type: "allow-gateway";
            description: "Allow gateway traffic";
            rules = [
              {
                from: ["gateway-pod"];
                to: ["any"];
                ports: [53, 67, 80, 443];
              }
            ];
          };
        };
      };
    };
    
    containers = {
      gateway = {
        name: "gateway-container";
        image: "gateway:latest";
        
        resources = {
          requests = {
            cpu: "1";
            memory: "2GB";
          };
          limits = {
            cpu: "2";
            memory: "4GB";
          };
        };
        
        networking = {
          hostNetwork: true;
          dnsPolicy: "ClusterFirstWithHostNet";
        };
        
        security = {
          runAsUser: 0;
          runAsGroup: 0;
          privileged: true;
        };
      };
      
      test = {
        name: "test-container";
        image: "network-test:latest";
        
        resources = {
          requests = {
            cpu: "0.5";
            memory: "512MB";
          };
          limits = {
            cpu: "1";
            memory: "1GB";
          };
        };
        
        networking = {
          hostNetwork: false;
          dnsPolicy: "ClusterFirst";
        };
        
        security = {
          runAsUser: 1000;
          runAsGroup: 1000;
          privileged: false;
        };
      };
    };
    
    serviceMesh = {
      enable = true;
      
      type: "istio";
      
      components = [
        {
          name: "ingress-gateway";
          type: "gateway";
          ports: [80, 443];
        }
        {
          name: "egress-gateway";
          type: "gateway";
          hosts: ["*"];
        }
        {
          name: "sidecar";
          type: "proxy";
          containers: ["gateway"];
        }
      ];
      
      policies = {
        enable = true;
        
        authentication = {
          enable = true;
          type: "mtls";
        };
        
        authorization = {
          enable = true;
          type: "rbac";
        };
        
        traffic = {
          enable = true;
          type: "mTLS";
        };
      };
    };
  };
  
  networkPolicies = [
    {
      name: "gateway-access";
      description: "Policy for gateway access";
      namespace: "gateway-tests";
      
      podSelector = {
        matchLabels = {
          app: "gateway";
        };
      };
      
      policyTypes = ["Ingress", "Egress"];
      
      ingress = [
        {
          from = [
            {
              namespaceSelector: {
                matchLabels = {
                  name: "kube-system";
                };
              };
            }
          ];
          ports = [
            { protocol: TCP; port: 53; }
            { protocol: UDP; port: 53; }
            { protocol: UDP; port: 67; }
          ];
        }
      ];
      
      egress = [
        {
          to = [];
          ports = [
            { protocol: TCP; port: 53; }
            { protocol: UDP; port: 53; }
            { protocol: UDP; port: 67; }
            { protocol: TCP; port: 80; }
            { protocol: TCP; port: 443; }
          ];
        }
      ];
    }
    {
      name: "test-traffic";
      description: "Policy for test traffic";
      namespace: "gateway-tests";
      
      podSelector = {
        matchLabels = {
          app: "test";
        };
      };
      
      policyTypes = ["Ingress", "Egress"];
      
      ingress = [
        {
          from = [
            {
              podSelector: {
                matchLabels = {
                  app: "gateway";
                };
              };
            }
          ];
          ports = [
            { protocol: TCP; port: 80; }
            { protocol: TCP; port: 443; }
          ];
        }
      ];
      
      egress = [
        {
          to = [
            {
              podSelector: {
                matchLabels = {
                  app: "gateway";
                };
              };
            }
          ];
          ports = [
            { protocol: TCP; port: 53; }
            { protocol: UDP; port: 53; }
          ];
        }
      ];
    }
    {
      name: "deny-all";
      description: "Default deny all policy";
      namespace: "gateway-tests";
      
      podSelector = {};
      
      policyTypes = ["Ingress", "Egress"];
      
      ingress = [];
      egress = [];
    }
  ];
  
  testScenarios = [
    {
      name: "policy-enforcement";
      description: "Test network policy enforcement";
      duration: "30m";
      
      tests = [
        {
          name: "allowed-traffic";
          description: "Test allowed traffic flows";
          validation = {
            type: "connectivity";
            from: "test-pod";
            to: "gateway-pod";
            ports: [53, 80, 443];
            expected: "success";
          };
        }
        {
          name: "denied-traffic";
          description: "Test denied traffic flows";
          validation = {
            type: "connectivity";
            from: "test-pod";
            to: "external-pod";
            ports: [22, 3306];
            expected: "denied";
          };
        }
        {
          name: "policy-compliance";
          description: "Verify policy compliance";
          validation = {
            type: "policy-check";
            policies: ["gateway-access", "test-traffic"];
            expected: "enforced";
          };
        }
      ];
    }
    {
      name: "service-mesh";
      description: "Test service mesh functionality";
      duration: "45m";
      
      tests = [
        {
          name: "mtls-communication";
          description: "Test mTLS communication";
          validation = {
            type: "tls-handshake";
            from: "test-pod";
            to: "gateway-pod";
            expected: "success";
          };
        }
        {
          name: "traffic-routing";
          description: "Test traffic routing through mesh";
          validation = {
            type: "routing";
            from: "test-pod";
            to: "gateway-pod";
            expected: "mesh-routed";
          };
        }
        {
          name: "observability";
          description: "Test mesh observability";
          validation = {
            type: "metrics";
            components: ["ingress", "egress", "sidecar"];
            expected: "metrics-available";
          };
        }
      ];
    }
    {
      name: "container-networking";
      description: "Test container networking";
      duration: "30m";
      
      tests = [
        {
          name: "dns-resolution";
          description: "Test DNS resolution in containers";
          validation = {
            type: "dns-query";
            from: "test-pod";
            target: "gateway-pod";
            expected: "resolution";
          };
        }
        {
          name: "service-discovery";
          description: "Test service discovery";
          validation = {
            type: "service-discovery";
            service: "gateway";
            expected: "discovered";
          };
        }
        {
          name: "load-balancing";
          description: "Test load balancing to gateway";
          validation = {
            type: "load-distribution";
            from: "test-pods";
            to: "gateway-pod";
            expected: "balanced";
          };
        }
      ];
    }
    {
      name: "security-policies";
      description: "Test security policy enforcement";
      duration: "30m";
      
      tests = [
        {
          name: "pod-security";
          description: "Test pod security policies";
          validation = {
            type: "security-check";
            policies: ["privileged", "runAsUser", "capabilities"];
            expected: "enforced";
          };
        }
        {
          name: "network-segmentation";
          description: "Test network segmentation";
          validation = {
            type: "isolation";
            namespaces: ["gateway-tests", "default"];
            expected: "isolated";
          };
        }
        {
          name: "egress-control";
          description: "Test egress traffic control";
          validation = {
            type: "egress-filtering";
            from: "test-pod";
            destinations: ["external"];
            expected: "controlled";
          };
        }
      ];
    }
  ];
  
  security = {
    scanning = {
      enable = true;
      
      images = [
        {
          name: "gateway-image";
          image: "gateway:latest";
          scanner: "trivy";
          
          severity = ["HIGH", "CRITICAL"];
          ignoreUnfixed: false;
        }
        {
          name: "test-image";
          image: "network-test:latest";
          scanner: "trivy";
          
          severity = ["MEDIUM", "HIGH", "CRITICAL"];
          ignoreUnfixed: false;
        }
      ];
      
      runtime = {
        enable = true;
        
        tools = [
          {
            name: "falco";
            type: "behavioral";
            rules: ["default", "custom"];
          }
          {
            name: "opa-gatekeeper";
            type: "policy";
            policies: ["pod-security", "network-policy"];
          }
        ];
      };
    };
    
    compliance = {
      enable = true;
      
      frameworks = [
        {
          name: "pod-security";
          version: "v1.29";
          policies: ["privileged", "capabilities", "seccomp"];
        }
        {
          name: "network-policy";
          version: "v1.5";
          policies: ["ingress", "egress", "port-range"];
        }
        {
          name: "cis-kubernetes";
          version: "1.7";
          policies: ["master-node", "worker-node", "policies"];
        }
      ];
    };
  };
  
  monitoring = {
    enable = true;
    
    metrics = [
      {
        name: "policy-violations";
        source: "gatekeeper";
        description: "Network policy violations";
      }
      {
        name: "container-security";
        source: "falco";
        description: "Container security events";
      }
      {
        name: "network-traffic";
        source: "calico";
        description: "Container network traffic";
      }
      {
        name: "service-mesh";
        source: "istio";
        description: "Service mesh metrics";
      }
    ];
    
    dashboards = {
      enable = true;
      
      panels = [
        {
          title: "Policy Status";
          type: "summary";
          metrics: ["policy-violations", "compliance-status"];
        }
        {
          title: "Network Traffic";
          type: "chart";
          metrics: ["ingress-traffic", "egress-traffic"];
        }
        {
          title: "Security Events";
          type: "table";
          metrics: ["security-alerts", "violations"];
        }
        {
          title: "Service Mesh";
          type: "topology";
          metrics: ["mesh-status", "traffic-flow"];
        }
      ];
    };
  };
  
  automation = {
    deployment = {
      enable = true;
      
      method = "helm";
      
      charts = [
        {
          name: "gateway";
          repository: "gateway-charts";
          version: "latest";
          
          values = {
            gateway: {
              image: "gateway:latest";
              resources: {
                requests: { cpu: "1", memory: "2GB"; };
                limits: { cpu: "2", memory: "4GB"; };
              };
            };
          };
        }
        {
          name: "test-suite";
          repository: "test-charts";
          version: "latest";
          
          values = {
            test: {
              image: "network-test:latest";
              resources: {
                requests: { cpu: "0.5", memory: "512MB"; };
                limits: { cpu: "1", memory: "1GB"; };
              };
            };
          };
        }
      ];
    };
    
    testing = {
      enable = true;
      
      triggers = [
        {
          name: "on-deployment";
          condition: "deployment.complete";
          scenarios: ["policy-enforcement", "service-mesh"];
        }
        {
          name: "scheduled";
          condition: "cron.daily";
          scenarios: ["all"];
        }
        {
          name: "on-policy-change";
          condition: "policy.change";
          scenarios: ["security-policies"];
        }
      ];
    };
  };
};
```

### Integration Points
- Kubernetes orchestration
- Service mesh (Istio)
- Container security tools
- Network policy enforcement

## Testing Requirements
- Policy enforcement validation
- Service mesh functionality tests
- Security scanning accuracy
- Container networking tests

## Dependencies
- 43-security-penetration-testing
- 44-multi-node-integration-tests

## Estimated Effort
- High (complex container testing)
- 6 weeks implementation
- 4 weeks testing

## Success Criteria
- Comprehensive policy testing
- Accurate security validation
- Effective service mesh testing
- Good container integration
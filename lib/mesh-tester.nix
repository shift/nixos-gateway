{ lib, pkgs, ... }:

let
  inherit (lib) mkOption types;

  # Service Mesh types and helpers
  meshTypes = {
    envoyProxy = "envoy-proxy";
    rustProxy = "rust-proxy";
  };

  # Validate mesh configuration structure
  validateMeshConfig =
    mesh:
    assert mesh ? name && mesh ? version && mesh ? type;
    assert lib.elem mesh.type (lib.attrValues meshTypes);
    true;

  # Helper to create mesh test scenarios
  mkMeshScenario =
    {
      name,
      mesh,
      duration ? "30m",
      steps,
    }:
    {
      inherit
        name
        mesh
        duration
        steps
        ;
      type = "mesh-scenario";
    };

  # Helper to validate mesh deployment
  validateDeployment =
    {
      components,
      expected ? "ready",
    }:
    {
      type = "deployment-status";
      inherit components expected;
    };

in
{
  inherit
    meshTypes
    validateMeshConfig
    mkMeshScenario
    validateDeployment
    ;

  # Service Mesh Testing Utilities

  # Generate k8s manifest for mesh deployment
  generateMeshManifest =
    {
      name,
      version,
      type,
      config ? { },
    }:
    {
      apiVersion = "v1";
      kind = "ConfigMap";
      metadata = {
        name = "mesh-config-${name}";
        namespace = "gateway-mesh-tests";
      };
      data = {
        "mesh-config.yaml" = builtins.toJSON {
          inherit
            name
            version
            type
            config
            ;
        };
      };
    };

  # Generate test workload manifest
  generateWorkloadManifest =
    {
      name,
      sidecar ? true,
      labels ? { },
    }:
    {
      apiVersion = "apps/v1";
      kind = "Deployment";
      metadata = {
        inherit name;
        labels = labels // {
          app = name;
          "sidecar.istio.io/inject" = if sidecar then "true" else "false";
        };
      };
      spec = {
        replicas = 1;
        selector.matchLabels.app = name;
        template = {
          metadata.labels.app = name;
          spec.containers = [
            {
              name = name;
              image = "alpine";
              command = [
                "sleep"
                "infinity"
              ];
            }
          ];
        };
      };
    };

  # Validation helpers for different mesh features
  validators = {
    traffic =
      {
        from,
        to,
        expected,
      }:
      {
        type = "traffic-test";
        inherit from to expected;
      };

    security =
      {
        from,
        to,
        expected,
        protocol ? "http",
      }:
      {
        type = "security-test";
        inherit
          from
          to
          expected
          protocol
          ;
      };

    observability =
      { service, metricType }:
      {
        type = "observability-test";
        inherit service metricType;
      };
  };
}

{ lib, pkgs, ... }:

let
  inherit (lib) mkOption types;

  # Network Policy types and helpers
  policyTypes = {
    ingress = "Ingress";
    egress = "Egress";
  };

  # Helper to create policy test scenarios
  mkPolicyScenario =
    {
      name,
      namespaces,
      policies,
      validation,
      ...
    }:
    {
      inherit
        name
        namespaces
        policies
        validation
        ;
      type = "policy-scenario";
    };

  # Generate K8s NetworkPolicy manifest
  generateNetworkPolicy =
    {
      name,
      namespace,
      spec,
    }:
    {
      apiVersion = "networking.k8s.io/v1";
      kind = "NetworkPolicy";
      metadata = {
        inherit name namespace;
      };
      inherit spec;
    };

  # Helpers for validation
  validators = {
    connectivity =
      {
        from,
        to,
        expected,
      }:
      {
        type = "connectivity-test";
        inherit from to expected;
      };

    dns =
      {
        from,
        target,
        expected,
      }:
      {
        type = "dns-test";
        inherit from target expected;
      };
  };

in
{
  inherit
    policyTypes
    mkPolicyScenario
    generateNetworkPolicy
    validators
    ;

  # Test Helper Functions

  # Generate Pod manifest for testing
  generateTestPod =
    {
      name,
      namespace,
      labels ? { },
    }:
    {
      apiVersion = "v1";
      kind = "Pod";
      metadata = {
        inherit name namespace;
        inherit labels;
      };
      spec = {
        containers = [
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

  # Generate Namespace manifest
  generateNamespace =
    {
      name,
      labels ? { },
    }:
    {
      apiVersion = "v1";
      kind = "Namespace";
      metadata = {
        inherit name labels;
      };
    };
}

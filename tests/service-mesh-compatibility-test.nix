{ pkgs, lib, ... }:

let
  meshTester = import ../lib/mesh-tester.nix { inherit lib pkgs; };

  mockMeshConfig = {
    enable = true;
    framework = {
      meshes = [
        {
          name = "istio";
          version = "1.19";
          type = "envoy-proxy";
          components = [
            "pilot"
            "proxy"
          ];
          features = [
            "traffic-management"
            "security"
          ];
        }
        {
          name = "linkerd";
          version = "2.12";
          type = "rust-proxy";
          components = [
            "controller"
            "proxy"
          ];
          features = [
            "observability"
            "security"
          ];
        }
      ];
      testing.type = "kubernetes";
    };

    testScenarios = [
      {
        name = "mesh-deployment";
        description = "Test basic deployment";
        mesh = "istio";
        steps = [
          {
            name = "verify-components";
            validation = {
              type = "deployment-status";
              components = [ "pilot" ];
              expected = "ready";
            };
          }
        ];
      }
    ];
  };

in
{
  name = "service-mesh-compatibility-test";

  nodes = {
    gateway =
      { config, pkgs, ... }:
      {
        imports = [
          ../modules/service-mesh-compatibility.nix
        ];

        services.gateway.serviceMeshCompatibility = mockMeshConfig;
      };
  };

  testScript = ''
    start_all()

    # Wait for the system to settle
    gateway.wait_for_unit("multi-user.target")

    # Verify configuration file creation
    gateway.succeed("test -f /etc/systemd/system/mesh-compatibility-test.service")

    # Run the compatibility test service
    gateway.succeed("systemctl start mesh-compatibility-test.service")

    # Check results directory creation
    gateway.succeed("test -d /var/lib/mesh-test-results")

    # Verify log output format
    result = gateway.succeed("cat /var/lib/mesh-test-results/results.json")
    if "istio" not in result or "mesh-deployment" not in result:
        raise Exception("Test results do not contain expected mesh or scenario data")
        
    # Verify lib helper functions (unit testing the lib)
    # We can't directly call nix functions from python, but we can verify their effects
    # via the generated systemd script which uses them
  '';
}

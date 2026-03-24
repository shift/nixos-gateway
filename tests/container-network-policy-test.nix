{ pkgs, lib, ... }:

let
  policyTester = import ../lib/network-policy-tester.nix { inherit lib pkgs; };

  mockPolicyConfig = {
    enable = true;
    policyScenarios = [
      {
        name = "namespace-isolation";
        description = "Test namespace isolation";
        namespaces = [
          {
            name = "gateway";
            labels = {
              environment = "production";
            };
          }
          {
            name = "test";
            labels = {
              environment = "testing";
            };
          }
        ];
        policies = [
          {
            name = "deny-cross-namespace";
            namespace = "gateway";
            spec = {
              podSelector = { };
              policyTypes = [ "Ingress" ];
            };
          }
        ];
        validation = {
          tests = [
            {
              name = "test-isolation";
              validation = {
                type = "connectivity-test";
                expected = "denied";
              };
            }
          ];
        };
      }
    ];
  };

in
{
  name = "container-network-policy-test";

  nodes = {
    gateway =
      { config, pkgs, ... }:
      {
        imports = [
          ../modules/container-network-policies.nix
        ];

        services.gateway.containerNetworkPolicies = mockPolicyConfig;
      };
  };

  testScript = ''
    start_all()

    # Wait for the system to settle
    gateway.wait_for_unit("multi-user.target")

    # Verify configuration file creation
    gateway.succeed("test -f /etc/systemd/system/network-policy-test.service")

    # Run the policy test service
    gateway.succeed("systemctl start network-policy-test.service")

    # Check results directory creation
    gateway.succeed("test -d /var/lib/network-policy-results")

    # Verify log output format
    result = gateway.succeed("cat /var/lib/network-policy-results/results.json")
    if "namespace-isolation" not in result or "SUCCESS" not in result:
        raise Exception("Test results do not contain expected scenario data")
  '';
}

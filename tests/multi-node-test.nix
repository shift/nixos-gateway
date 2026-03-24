{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "multi-node-test";
  commonConfig =
    { config, pkgs, ... }:
    {
      imports = [
        ../modules/default.nix
        ../modules/multi-node-tests.nix
      ];

      # Enable the testing module but don't define scenarios globally yet
      services.gateway.multiNodeTests.enable = true;

      # Mock networking for the test environment
      networking.useDHCP = false;
      networking.firewall.enable = false;
      services.gateway.interfaces = {
        lan = "eth1";
        wan = "eth0";
      };
    };

in
pkgs.testers.runNixOSTest {
  name = "gateway-multi-node-integration";

  nodes = {
    # Primary Node (Coordinator)
    node1 =
      { config, pkgs, ... }:
      {
        imports = [ commonConfig ];
        networking.interfaces.eth1.ipv4.addresses = [
          {
            address = "192.168.1.1";
            prefixLength = 24;
          }
        ];

        services.gateway.multiNodeTests = {
          scenarios = [
            {
              name = "cluster-formation";
              description = "Test cluster formation and initialization";
              steps = [
                {
                  name = "deploy-nodes";
                  validation = {
                    type = "service-status";
                    expected = "running";
                    services = [ "gateway" ];
                  };
                }
                {
                  name = "cluster-discovery";
                  validation = {
                    type = "cluster-membership";
                    expected = "all-nodes";
                  };
                }
              ];
            }
            {
              name = "basic-failover";
              description = "Test simulated failover";
              steps = [
                {
                  name = "simulate-primary-failure";
                  action = {
                    type = "node-stop";
                    target = "node2";
                  }; # Simulation only
                }
                {
                  name = "verify-recovery";
                  validation = {
                    type = "service-health";
                    expected = "healthy";
                  };
                }
              ];
            }
          ];

          framework.orchestration.cluster.nodes = [
            {
              name = "node1";
              role = "primary";
            }
            {
              name = "node2";
              role = "secondary";
            }
            {
              name = "node3";
              role = "secondary";
            }
          ];
        };
      };

    # Secondary Node 1
    node2 =
      { config, pkgs, ... }:
      {
        imports = [ commonConfig ];
        networking.interfaces.eth1.ipv4.addresses = [
          {
            address = "192.168.1.2";
            prefixLength = 24;
          }
        ];
      };

    # Secondary Node 2
    node3 =
      { config, pkgs, ... }:
      {
        imports = [ commonConfig ];
        networking.interfaces.eth1.ipv4.addresses = [
          {
            address = "192.168.1.3";
            prefixLength = 24;
          }
        ];
      };
  };

  testScript = ''
    start_all()

    # Wait for networking
    node1.wait_for_unit("network.target")
    node2.wait_for_unit("network.target")
    node3.wait_for_unit("network.target")

    # Ensure they can see each other
    node1.succeed("ping -c 1 192.168.1.2")
    node1.succeed("ping -c 1 192.168.1.3")

    # Run the test suite on the primary node
    # This script simulates the orchestration of tests
    node1.succeed("gateway-multi-node-test >&2")

    # Verify report generation
    node1.succeed("ls -l /var/lib/gateway/multi-node-tests/report-*.json")

    # Verify content of the report contains success
    node1.succeed("grep '\"status\": \"passed\"' /var/lib/gateway/multi-node-tests/report-*.json")
  '';
}

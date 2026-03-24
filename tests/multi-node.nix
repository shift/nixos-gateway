{ pkgs, ... }:

{
  name = "multi-node-integration";

  nodes = {
    # Primary node
    node1 =
      {
        pkgs,
        config,
        lib,
        ...
      }:
      {
        imports = [ ../modules/default.nix ];
        services.gateway.data = {
          network = {
            subnets = [
              {
                name = "lan";
                gateway = "192.168.1.1";
                network = "192.168.1.0/24";
              }
            ];
            mgmtAddress = "192.168.1.1";
          };
        };
        services.gateway.enable = true;
        services.gateway.interfaces = {
          wan = "eth0";
          lan = "eth1";
          mgmt = "eth1";
        };

        networking.hostName = lib.mkForce "node1";
        networking.interfaces.eth1.ipv4.addresses = lib.mkForce [
          {
            address = "192.168.1.1";
            prefixLength = 24;
          }
        ];
        # Open firewall for checks
        networking.firewall.allowedTCPPorts = [
          80
          443
          2379
          8500
        ];

        environment.systemPackages = with pkgs; [ jq ];
      };

    # Secondary node
    node2 =
      {
        pkgs,
        config,
        lib,
        ...
      }:
      {
        imports = [ ../modules/default.nix ];
        services.gateway.data = {
          network = {
            subnets = [
              {
                name = "lan";
                gateway = "192.168.1.1";
                network = "192.168.1.0/24";
              }
            ];
            mgmtAddress = "192.168.1.2";
          };
        };
        services.gateway.enable = true;
        services.gateway.interfaces = {
          wan = "eth0";
          lan = "eth1";
          mgmt = "eth1";
        };

        networking.hostName = lib.mkForce "node2";
        networking.interfaces.eth1.ipv4.addresses = lib.mkForce [
          {
            address = "192.168.1.2";
            prefixLength = 24;
          }
        ];
        networking.firewall.allowedTCPPorts = [
          80
          443
          2379
          8500
        ];
      };

    # Test runner node (simulates external coordinator)
    coordinator =
      { pkgs, lib, ... }:
      {
        imports = [ ../modules/default.nix ];
        services.gateway.data = {
          network = {
            subnets = [
              {
                name = "lan";
                gateway = "192.168.1.1";
                network = "192.168.1.0/24";
              }
            ];
            mgmtAddress = "192.168.1.100";
          };
        };
        services.gateway.enable = true;
        services.gateway.interfaces = {
          wan = "eth0";
          lan = "eth1";
          mgmt = "eth1";
        };
        networking.hostName = lib.mkForce "coordinator";
        networking.interfaces.eth1.ipv4.addresses = [
          {
            address = "192.168.1.100";
            prefixLength = 24;
          }
        ];

        environment.systemPackages = with pkgs; [
          jq
          curl
          (pkgs.writeScriptBin "run-cluster-tests" (
            let
              clusterTester = import ../lib/cluster-tester.nix {
                inherit (pkgs) lib;
                inherit pkgs;
              };
            in
            clusterTester.mkClusterTestScript {
              nodes = [
                "node1"
                "node2"
              ];
              scenarios = [
                {
                  name = "cluster-formation";
                  description = "Verify nodes are reachable";
                  steps = [
                    {
                      name = "check-node1";
                      validation = {
                        type = "service-status";
                      };
                    }
                    {
                      name = "check-cluster";
                      validation = {
                        type = "cluster-membership";
                      };
                    }
                  ];
                }
              ];
            }
          ))
        ];
      };
  };

  testScript = ''
    start_all()

    # Wait for networking
    coordinator.wait_for_unit("network.target")
    node1.wait_for_unit("network.target")
    node2.wait_for_unit("network.target")

    # Ensure connectivity
    coordinator.succeed("ping -c 1 node1")
    coordinator.succeed("ping -c 1 node2")

    print("Running Cluster Integration Tests...")

    # Execute the generated test script on the coordinator
    output = coordinator.succeed("run-cluster-tests")
    print(output)

    # Verify report generation
    report = coordinator.succeed("cat /var/lib/gateway/multi-node-tests/report-*.json")

    # Use Python to validate JSON
    import json
    data = json.loads(report)

    assert len(data['results']) == 1, "Expected 1 scenario result"
    assert data['results'][0]['status'] == "passed", "Scenario failed"

    print("✅ Multi-node integration test passed successfully.")
  '';
}

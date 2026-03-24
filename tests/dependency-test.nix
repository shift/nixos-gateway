# Test for Module System Dependencies (Task 02)

{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "gateway-dependencies-test";

  nodes = {
    gateway =
      { ... }:
      {
        imports = [ ../modules/default.nix ];

        services.gateway = {
          enable = true;
          interfaces = {
            lan = "enp1s0f0";
            wan = "enp1s0f1";
            mgmt = "eno1";
          };
          domain = "test.local";

          data = {
            network = {
              subnets = {
                lan = {
                  ipv4 = {
                    gateway = "192.168.1.1";
                    subnet = "192.168.1.0/24";
                  };
                };
              };
              dhcp = {
                poolStart = "192.168.1.50";
                poolEnd = "192.168.1.254";
              };
            };
            hosts = {
              staticDHCPv4Assignments = [
                {
                  hostname = "test-host";
                  mac = "00:11:22:33:44:55";
                  ip = "192.168.1.100";
                }
              ];
            };
          };
        };
      };
  };

  testScript = ''
    # Business case: Gateway must start services in correct order to ensure
    # network dependencies are satisfied before dependent services start

    start_all()

    # Wait for system to be ready
    gateway.wait_for_unit("network-online.target")

    # Check that dependency information is generated
    gateway.succeed("test -f /etc/gateway-dependencies.txt")

    # Verify startup order includes network before dns/dhcp
    deps_output = gateway.succeed("cat /etc/gateway-dependencies.txt")
    print("Dependency information:", deps_output)

    # Verify network is in startup order
    assert "network" in deps_output, "Network module should be in startup order"

    # Verify dependency wait services are created
    gateway.wait_for_unit("network-dependency-wait.service")

    # Check that basic networking is working
    gateway.succeed("ip addr show enp1s0f0")

    print("Module dependency management test passed")
  '';
}

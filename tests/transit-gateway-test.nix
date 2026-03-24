{ pkgs, lib, ... }:

# Simplified smoke-test: verify the gateway module loads without errors.
# Full transit-gateway BGP/VRF testing requires a dedicated module that is
# not yet wired into services.gateway; runtime integration tests are tracked
# separately.
pkgs.testers.nixosTest {
  name = "transit-gateway-test";

  nodes.machine =
    { config, pkgs, ... }:
    {
      imports = [ ../modules ];

      services.gateway = {
        enable = true;
        interfaces = {
          lan = "eth1";
          wan = "eth0";
        };
        data = { };
      };
    };

  testScript = ''
    start_all()
    machine.wait_for_unit("network.target")
    print("transit-gateway smoke test passed")
  '';
}

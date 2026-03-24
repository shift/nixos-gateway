{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "ip-reputation-test";

  nodes.machine =
    { config, pkgs, ... }:
    {
      imports = [
        ../modules/ip-reputation.nix
        ../modules/threat-intel.nix
      ];

      # Enable Threat Intel to provide indicators
      services.gateway.threatIntel = {
        enable = true;
        feeds = {
          custom = [
            {
              name = "test-blocklist";
              type = "file";
              path = "/etc/threat-intel/blocklist.txt";
            }
          ];
        };
      };

      services.gateway.ipReputation = {
        enable = true;
      };

      # Mock Data
      environment.etc."threat-intel/blocklist.txt".text = ''
        192.0.2.100
        192.0.2.200
      '';
    };

  # Smoke test: verify the module loads and the system boots cleanly.
  # Full service tests will be added when ip-reputation-update/apply are implemented.
  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("echo 'ip-reputation module loaded successfully'")
  '';
}

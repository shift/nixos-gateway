# Ultra Minimal Working Test
# Basic test to verify test runner works without complex modules

{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "ultra-minimal-test";

  nodes = {
    gateway =
      { config, pkgs, ... }:
      {
        # Don't import modules to avoid complex dependencies
        # imports = [ ../modules ];

        # Simple test service
        systemd.services.test-service = {
          description = "Test Service";
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
          };
        };

        environment.systemPackages = with pkgs; [
          coreutils
        ];
      };
  };

  testScript = ''
    start_all()

    # Wait for services to start
    gateway.wait_for_unit("multi-user.target")
    gateway.sleep(5)

    # Test that test service is running
    gateway.succeed("systemctl is-active test-service")

    # Test basic functionality
    gateway.succeed("echo 'Ultra minimal test passed!'")

    print("✅ Ultra minimal test passed!")
  '';
}

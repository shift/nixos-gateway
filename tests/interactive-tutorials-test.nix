{ pkgs, lib, ... }:

let
  tutorialEngine = import ../lib/tutorial-engine.nix { inherit lib; };

  mockTutorial = {
    id = "test-tutorial";
    category = "test";
    title = "Test Tutorial";
    description = "A test tutorial";
    duration = "10m";
    difficulty = "beginner";
    steps = [
      {
        title = "Step 1";
        type = "content";
        content = "Test content";
      }
    ];
  };

in
pkgs.testers.runNixOSTest {
  name = "interactive-tutorials-test";

  nodes.machine =
    { config, pkgs, ... }:
    {
      imports = [
        ../modules/default.nix
        ../modules/ipv6.nix
      ];
      services.gateway.enable = true;
      services.gateway.interfaces = {
        lan = "eth1";
        wan = "eth0";
        mgmt = "eth2";
      };
      services.gateway.ipv6Prefix = "2001:db8::";
      services.gateway.tutorials.enable = true;
    };

  testScript = ''
    start_all()

    # Check if the tutorial script exists
    machine.succeed("which gateway-tutorial")

    # Check listing of tutorials
    output = machine.succeed("gateway-tutorial list")
    assert "basic-setup" in output
    assert "network-interfaces" in output
    assert "debug-techniques" in output

    # Run a tutorial (non-interactive mode for testing)
    machine.succeed("TUTORIAL_NON_INTERACTIVE=1 gateway-tutorial basic-setup")
  '';
}

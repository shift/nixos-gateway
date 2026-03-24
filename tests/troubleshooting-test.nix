{ pkgs, lib, ... }:

pkgs.testers.runNixOSTest {
  name = "task-40-troubleshooting-trees";

  nodes.machine =
    { config, pkgs, ... }:
    {
      imports = [ ../modules/default.nix ];
      services.gateway.enable = true;
       services.gateway.interfaces = {
         lan = "eth1";
         wan = "eth0";
         mgmt = "eth2";
       };
       services.gateway.troubleshooting.enable = true;

      # Enable networking tools for the checks
      environment.systemPackages = [
        pkgs.iproute2
        pkgs.iputils
        pkgs.dnsutils
      ];
    };

  testScript = ''
    start_all()

    # Verify CLI tool exists
    machine.succeed("which gateway-diagnose")

    # List available trees
    output = machine.succeed("gateway-diagnose list")
    assert "network-connectivity" in output

    # Run network connectivity check (should fail or pass depending on network state)
    # In the VM, external ping (8.8.8.8) usually fails due to sandbox, so we expect it to reach a result node.
    # We use DIAGNOSE_NON_INTERACTIVE to skip manual prompts.

    result = machine.succeed("DIAGNOSE_NON_INTERACTIVE=1 gateway-diagnose network-connectivity")
    print(result)

    # Ensure it ran through checks
    assert "Starting Troubleshooting" in result
    assert "Checking: Checking network interfaces" in result
    assert "Diagnosis Complete" in result
  '';
}

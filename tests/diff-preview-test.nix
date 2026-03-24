{ pkgs, ... }:

{
  name = "diff-preview-test";

  nodes.machine =
    { config, pkgs, ... }:
    {
      imports = [
        ../modules/dev-tools/diff-preview.nix
      ];

      services.gateway.configDiff.enable = true;

      # Some dummy config to test diffs against
      networking.hostName = "test-gateway";
      services.openssh.enable = true;
    };

  testScript = ''
    start_all()

    # 1. Test Config Dump
    machine.succeed("gateway-config-dump > /tmp/initial.json")
    machine.succeed("grep 'test-gateway' /tmp/initial.json")

    # 2. Test Snapshot
    machine.succeed("gateway-diff snapshot /tmp/snapshot.json")
    machine.succeed("diff /tmp/initial.json /tmp/snapshot.json")

    # 3. Test Comparison (No changes)
    machine.succeed("gateway-diff compare /tmp/snapshot.json /tmp/initial.json > /tmp/diff_none.txt")
    machine.succeed("grep 'No changes detected' /tmp/diff_none.txt")

    # 4. Test Comparison (With Simulated Changes)
    # We create a modified JSON manually since we can't easily change system config at runtime without rebuild
    # We modify the snapshot to simulate that the *old* config was different (e.g., SSH was disabled)

    machine.succeed("sed -i 's/\"enable\": true/\"enable\": false/' /tmp/snapshot.json")

    # Now compare modified snapshot (old=false) with current (new=true)
    machine.succeed("gateway-diff compare /tmp/snapshot.json current > /tmp/diff_change.txt")

    # Verify output contains expected changes and impact warnings
    machine.succeed("cat /tmp/diff_change.txt")
    machine.succeed("grep 'CHANGED: services.openssh.enable' /tmp/diff_change.txt")
    machine.succeed("grep 'SSH configuration changed' /tmp/diff_change.txt")
  '';
}

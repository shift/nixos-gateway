{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "drift-detection-test";
{
  name = "drift-detection-test";

  nodes.machine =
    { config, pkgs, ... }:
    {
      imports = [ ../modules/config-drift.nix ];

      services.gateway.configDrift = {
        enable = true;
        monitoring.realTime = {
          enable = true;
          paths = [ "/var/lib/monitored" ];
        };
      };

      # Prepare monitored directory
      # /etc is read-only in NixOS usually, but we can write to /etc if we don't use environment.etc for the specific file we want to mutate?
      # Or we use a different path. /var/lib is writable.

      # Let's switch to /var/lib/monitored for the test target
    };

  testScript = ''
    start_all()

    # Setup test directory in writable location
    machine.succeed("mkdir -p /var/lib/monitored")
    machine.succeed("echo 'original=state' > /var/lib/monitored/config.conf")

    # 1. Create Baseline
    # We trigger it manually since the auto-init ran before we created the file
    machine.succeed("drift-detector create-baseline")
    machine.wait_until_succeeds("test -f /var/lib/config-drift/baselines/current_baseline.json")

    # Debug: Check baseline content
    machine.succeed("cat /var/lib/config-drift/baselines/current_baseline.json >&2")

    # 2. Run Check (Should pass)
    machine.succeed("systemctl start drift-detection.service")
    machine.succeed("test ! -f /var/log/config-drift/report.json")

    # 3. Modify File (Simulate Drift)
    machine.succeed("echo 'modified=true' > /var/lib/monitored/config.conf")

    # Debug: Check file content
    machine.succeed("cat /var/lib/monitored/config.conf")

    # 4. Run Check (Should detect drift)
    machine.succeed("systemctl start drift-detection.service")

    # 5. Check Logs/Report
    machine.succeed("test -f /var/log/config-drift/report.json")
    machine.succeed("grep 'modified' /var/log/config-drift/report.json")

    # 6. Add New File
    machine.succeed("touch /var/lib/monitored/newfile.txt")
    machine.succeed("systemctl start drift-detection.service")
    machine.succeed("grep 'created' /var/log/config-drift/report.json")
  '';
}

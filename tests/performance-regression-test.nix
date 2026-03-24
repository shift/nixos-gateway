{ pkgs, lib, ... }:

{
  name = "performance-regression-test";

  nodes.machine =
    { config, pkgs, ... }:
    {
      imports = [
        ../modules/performance-regression.nix
      ];

      services.nixos-gateway.performance-regression = {
        enable = true;
        baselineFile = "/var/lib/nixos-gateway/baseline.json";
        currentFile = "/var/lib/nixos-gateway/report.json";
        thresholdPercent = 10;
      };
    };

  testScript = ''
    start_all()

    # Create dummy baseline and current report
    machine.succeed("mkdir -p /var/lib/nixos-gateway")

    # Scenario 1: No baseline (Should create it)
    machine.succeed("echo '{\"results\":{\"cpu\":{\"events_per_second\": 100}}}' > /var/lib/nixos-gateway/report.json")
    machine.succeed("systemctl start performance-regression-check.service")
    machine.succeed("test -f /var/lib/nixos-gateway/baseline.json")

    # Scenario 2: Good Performance (Should pass)
    # Baseline: 100, Current: 100 -> No change
    machine.succeed("systemctl start performance-regression-check.service")

    # Scenario 3: Better Performance (Should pass)
    # Baseline: 100, Current: 120 -> +20%
    machine.succeed("echo '{\"results\":{\"cpu\":{\"events_per_second\": 120}}}' > /var/lib/nixos-gateway/report.json")
    machine.succeed("systemctl start performance-regression-check.service")

    # Scenario 4: Slight Degradation within threshold (Should pass)
    # Baseline: 100, Current: 95 -> -5% (Threshold 10%)
    machine.succeed("echo '{\"results\":{\"cpu\":{\"events_per_second\": 95}}}' > /var/lib/nixos-gateway/report.json")
    machine.succeed("systemctl start performance-regression-check.service")

    # Scenario 5: Severe Degradation (Should fail)
    # Baseline: 100, Current: 80 -> -20% (Threshold 10%)
    machine.succeed("echo '{\"results\":{\"cpu\":{\"events_per_second\": 80}}}' > /var/lib/nixos-gateway/report.json")
    machine.fail("systemctl start performance-regression-check.service")

    # Scenario 6: Latency check (Lower is better)
    # Reset baseline for latency test
    machine.succeed("rm /var/lib/nixos-gateway/baseline.json")

    # Create baseline with Latency
    machine.succeed("echo '{\"results\":{\"network_loopback\":{\"bits_per_second\": 1000}}}' > /var/lib/nixos-gateway/report.json")
    # Note: Our script currently hardcodes check direction. 
    # network_loopback bits_per_second is "higher" is better.
    # Let's verify network_loopback regression.

    machine.succeed("systemctl start performance-regression-check.service") # Creates baseline

    # Degrade network
    machine.succeed("echo '{\"results\":{\"network_loopback\":{\"bits_per_second\": 500}}}' > /var/lib/nixos-gateway/report.json")
    machine.fail("systemctl start performance-regression-check.service")
  '';
}

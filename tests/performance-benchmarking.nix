{ pkgs, ... }:

{
  name = "performance-benchmarking-test";

  nodes.machine =
    { pkgs, ... }:
    {
      imports = [ ../modules/performance-benchmarking.nix ];

      environment.systemPackages = [ pkgs.jq ];

      services.nixos-gateway.benchmarking = {
        enable = true;
        enableSysbench = true;
        enableIperf = true;
        enableStress = true;
        outputFile = "/tmp/benchmark.json";
      };
    };

  testScript = ''
    start_all()

    # Wait for the system to settle
    machine.wait_for_unit("multi-user.target")

    # Start the benchmark service
    machine.succeed("systemctl start performance-benchmark.service")

    # Wait for the file to exist and be non-empty
    machine.wait_for_file("/tmp/benchmark.json")

    # Check content
    result = machine.succeed("cat /tmp/benchmark.json")
    print(result)

    # Validate JSON structure using jq
    machine.succeed("jq -e '.results.cpu.events_per_second' /tmp/benchmark.json")
    machine.succeed("jq -e '.results.memory.total_operations' /tmp/benchmark.json")
    machine.succeed("jq -e '.results.network_loopback.bits_per_second' /tmp/benchmark.json")
    machine.succeed("jq -e '.results.stress.bogops' /tmp/benchmark.json")
  '';
}

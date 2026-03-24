{ pkgs, ... }:

{
  name = "hardware-testing-comprehensive";

  nodes.machine =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    {
      imports = [ ../modules/hardware-testing.nix ];

      # Enable hardware testing module
      services.gateway.hardwareTesting = {
        enable = true;
        platforms = [
          {
            name = "vm-x86_64";
            description = "Virtual Machine Test Platform";
            architecture = "x86_64";
            cpuVendor = "Unknown"; # In QEMU it varies
            testSuites = [
              "basicFunctionality"
              "performanceBenchmarks"
            ];
            hardware = {
              cpu = {
                features = [ ];
                minCores = 1;
                minFrequency = "1GHz";
              };
              network = {
                vendors = [ ];
                features = [ ];
              };
              storage = {
                types = [ ];
                minSpeed = "100MB/s";
              };
            };
          }
        ];

        testSuites = {
          basicFunctionality = {
            description = "Basic Functionality";
            tests = [
              {
                name = "service-startup";
                validation = {
                  type = "service-status";
                  services = [ "dbus" ];
                }; # dbus is always there
              }
            ];
          };
          performanceBenchmarks = {
            description = "Performance Benchmarks";
            benchmarks = [
              {
                name = "cpu-performance";
                tool = "sysbench";
                parameters = {
                  test = "cpu";
                };
              }
            ];
          };
        };
      };

      environment.systemPackages = with pkgs; [
        jq
        sysbench
      ];
    };

  testScript = ''
    start_all()

    machine.wait_for_unit("multi-user.target")

    print("Running Hardware Test Script...")

    # Execute the generated hardware test script
    # The module should expose a way to run it, typically via a bin script or service
    # Based on module implementation (assumed), it might be 'gateway-hardware-test'

    output = machine.succeed("gateway-hardware-test")
    print(output)

    # Verify report generation
    report_file = machine.succeed("ls /var/lib/gateway/hardware-tests/report-*.json | head -n 1").strip()

    # Validate JSON
    machine.succeed(f"${pkgs.jq}/bin/jq . {report_file}")

    # Verify test results
    # We expect 2 results: 1 from basicFunctionality, 1 from performanceBenchmarks
    count = machine.succeed(f"${pkgs.jq}/bin/jq '.results | length' {report_file}").strip()
    if int(count) != 2:
        raise Exception(f"Expected 2 test results, got {count}")
        
    print("✅ Hardware testing framework validated successfully.")
  '';
}

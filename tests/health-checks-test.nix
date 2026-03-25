{ pkgs, lib, ... }:

let
  healthChecksLib = import ../lib/health-checks.nix { inherit lib; };

  # Generate a script that exercises the Prometheus warn-and-continue path
  # (Prometheus not running → curl fails → script still exits 0)
  promCheckScript = healthChecksLib.generateHealthCheckScript {
    type = "metric";
    source = "prometheus";
    metric = "node_load1";
    operator = "lt";
    threshold = 100;
    prometheusUrl = "http://localhost:9090";
  };

  # Generate a script that exercises the kea-ctrl-agent warn-and-continue path
  dhcpCheckScript = healthChecksLib.generateHealthCheckScript {
    type = "dhcp-server";
    interface = "eth1";
    poolUtilization = { poolSize = 100; threshold = "0.9"; };
  };

in
pkgs.testers.nixosTest {
  name = "health-checks-test";

  nodes = {
    gateway =
      { config, pkgs, ... }:
      {
        imports = [ ../modules ];

        services.gateway = {
          enable = true;
          interfaces = {
            wan = "eth0";
            lan = "eth1";
          };
        };

        # Install curl + jq + dhcping so the generated scripts can run
        environment.systemPackages = with pkgs; [ curl jq dhcping bc ];

        # Write the generated scripts into the VM at a known path
        environment.etc."health-check-tests/prom-check.sh".text = ''
          #!/bin/sh
          ${promCheckScript}
        '';
        environment.etc."health-check-tests/dhcp-pool-check.sh".text = ''
          #!/bin/sh
          ${dhcpCheckScript}
        '';
      };
  };

  testScript = ''
    start_all()
    gateway.wait_for_unit("multi-user.target")

    # Prometheus warn-and-continue: Prometheus not running → curl fails → exit 0
    gateway.succeed("chmod +x /etc/health-check-tests/prom-check.sh")
    output = gateway.succeed("/etc/health-check-tests/prom-check.sh 2>&1")
    assert "unreachable" in output or "WARNING" in output, \
      f"Expected Prometheus unreachable warning, got: {output}"

    # kea-ctrl-agent warn-and-continue: kea not running → curl fails → exit 0
    gateway.succeed("chmod +x /etc/health-check-tests/dhcp-pool-check.sh")
    output = gateway.succeed("/etc/health-check-tests/dhcp-pool-check.sh 2>&1")
    assert "kea-ctrl-agent unreachable" in output, \
      f"Expected kea-ctrl-agent unreachable warning, got: {output}"

    print("Health checks integration test passed!")
  '';
}

{ pkgs, lib, ... }:

pkgs.testers.runNixOSTest {
  name = "distributed-tracing-test";
  nodes.machine =
    { config, pkgs, ... }:
    {
      imports = [ ../modules/default.nix ];

      config = {
        # Mock required options
        services.gateway.enable = true;
        services.gateway.interfaces = {
          lan = "eth1";
          wan = "eth0";
          mgmt = "eth2"; # Ensure mgmt interface is defined
        };

        services.gateway.tracing = {
          enable = true;
          collector = {
            endpoint = "http://jaeger:14268/api/traces";
            sampling.strategy = "probabilistic";
            sampling.probability = 0.5;
            sampling.serviceOverrides = {
              dns = {
                probability = 0.1;
              };
            };
          };
          services = {
            dns = {
              enable = true;
              spans = {
                "query-resolution" = {
                  operations = [
                    "resolve"
                    "forward"
                  ];
                  attributes = [ "query.name" ];
                };
              };
            };
          };
          integration.jaeger.enable = true;
        };
      };
    };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    # Check if config file is generated
    machine.succeed("test -f /etc/otel/config.yaml")

    # Validate content of the generated config
    config_content = machine.succeed("cat /etc/otel/config.yaml")

    # Check if key configurations are present (simple string match)
    assert "http://jaeger:14268/api/traces" in config_content
    assert "sampling_percentage: 50" in config_content

    # Check service unit
    machine.succeed("systemctl cat otel-collector.service | grep 'ExecStart=.*otelcol-contrib'")
  '';
}

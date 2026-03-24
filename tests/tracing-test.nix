{ pkgs, ... }:

let
  # Import the module
  tracingModule = import ../modules/tracing/default.nix;
in
{
  name = "distributed-tracing-test";

  nodes = {
    gateway =
      { config, pkgs, ... }:
      {
        imports = [ tracingModule ];

        services.gateway.tracing = {
          enable = true;

          collector = {
            endpoint = "jaeger:14268";
            sampling.probability = 1.0; # Sample everything for tests
          };

          services = {
            dns = {
              enable = true;
              spans."query-resolution" = {
                operations = [ "resolve" ];
                attributes = [ "query.name" ];
              };
            };
          };

          integration.jaeger.enable = true;
        };

        # Mock packages if not available
        nixpkgs.overlays = [
          (self: super: {
            opentelemetry-collector-contrib = super.runCommand "mock-otel" { } ''
              mkdir -p $out/bin
              echo "#!/bin/sh" > $out/bin/otelcol-contrib
              echo "echo 'Starting Mock Otel Collector'" >> $out/bin/otelcol-contrib
              echo "while true; do sleep 1; done" >> $out/bin/otelcol-contrib
              chmod +x $out/bin/otelcol-contrib
            '';

            jaeger = super.runCommand "mock-jaeger" { } ''
              mkdir -p $out/bin
              echo "#!/bin/sh" > $out/bin/jaeger-all-in-one
              chmod +x $out/bin/jaeger-all-in-one
            '';
          })
        ];
      };
  };

  testScript = ''
    start_all()

    # Verify configuration generation
    gateway.wait_for_unit("otel-collector.service")

    # Check if config file exists
    gateway.succeed("test -f /etc/otel/config.yaml")

    # Verify content in config file
    gateway.succeed("grep 'receivers:' /etc/otel/config.yaml")
    gateway.succeed("grep 'otlp:' /etc/otel/config.yaml")

    # Verify service sampling configuration (should be 100% based on probability 1.0)
    gateway.succeed("grep 'sampling_percentage: 100' /etc/otel/config.yaml")
  '';
}

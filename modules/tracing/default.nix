{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.gateway.tracing;
  traceCollector = import ../../lib/trace-collector.nix { inherit lib; };

  traceSpansOption = {
    options = {
      operations = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "List of operations to trace in this span group";
      };
      attributes = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "List of attributes to include in traces";
      };
    };
  };

  # Common trace configuration for services
  traceServiceOption = mkOption {
    type = types.submodule {
      options = {
        enable = mkEnableOption "tracing for this service";
        spans = mkOption {
          type = types.attrsOf (types.submodule traceSpansOption);
          default = { };
          description = "Trace span definitions";
        };
      };
    };
    default = { };
    description = "Service-specific tracing configuration";
  };

in
{
  options.services.gateway.tracing = {
    enable = mkEnableOption "Distributed Tracing";

    collector = {
      endpoint = mkOption {
        type = types.str;
        default = "http://jaeger:14268/api/traces";
        description = "Trace collector endpoint URL";
      };

      protocol = mkOption {
        type = types.enum [
          "http"
          "grpc"
        ];
        default = "http";
        description = "Protocol used to send traces";
      };

      sampling = {
        strategy = mkOption {
          type = types.enum [
            "const"
            "probabilistic"
            "ratelimiting"
            "remote"
          ];
          default = "probabilistic";
          description = "Sampling strategy";
        };

        probability = mkOption {
          type = types.float;
          default = 0.1;
          description = "Sampling probability (0.0 to 1.0)";
        };

        serviceOverrides = mkOption {
          type = types.attrsOf (
            types.submodule {
              options.probability = mkOption {
                type = types.float;
                description = "Sampling probability for specific service";
              };
            }
          );
          default = { };
          description = "Per-service sampling overrides";
        };
      };

      batch = {
        timeout = mkOption {
          type = types.str;
          default = "5s";
          description = "Batch sending timeout";
        };
        batchSize = mkOption {
          type = types.int;
          default = 100;
          description = "Maximum batch size";
        };
        maxPacketSize = mkOption {
          type = types.int;
          default = 1048576;
          description = "Maximum packet size in bytes";
        };
      };
    };

    services = {
      dns = traceServiceOption;
      dhcp = traceServiceOption;
      network = traceServiceOption;
      ids = traceServiceOption;
    };

    networkFlows = {
      enable = mkEnableOption "Network flow tracing";

      tracing = {
        flowTimeout = mkOption {
          type = types.str;
          default = "30s";
          description = "Flow timeout duration";
        };
        maxFlows = mkOption {
          type = types.int;
          default = 100000;
          description = "Maximum concurrent flows to track";
        };
        attributes = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Flow attributes to include in traces";
        };
      };

      sampling = {
        strategy = mkOption {
          type = types.str;
          default = "flow-based";
          description = "Flow sampling strategy";
        };
        sampleRate = mkOption {
          type = types.int;
          default = 1000;
          description = "Global flow sampling rate (1 in N)";
        };
        filters = mkOption {
          type = types.listOf types.attrs;
          default = [ ];
          description = "Specific flow sampling filters";
        };
      };
    };

    analysis = {
      enable = mkEnableOption "Trace analysis tools";

      performance = {
        latencyThresholds = mkOption {
          type = types.attrsOf types.str;
          default = { };
          description = "Latency thresholds per service";
        };
        anomalyDetection = {
          enable = mkEnableOption "Anomaly detection";
          algorithm = mkOption {
            type = types.str;
            default = "statistical";
            description = "Detection algorithm";
          };
          sensitivity = mkOption {
            type = types.float;
            default = 0.95;
            description = "Sensitivity level";
          };
        };
      };

      dependencies = {
        autoDiscovery = mkEnableOption "Dependency auto-discovery";
        updateInterval = mkOption {
          type = types.str;
          default = "5m";
          description = "Discovery update interval";
        };
        mapping = mkOption {
          type = types.attrsOf types.bool;
          default = {
            services = true;
            networks = true;
            protocols = true;
          };
          description = "Enabled dependency mapping types";
        };
      };
    };

    integration = {
      jaeger = {
        enable = mkEnableOption "Jaeger integration";
        endpoint = mkOption {
          type = types.str;
          default = "http://jaeger:16686";
          description = "Jaeger UI endpoint";
        };
      };
      prometheus = {
        enable = mkEnableOption "Prometheus metrics integration";
        metrics = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Metrics to export from traces";
        };
      };
      grafana = {
        enable = mkEnableOption "Grafana dashboard integration";
        dashboards = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Dashboards to create";
        };
      };
    };
  };

  config = mkIf cfg.enable {
    # Generate OpenTelemetry Collector configuration
    environment.etc."otel/config.yaml".source = (pkgs.formats.yaml { }).generate "otel-config.yaml" (
      traceCollector.mkOtelConfig cfg
    );

    # Enable OpenTelemetry Collector service
    systemd.services.otel-collector = {
      description = "OpenTelemetry Collector";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.opentelemetry-collector-contrib}/bin/otelcol-contrib --config /etc/otel/config.yaml";
        Restart = "always";
      };
    };

    # Configure Jaeger if enabled
    # services.jaeger = mkIf cfg.integration.jaeger.enable {
    #   enable = true;
    #   # Basic Jaeger all-in-one configuration
    # };
  };
}

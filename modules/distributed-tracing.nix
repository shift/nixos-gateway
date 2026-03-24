{ config, lib, ... }:

with lib;

let
  cfg = config.services.distributedTracing;
in

{
  options.services.distributedTracing = {
    enable = mkEnableOption "Distributed tracing framework";

    collector = {
      endpoint = mkOption {
        type = types.str;
        default = "http://jaeger:14268/api/traces";
        description = "Trace collector endpoint";
      };

      protocol = mkOption {
        type = types.enum [ "http" "grpc" ];
        default = "http";
        description = "Protocol for trace submission";
      };

      sampling = {
        strategy = mkOption {
          type = types.enum [ "always" "never" "probabilistic" "rate-limiting" "adaptive" ];
          default = "probabilistic";
          description = "Trace sampling strategy";
        };

        probability = mkOption {
          type = types.float;
          default = 0.1;
          description = "Sampling probability (0.0 to 1.0)";
        };

        serviceOverrides = mkOption {
          type = types.attrsOf (types.submodule {
            options = {
              probability = mkOption {
                type = types.nullOr types.float;
                default = null;
                description = "Service-specific sampling probability";
              };
            };
          });
          default = {};
          description = "Per-service sampling overrides";
        };
      };

      batch = {
        timeout = mkOption {
          type = types.str;
          default = "5s";
          description = "Batch timeout for trace submission";
        };

        batchSize = mkOption {
          type = types.int;
          default = 100;
          description = "Maximum batch size";
        };

        maxPacketSize = mkOption {
          type = types.int;
          default = 1048576; # 1MB
          description = "Maximum packet size in bytes";
        };
      };
    };

    services = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Enable tracing for this service";
          };

          spans = mkOption {
            type = types.attrsOf (types.submodule {
              options = {
                operations = mkOption {
                  type = types.listOf types.str;
                  description = "Operations to trace";
                };

                attributes = mkOption {
                  type = types.listOf types.str;
                  default = [];
                  description = "Span attributes to capture";
                };
              };
            });
            default = {};
            description = "Span definitions for this service";
          };
        };
      });
      default = {};
      description = "Service-specific tracing configuration";
    };

    networkFlows = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable network flow tracing";
      };

      tracing = {
        flowTimeout = mkOption {
          type = types.str;
          default = "30s";
          description = "Flow tracking timeout";
        };

        maxFlows = mkOption {
          type = types.int;
          default = 100000;
          description = "Maximum concurrent flows to track";
        };

        attributes = mkOption {
          type = types.listOf types.str;
          default = [
            "flow.src_ip"
            "flow.dst_ip"
            "flow.src_port"
            "flow.dst_port"
            "flow.protocol"
            "flow.bytes"
            "flow.packets"
            "flow.duration"
          ];
          description = "Network flow attributes to capture";
        };
      };

      sampling = {
        strategy = mkOption {
          type = types.enum [ "packet-based" "flow-based" "time-based" ];
          default = "flow-based";
          description = "Network sampling strategy";
        };

        sampleRate = mkOption {
          type = types.int;
          default = 1000;
          description = "Sampling rate (1 in N)";
        };

        filters = mkOption {
          type = types.listOf types.attrs;
          default = [];
          description = "Sampling filters";
        };
      };
    };
  };

  config = mkIf cfg.enable {
    # OpenTelemetry collector service
    services.opentelemetry-collector = {
      enable = true;

      settings = {
        receivers = {
          otlp = {
            protocols = {
              grpc.endpoint = "0.0.0.0:4317";
              http.endpoint = "0.0.0.0:4318";
            };
          };
        };

        processors = {
          batch = {
            timeout = cfg.collector.batch.timeout;
            send_batch_size = cfg.collector.batch.batchSize;
          };

          memory_limiter = {
            limit_mib = 512;
            spike_limit_mib = 128;
            check_interval = "5s";
          };
        };

        exporters = {
          jaeger = {
            endpoint = cfg.collector.endpoint;
            tls.insecure = true;
          };
        };

        service = {
          pipelines = {
            traces = {
              receivers = [ "otlp" ];
              processors = [ "memory_limiter" "batch" ];
              exporters = [ "jaeger" ];
            };
          };
        };
      };
    };

    # Tracing instrumentation service
    systemd.services.tracing-instrumentation = {
      description = "Distributed Tracing Instrumentation";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "opentelemetry-collector.service" ];

      serviceConfig = {
        ExecStart = "${pkgs.callPackage ./tracing-instrumentation.nix {
          inherit (cfg) collector services networkFlows;
        }}/bin/tracing-instrumentation";
        Restart = "always";
        User = "tracing";
        Group = "tracing";
      };
    };

    # Create tracing user and directories
    users.users.tracing = {
      isSystemUser = true;
      group = "tracing";
      home = "/var/lib/tracing";
      createHome = true;
    };

    users.groups.tracing = {};

    systemd.tmpfiles.rules = [
      "d /var/lib/tracing 0750 tracing tracing -"
      "d /var/lib/tracing/spans 0750 tracing tracing -"
      "d /var/lib/tracing/flows 0750 tracing tracing -"
    ];

    # Install OpenTelemetry packages
    environment.systemPackages = with pkgs; [
      opentelemetry-collector
      jaeger
    ];
  };
}
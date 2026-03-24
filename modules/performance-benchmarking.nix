{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.nixos-gateway.benchmarking;
  benchmarkEngine = import ../lib/benchmark-engine.nix { inherit pkgs; };
in
{
  options.services.nixos-gateway.benchmarking = {
    enable = lib.mkEnableOption "Performance Benchmarking Service";

    enableSysbench = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Sysbench CPU/Memory tests";
    };

    enableIperf = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable iperf3 network loopback tests";
    };

    enableStress = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable stress-ng load tests";
    };

    outputFile = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/nixos-gateway/benchmark-report.json";
      description = "Path to write the JSON report";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.performance-benchmark = {
      description = "NixOS Gateway Performance Benchmark";
      path = with pkgs; [
        sysbench
        iperf3
        stress-ng
        jq
        coreutils
      ];

      serviceConfig = {
        Type = "oneshot";
        User = "root";
        StandardOutput = "journal+console";
      };

      script = benchmarkEngine.generateBenchmarkScript {
        inherit (cfg) outputFile;
        sysbenchEnabled = cfg.enableSysbench;
        iperfEnabled = cfg.enableIperf;
        stressEnabled = cfg.enableStress;
      };
    };
  };
}

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.networking.acceleration.xdp;
  xdpPrograms = import ../lib/xdp-programs.nix { inherit lib pkgs; };
  ebpfMonitoring = import ../lib/ebpf-monitoring.nix { inherit lib pkgs; };
  inherit (lib)
    mkOption
    types
    mkEnableOption
    mkIf
    ;

  interfaceOptions = types.submodule {
    options = {
      enable = mkEnableOption "XDP on this interface";

      mode = mkOption {
        type = types.enum [
          "skb"
          "driver"
          "hw"
        ];
        default = "skb";
        description = "XDP attachment mode (skb=generic, driver=native, hw=offload)";
      };

      program = mkOption {
        type = types.str;
        default = "drop";
        description = "XDP program type to load";
      };

      blacklist = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "List of IP addresses to drop";
      };

      customSource = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Custom C source code for XDP program";
      };
    };
  };

in
{
  options.networking.acceleration.xdp = {
    enable = mkEnableOption "XDP packet acceleration";

    interfaces = mkOption {
      type = types.attrsOf interfaceOptions;
      default = { };
      description = "Interface-specific XDP configuration";
    };

    monitoring = {
      enable = mkEnableOption "eBPF monitoring";
      metricsPort = mkOption {
        type = types.port;
        default = 9091;
        description = "Port for eBPF metrics export";
      };
      customMetrics = mkOption {
        type = types.listOf (
          types.submodule {
            options = {
              name = mkOption { type = types.str; };
              type = mkOption {
                type = types.enum [
                  "counter"
                  "gauge"
                  "histogram"
                ];
              };
              description = mkOption { type = types.str; };
            };
          }
        );
        default = [ ];
        description = "Additional metrics to collect";
      };
    };
  };

  config = mkIf cfg.enable {
    # Verify kernel version requirements (warn only)
    warnings = mkIf (lib.versionOlder config.boot.kernelPackages.kernel.version "4.18") [
      "XDP acceleration requires Linux kernel >= 4.18 for full feature support."
    ];

    # Required system packages
    environment.systemPackages =
      with pkgs;
      [
        linuxPackages.perf
        clang
        llvm
        iproute2
      ]
      ++ lib.optionals (pkgs ? bpftool) [ pkgs.bpftool ]
      ++ lib.optionals (pkgs ? libbpf) [ pkgs.libbpf ]
      ++ lib.optionals (pkgs ? xdp-tools) [ pkgs.xdp-tools ];

    # Create XDP program service for each interface
    systemd.services = lib.mkMerge [
      (lib.mapAttrs' (
        name: ifaceCfg:
        lib.nameValuePair "xdp-attach-${name}" {
          description = "Attach XDP program to ${name}";
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ];

          script =
            let
              # Determine source code to use
              sourceCode =
                if ifaceCfg.customSource != null then
                  ifaceCfg.customSource
                else
                  xdpPrograms.mkDropProgram ifaceCfg.blacklist;

              # Compile the program (in a real system)
              # For this implementation, we simulate the compilation/loading
              bpfObj = xdpPrograms.compileBPF "xdp-${name}" sourceCode;
            in
            ''
              echo "Loading XDP program for ${name} in ${ifaceCfg.mode} mode..."

              # In a real system:
              # ip link set dev ${name} xdp${
                if ifaceCfg.mode == "skb" then
                  "generic"
                else if ifaceCfg.mode == "driver" then
                  ""
                else
                  "offload"
              } obj ${bpfObj} sec xdp

              # Simulation:
              mkdir -p /run/xdp/
              echo "${name}: loaded" > /run/xdp/${name}.status
              echo "${sourceCode}" > /run/xdp/${name}.c
            '';

          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStop = "echo 'Unloading XDP from ${name}' && rm -f /run/xdp/${name}.status";
          };
        }
      ) (lib.filterAttrs (n: v: v.enable) cfg.interfaces))

      # Monitoring service
      (mkIf cfg.monitoring.enable {
        ebpf-exporter = {
          description = "eBPF Metrics Exporter";
          wantedBy = [ "multi-user.target" ];

          script =
            let
              allMetrics = ebpfMonitoring.standardMetrics ++ cfg.monitoring.customMetrics;
              monitorCode = ebpfMonitoring.mkMonitoringCode allMetrics;
            in
            ''
              echo "Starting eBPF Exporter on port ${toString cfg.monitoring.metricsPort}"
              mkdir -p /run/ebpf-monitoring
              echo "${monitorCode}" > /run/ebpf-monitoring/monitor.c

              # Simulate exporter running
              while true; do
                sleep 60
              done
            '';
        };
      })
    ];
  };
}

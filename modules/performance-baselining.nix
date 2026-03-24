{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.performance-baselining;
  baselineAnalyzer = import ../lib/baseline-analyzer.nix { inherit pkgs; };
in
{
  options.services.performance-baselining = {
    enable = lib.mkEnableOption "Performance Baselining Service";

    interval = lib.mkOption {
      type = lib.types.str;
      default = "5m";
      description = "Interval at which to run the baselining analysis (systemd timer format)";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/gateway-baselines";
      description = "Directory to store metrics, baselines, and anomaly records";
    };

    zScoreThreshold = lib.mkOption {
      type = lib.types.float;
      default = 2.0;
      description = "Number of standard deviations from the mean to consider an anomaly";
    };

    minSamples = lib.mkOption {
      type = lib.types.int;
      default = 5;
      description = "Minimum number of samples required before detecting anomalies";
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure the analyzer tool is available in system packages (optional, but good for debugging)
    environment.systemPackages = [ baselineAnalyzer ];

    systemd.services.performance-baselining = {
      description = "Performance Baselining and Anomaly Detection";
      after = [ "network.target" ];

      environment = {
        METRICS_FILE = "${cfg.dataDir}/metrics.json";
        BASELINE_FILE = "${cfg.dataDir}/baseline.json";
        ANOMALY_FILE = "${cfg.dataDir}/anomalies.json";
        Z_SCORE_THRESHOLD = toString cfg.zScoreThreshold;
        MIN_SAMPLES = toString cfg.minSamples;
      };

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${baselineAnalyzer}/bin/baseline-analyzer";
        User = "root"; # Or a dedicated user, but root is simpler for MVP accessing system metrics
        StateDirectory = "gateway-baselines";
        # If we weren't using StateDirectory to manage the dir, we'd need:
        # ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${cfg.dataDir}";
      };
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
    ];

    systemd.timers.performance-baselining = {
      description = "Timer for Performance Baselining";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "1m";
        OnUnitActiveSec = cfg.interval;
        Unit = "performance-baselining.service";
      };
    };
  };
}

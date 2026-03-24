{ lib }:

let
  # Helper to parse duration strings like "30d", "2h", "15m", "30s" to seconds
  parseDuration =
    durationStr:
    let
      len = lib.stringLength durationStr;
      lastChar = lib.substring (len - 1) 1 durationStr;
      # Extract value part (everything except last char)
      valStr = lib.substring 0 (len - 1) durationStr;
      # Helper to safely convert string to int
      safeToInt =
        str:
        let
          parsed = builtins.tryEval (lib.toInt str);
        in
        if parsed.success then parsed.value else 0;

      value = safeToInt valStr;
    in
    if lastChar == "d" then
      value * 86400
    else if lastChar == "h" then
      value * 3600
    else if lastChar == "m" then
      value * 60
    else if lastChar == "s" then
      value
    else
      safeToInt durationStr; # Fallback: assume raw seconds if no unit

  # Calculate error budget in seconds for a given target (percentage) and window (seconds)
  # e.g., target 99.9 means 0.1% error allowed.
  # Budget = window * (1 - target/100)
  calculateErrorBudgetSeconds =
    target: windowSeconds:
    let
      allowedErrorRatio = (100.0 - target) / 100.0;
    in
    windowSeconds * allowedErrorRatio;

  # Calculate the percentage of budget remaining given observed errors
  calculateBudgetRemaining =
    target: windowSeconds: observedErrorSeconds:
    let
      budget = calculateErrorBudgetSeconds target windowSeconds;
    in
    if budget == 0 then 0.0 else ((budget - observedErrorSeconds) / budget) * 100.0;

  # Generate Prometheus recording rules for an SLO
  # This is a helper to generate the rule structure based on standard multi-window, multi-burn-rate alerts
  # Ref: https://sre.google/workbook/alerting-on-slos/
  generatePrometheusRules =
    {
      name,
      sli,
      slo,
    }:
    let
      windowSeconds = parseDuration slo.timeWindow;
      target = slo.target;

      # We typically want to record the error rate over specific windows for alerting
      # Common windows for burn rates: 1h, 6h, 5m, 30m, etc.
      # But here we will generate based on the user provided burn rates or defaults.

      # Helper to create a recording rule
      mkRecord = expr: record: {
        inherit record expr;
      };

      # Determine metric expression based on SLI type
      metricExpr =
        if sli ? successRate then
          # ratio = error / total
          # error = total - good (or explicit bad metric)
          # We want error rate: (total - good) / total OR (bad / total)
          # But usually Prometheus calculates rate() first.
          let
            totalRate = "rate(${sli.successRate.total}[1m])";
            goodRate = "rate(${sli.successRate.good}[1m])";
          in
          "(${totalRate} - ${goodRate}) / ${totalRate}"
        else if sli ? latency then
          # latency threshold: (total - bucket_le_threshold) / total ??
          # Usually histogram: (rate(bucket_total) - rate(bucket_le_threshold)) / rate(bucket_total)
          # This gives percentage of requests SLOWER than threshold.
          # Or direct metric if provided.
          "rate(${sli.latency.metric}{le=\"${sli.latency.threshold}\"}[1m])" # Placeholder, highly dependent on metric type
        else if sli ? availability then
          # 1 - up/1 ?
          "1 - ${sli.availability.metric}"
        else
          "0";

    in
    [
      (mkRecord metricExpr "slo:error_rate:ratio_${name}")
    ];

  # Enhanced SLO calculation functions
  calculateSLI = {
    type,
    measurements,
    config
  }: let
    calculateSuccessRate = measurements: config:
      if measurements == [] then 100.0
      else let
        good = lib.foldl (acc: m: acc + (m.good or 0)) 0 measurements;
        total = lib.foldl (acc: m: acc + (m.total or 0)) 0 measurements;
      in if total == 0 then 100.0 else (good / total) * 100.0;

    calculateLatency = measurements: config: let
      latencies = lib.filter (m: m.value <= (config.threshold or 1.0)) measurements;
    in if measurements == [] then 100.0
       else (lib.length latencies / lib.length measurements) * 100.0;

    calculateAvailability = measurements: config:
      if measurements == [] then 100.0
      else let
        available = lib.filter (m: m.value >= (config.threshold or 1)) measurements;
      in (lib.length available / lib.length measurements) * 100.0;
  in
    if type == "success-rate" then calculateSuccessRate measurements config
    else if type == "latency" then calculateLatency measurements config
    else if type == "availability" then calculateAvailability measurements config
    else 100.0;

  # Error budget calculations
  calculateErrorBudget = {
    sloTarget,
    sliValue,
    timeWindow
  }: let
    errorBudget = 100.0 - sloTarget;
    currentError = 100.0 - sliValue;
    remainingBudget = errorBudget - currentError;
  in {
    inherit errorBudget currentError remainingBudget;
    exhausted = remainingBudget <= 0;
  };

  # Burn rate calculations
  calculateBurnRate = {
    errorBudget,
    timeWindow,
    measurements
  }: let
    # Simplified burn rate calculation
    recentErrors = lib.take 10 measurements;  # Last 10 measurements
    errorRate = if recentErrors == [] then 0.0
                else (lib.foldl (acc: m: acc + m.value) 0 recentErrors) / (lib.length recentErrors);
    burnRate = if errorBudget == 0 then 0.0 else errorRate / errorBudget;
  in burnRate;

  # SLO compliance calculation
  calculateSLOCompliance = {
    sloTarget,
    sliValues,
    timeWindow
  }: let
    avgSLI = if sliValues == [] then 100.0
             else (lib.foldl (acc: v: acc + v) 0 sliValues) / (lib.length sliValues);
    compliance = if avgSLI >= sloTarget then 100.0 else (avgSLI / sloTarget) * 100.0;
  in {
    inherit avgSLI compliance;
    met = compliance >= 100.0;
  };

  # Alert generation
  generateAlerts = {
    sloId,
    compliance,
    burnRate,
    thresholds
  }: let
    alerts = [];

    alerts = alerts ++ (if burnRate > (thresholds.burnRateFast or 14.4) then [{
      type = "burn-rate-fast";
      severity = "critical";
      message = "Fast error budget burn rate: ${toString burnRate}";
    }] else []);

    alerts = alerts ++ (if burnRate > (thresholds.burnRateSlow or 6.0) then [{
      type = "burn-rate-slow";
      severity = "warning";
      message = "Slow error budget burn rate: ${toString burnRate}";
    }] else []);

    alerts = alerts ++ (if compliance < 95.0 then [{
      type = "compliance-low";
      severity = "warning";
      message = "Low SLO compliance: ${toString compliance}%";
    }] else []);
  in alerts;

  # Report generation
  generateSLOReport = {
    sloId,
    sloConfig,
    sliResults,
    compliance,
    errorBudget,
    burnRate,
    alerts,
    timeWindow
  }: {
    reportId = "${sloId}-${toString (builtins.currentTime)}";
    generatedAt = builtins.currentTime;
    slo = sloConfig;
    results = {
      inherit compliance errorBudget burnRate;
      sliMeasurements = sliResults;
      activeAlerts = alerts;
      timeWindow = timeWindow;
    };
    summary = {
      status = if compliance.met then "healthy" else "degraded";
      errorBudgetRemaining = errorBudget.remainingBudget;
      burnRateStatus = if burnRate > 10 then "critical"
                      else if burnRate > 5 then "warning"
                      else "normal";
    };
  };

  # Validation helpers
  validateSLOConfig = sloConfig: let
    errors = [];
    errors = errors ++ (if !lib.hasAttr "target" sloConfig || sloConfig.target < 0 || sloConfig.target > 100 then
      ["SLO target must be between 0 and 100"] else []);
    errors = errors ++ (if !lib.hasAttr "timeWindow" sloConfig then
      ["SLO timeWindow is required"] else []);
  in {
    valid = errors == [];
    inherit errors;
  };

  validateSLIConfig = sliConfig: let
    errors = [];
    validTypes = [ "success-rate" "latency" "availability" "custom" ];
    errors = errors ++ (if !lib.elem sliConfig.type validTypes then
      ["Invalid SLI type: ${sliConfig.type}"] else []);
    errors = errors ++ (if !lib.hasAttr "metric" sliConfig then
      ["SLI metric is required"] else []);
  in {
    valid = errors == [];
    inherit errors;
  };

in
{
  inherit
    parseDuration
    calculateErrorBudgetSeconds
    calculateBudgetRemaining
    generatePrometheusRules
    calculateSLI
    calculateErrorBudget
    calculateBurnRate
    calculateSLOCompliance
    generateAlerts
    generateSLOReport
    validateSLOConfig
    validateSLIConfig
    ;
}

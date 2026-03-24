{ lib }:

let
  inherit (lib)
    mkOption
    types
    optionalAttrs
    mapAttrsToList
    concatStringsSep
    concatMapStringsSep
    filter
    mapAttrs
    ;

  # Posture check result types
  postureResultType = types.submodule {
    options = {
      name = mkOption {
        type = types.str;
        description = "Check name";
      };

      type = mkOption {
        type = types.str;
        description = "Check type";
      };

      criticality = mkOption {
        type = types.enum [ "low" "medium" "high" "critical" ];
        description = "Check criticality";
      };

      status = mkOption {
        type = types.enum [ "pass" "fail" "unknown" "error" ];
        description = "Check result status";
      };

      details = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Additional check details";
      };

      timestamp = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "Check timestamp";
      };

      remediation = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Suggested remediation action";
      };
    };
  };

  # Device posture state type
  devicePostureType = types.submodule {
    options = {
      score = mkOption {
        type = types.int;
        description = "Overall posture score (0-100)";
      };

      baseScore = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "Base score before context multipliers";
      };

      lastAssessment = mkOption {
        type = types.int;
        description = "Timestamp of last assessment";
      };

      results = mkOption {
        type = types.attrsOf (types.listOf postureResultType);
        description = "Check results by category";
      };

      contextMultipliers = mkOption {
        type = types.attrs;
        default = { };
        description = "Applied context multipliers";
      };

      deviceType = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Device type classification";
      };

      compliance = mkOption {
        type = types.attrs;
        default = { };
        description = "Compliance status information";
      };
    };
  };

  # Helper functions for posture evaluation

  # Calculate posture score from check results
  calculatePostureScore = {
    results,
    weights ? {
      security = 40;
      compliance = 30;
      applications = 20;
      behavior = 10;
    }
  }:
    let
      totalScore = 0;
      maxPossible = 0;

      calculateCategoryScore = category: categoryResults:
        let
          totalChecks = builtins.length categoryResults;
          passedChecks = builtins.length (filter (r: r.status == "pass") categoryResults);

          # Weight checks by criticality
          weightedScore = builtins.foldl' (acc: result:
            let
              criticalityWeight = {
                "low" = 1;
                "medium" = 2;
                "high" = 3;
                "critical" = 4;
              }.${result.criticality} or 1;

              checkScore = if result.status == "pass" then 100 else 0;
            in
            acc + (checkScore * criticalityWeight)
          ) 0 categoryResults;

          totalWeight = builtins.foldl' (acc: result:
            let
              criticalityWeight = {
                "low" = 1;
                "medium" = 2;
                "high" = 3;
                "critical" = 4;
              }.${result.criticality} or 1;
            in
            acc + criticalityWeight
          ) 0 categoryResults;

          categoryScore = if totalWeight > 0 then (weightedScore / totalWeight) else 0;
        in
        categoryScore;

      categoryScores = mapAttrs calculateCategoryScore results;

      finalScore = builtins.foldl' (acc: category:
        let
          weight = weights.${category} or 0;
          categoryScore = categoryScores.${category} or 0;
        in
        acc + (categoryScore * weight)
      ) 0 (builtins.attrNames weights);

      maxScore = builtins.foldl' (acc: category:
        let
          weight = weights.${category} or 0;
        in
        acc + (100 * weight)
      ) 0 (builtins.attrNames weights);

    in
    if maxScore > 0 then
      builtins.floor ((finalScore / maxScore) * 100)
    else
      100;

  # Apply context multipliers to posture score
  applyContextMultipliers = {
    baseScore,
    contexts,
    deviceContext ? { }
  }:
    let
      applyMultiplier = score: multiplier:
        builtins.floor (score * multiplier);

      # Location multiplier
      locationMultiplier = contexts.location.${deviceContext.location or "office"}.scoreMultiplier or 1.0;

      # Time multiplier
      currentTime = builtins.currentTime;
      hour = (currentTime / 3600) % 24;
      dayOfWeek = ((currentTime / 86400) + 4) % 7; # 0 = Sunday

      timeContext =
        if dayOfWeek >= 1 && dayOfWeek <= 5 && hour >= 9 && hour <= 17 then
          "business-hours"
        else if dayOfWeek >= 6 then
          "weekend"
        else
          "after-hours";

      timeMultiplier = contexts.time.${timeContext}.scoreMultiplier or 1.0;

      # Risk multiplier
      riskMultiplier = contexts.risk.${deviceContext.riskLevel or "normal"}.scoreMultiplier or 1.0;

      # Apply all multipliers
      scoreWithLocation = applyMultiplier baseScore locationMultiplier;
      scoreWithTime = applyMultiplier scoreWithLocation timeMultiplier;
      finalScore = applyMultiplier scoreWithTime riskMultiplier;

    in
    {
      score = builtins.min 100 finalScore;
      multipliers = {
        location = locationMultiplier;
        time = timeMultiplier;
        risk = riskMultiplier;
      };
    };

  # Evaluate device type based on characteristics
  classifyDeviceType = {
    deviceData,
    deviceTypes
  }:
    let
      matchesType = typeName: typeConfig:
        let
          requiredChecks = typeConfig.requiredChecks or [ ];
          # Simplified matching - in real implementation would check actual device data
          matches = builtins.length requiredChecks > 0;
        in
        if matches then typeName else null;

      matchingTypes = filter (type: type != null) (mapAttrsToList matchesType deviceTypes);
    in
    if builtins.length matchingTypes > 0 then
      builtins.head matchingTypes
    else
      "unknown";

  # Check if device meets posture requirements
  evaluatePostureCompliance = {
    posture,
    policies,
    deviceType
  }:
    let
      devicePolicy = policies.deviceTypes.${deviceType} or policies.deviceTypes.corporate or { };
      requiredScore = devicePolicy.scoreThreshold or 80;
      requiredChecks = devicePolicy.requiredChecks or [ ];

      scoreCompliant = posture.score >= requiredScore;

      # Check if all required checks passed
      checkCompliance = checkName:
        let
          # Find check result across all categories
          foundResult = builtins.foldl' (acc: category:
            if acc != null then acc
            else builtins.foldl' (acc2: result:
              if result.name == checkName then result else acc2
            ) null posture.results.${category}
          ) null (builtins.attrNames posture.results);
        in
        foundResult != null && foundResult.status == "pass";

      checksCompliant = builtins.all checkCompliance requiredChecks;

    in
    {
      overall = scoreCompliant && checksCompliant;
      score = scoreCompliant;
      checks = checksCompliant;
      requiredScore = requiredScore;
      requiredChecks = requiredChecks;
    };

  # Generate remediation recommendations
  generateRemediationPlan = {
    posture,
    compliance,
    remediationConfig
  }:
    let
      failedChecks = builtins.concatLists (
        mapAttrsToList (category: results:
          filter (result: result.status != "pass") results
        ) posture.results
      );

      # Generate automatic actions
      automaticActions = if remediationConfig.automatic.enable or true then
        map (check: {
          check = check.name;
          action = check.remediation or "manual-intervention";
          priority = {
            "low" = "low";
            "medium" = "medium";
            "high" = "high";
            "critical" = "critical";
          }.${check.criticality} or "medium";
          deadline = "24h";
        }) (filter (check: check.remediation != null) failedChecks)
      else [ ];

      # Generate manual workflows
      manualWorkflows = if remediationConfig.manual.enable or true then
        let
          complianceViolation = if !compliance.overall then [{
            name = "compliance-workflow";
            trigger = "compliance-failure";
            priority = "high";
          }] else [ ];

          securityViolations = filter (check: check.criticality == "critical") failedChecks;
          securityWorkflows = if builtins.length securityViolations > 0 then [{
            name = "security-workflow";
            trigger = "security-violation";
            priority = "critical";
          }] else [ ];
        in
        complianceViolation ++ securityWorkflows
      else [ ];

    in
    {
      automatic = automaticActions;
      manual = manualWorkflows;
      summary = {
        failedChecks = builtins.length failedChecks;
        criticalIssues = builtins.length (filter (check: check.criticality == "critical") failedChecks);
        complianceIssues = if compliance.overall then 0 else 1;
      };
    };

  # Generate posture report
  generatePostureReport = {
    deviceId,
    posture,
    compliance,
    remediation,
    history ? [ ]
  }:
    let
      thresholds = {
        excellent = 95;
        good = 80;
        warning = 60;
        critical = 40;
      };

      status = if posture.score >= thresholds.excellent then "excellent"
               else if posture.score >= thresholds.good then "good"
               else if posture.score >= thresholds.warning then "warning"
               else if posture.score >= thresholds.critical then "critical"
               else "fail";

      trend = if builtins.length history >= 2 then
        let
          recent = builtins.take 5 history;
          avgRecent = builtins.foldl' (acc: h: acc + h.score) 0 recent / builtins.length recent;
          avgOlder = if builtins.length history > 5 then
            let older = builtins.drop 5 history;
            in builtins.foldl' (acc: h: acc + h.score) 0 older / builtins.length older
            else avgRecent;
        in
        if avgRecent > avgOlder then "improving"
        else if avgRecent < avgOlder then "degrading"
        else "stable"
      else "unknown";

    in
    {
      deviceId = deviceId;
      timestamp = builtins.currentTime;
      summary = {
        score = posture.score;
        status = status;
        trend = trend;
        compliance = compliance.overall;
      };
      details = {
        categories = mapAttrs (category: results: {
          total = builtins.length results;
          passed = builtins.length (filter (r: r.status == "pass") results);
          failed = builtins.length (filter (r: r.status != "pass") results);
          critical = builtins.length (filter (r: r.criticality == "critical" && r.status != "pass") results);
        }) posture.results;
      };
      remediation = remediation;
      history = history;
    };

in
{
  inherit
    postureResultType
    devicePostureType
    calculatePostureScore
    applyContextMultipliers
    classifyDeviceType
    evaluatePostureCompliance
    generateRemediationPlan
    generatePostureReport
    ;
}

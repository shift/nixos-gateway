{ }:

let
  inherit (import <nixpkgs> {}) lib;

in rec {
  # Verification result types
  resultTypes = {
    passed = "passed";
    failed = "failed";
    skipped = "skipped";
    error = "error";
  };

  # Test categories
  testCategories = {
    functional = "functional";
    integration = "integration";
    performance = "performance";
    security = "security";
    regression = "regression";
  };

  # Quality gate definitions
  qualityGates = {
    testCoverage = {
      name = "test-coverage";
      description = "Minimum test coverage requirement";
      threshold = 95.0; # 95%
      unit = "percentage";
    };

    performance = {
      name = "performance";
      description = "Performance requirements";
      threshold = 100.0; # milliseconds
      unit = "ms";
    };

    security = {
      name = "security";
      description = "Security compliance";
      threshold = 0.0; # vulnerabilities
      unit = "count";
    };

    integration = {
      name = "integration";
      description = "Integration compatibility";
      threshold = 100.0; # percentage
      unit = "percentage";
    };
  };

  # Verification utilities
  mkVerification = {
    taskId,
    taskName,
    category,
    tests ? [],
    qualityGates ? [],
    metadata ? {}
  }: {
    inherit taskId taskName category tests qualityGates metadata;
    id = "${toString (builtins.currentTime)}-${taskId}";
    timestamp = builtins.currentTime;
  };

  # Test definition helpers
  mkFunctionalTest = { name, description, testScript, expectedResult ? resultTypes.passed }: {
    inherit name description testScript expectedResult;
    type = testCategories.functional;
  };

  mkIntegrationTest = { name, description, testScript, dependencies ? [], expectedResult ? resultTypes.passed }: {
    inherit name description testScript dependencies expectedResult;
    type = testCategories.integration;
  };

  mkPerformanceTest = { name, description, testScript, threshold, unit, expectedResult ? resultTypes.passed }: {
    inherit name description testScript threshold unit expectedResult;
    type = testCategories.performance;
  };

  mkSecurityTest = { name, description, testScript, severity ? "medium", expectedResult ? resultTypes.passed }: {
    inherit name description testScript severity expectedResult;
    type = testCategories.security;
  };

  mkRegressionTest = { name, description, baseline, testScript, expectedResult ? resultTypes.passed }: {
    inherit name description baseline testScript expectedResult;
    type = testCategories.regression;
  };

  # Quality gate helpers
  mkQualityGate = { name, description, threshold, unit, checkScript }: {
    inherit name description threshold unit checkScript;
  };

  # Result processing
  processTestResult = { test, actualResult, duration ? null, error ? null, metrics ? {} }: {
    inherit test actualResult duration error metrics;
    passed = actualResult == test.expectedResult;
    timestamp = builtins.currentTime;
  };

  processQualityGateResult = { gate, actualValue, passed }: {
    inherit gate actualValue passed;
    timestamp = builtins.currentTime;
    deviation = if passed then 0.0 else (
      if actualValue > gate.threshold then actualValue - gate.threshold
      else gate.threshold - actualValue
    );
  };

  # Summary generation
  generateVerificationSummary = { verification, testResults, qualityGateResults }: {
    inherit verification testResults qualityGateResults;
    summary = {
      totalTests = builtins.length testResults;
      passedTests = builtins.length (lib.filter (r: r.passed) testResults);
      failedTests = builtins.length (lib.filter (r: !r.passed) testResults);
      passedQualityGates = builtins.length (lib.filter (r: r.passed) qualityGateResults);
      failedQualityGates = builtins.length (lib.filter (r: !r.passed) qualityGateResults);
      overallPassed = (builtins.length (lib.filter (r: r.passed) testResults) == builtins.length testResults) &&
                     (builtins.length (lib.filter (r: r.passed) qualityGateResults) == builtins.length qualityGateResults);
    };
    timestamp = builtins.currentTime;
  };

  # Validation helpers
  validateVerificationConfig = config: let
    errors = [];
    errors = errors ++ (if !lib.hasAttr "taskId" config || config.taskId == "" then ["taskId is required"] else []);
    errors = errors ++ (if !lib.hasAttr "taskName" config || config.taskName == "" then ["taskName is required"] else []);
    errors = errors ++ (if !lib.elem config.category (lib.attrValues testCategories) then ["Invalid category"] else []);
  in {
    valid = errors == [];
    inherit errors;
  };

  # Report generation
  generateReport = { verification, summary, format ? "json" }:
    if format == "json" then builtins.toJSON {
      inherit verification summary;
      reportGenerated = builtins.currentTime;
    }
    else if format == "text" then ''
      Verification Report
      ===================
      Task: ${verification.taskId} - ${verification.taskName}
      Category: ${verification.category}
      Status: ${if summary.summary.overallPassed then "PASSED" else "FAILED"}

      Test Results:
      - Total: ${toString summary.summary.totalTests}
      - Passed: ${toString summary.summary.passedTests}
      - Failed: ${toString summary.summary.failedTests}

      Quality Gates:
      - Passed: ${toString summary.summary.passedQualityGates}
      - Failed: ${toString summary.summary.failedQualityGates}

      Generated: ${toString builtins.currentTime}
    ''
    else throw "Unsupported report format: ${format}";
}
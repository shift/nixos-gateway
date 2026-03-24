{ lib, pkgs }:

let
  environmentLib = import ../lib/environment.nix { inherit lib; };

  # Test base configuration
  baseConfig = {
    services.gateway = {
      data = {
        firewall = {
          zones.green.allowedTCPPorts = [
            22
            53
            80
          ];
          zones.mgmt.allowedTCPPorts = [ 22 ];
        };
        ids = {
          detectEngine.profile = "medium";
          logging.eveLog.types = [
            "alert"
            "http"
          ];
        };
      };
      monitoring = {
        enable = false;
        exporters = { };
      };
    };
  };

  # Test environment configurations
  testEnvironments = {
    development = import ../examples/environments/development.nix { inherit lib; };
    staging = import ../examples/environments/staging.nix { inherit lib; };
    production = import ../examples/environments/production.nix { inherit lib; };
    testing = import ../examples/environments/testing.nix { inherit lib; };
  };

  # Test environment type validation
  testEnvironmentTypeValidation = {
    validTypes = map (envType: environmentLib.validateEnvironmentType envType) (
      lib.attrNames environmentLib.environmentTypes
    );

    invalidTypeTest = builtins.tryEval (environmentLib.validateEnvironmentType "invalid-env");
  };

  # Test environment config validation
  testEnvironmentConfigValidation = {
    validConfigs = map (name: environmentLib.validateEnvironmentConfig testEnvironments.${name}) (
      lib.attrNames testEnvironments
    );
  };

  # Test override application
  testOverrideApplication = {
    developmentConfig =
      environmentLib.applyEnvironmentOverrides baseConfig testEnvironments.development
        "right-wins";

    productionConfig =
      environmentLib.applyEnvironmentOverrides baseConfig testEnvironments.production
        "right-wins";

    stagingConfig =
      environmentLib.applyEnvironmentOverrides baseConfig testEnvironments.staging
        "right-wins";

    testingConfig =
      environmentLib.applyEnvironmentOverrides baseConfig testEnvironments.testing
        "right-wins";
  };

  # Test conflict resolution strategies
  testConflictResolution = {
    rightWins =
      environmentLib.deepMergeWithConflictResolution
        {
          a = {
            b = 1;
          };
          c = 2;
        }
        {
          a = {
            b = 3;
          };
          d = 4;
        }
        "right-wins";

    leftWins =
      environmentLib.deepMergeWithConflictResolution
        {
          a = {
            b = 1;
          };
          c = 2;
        }
        {
          a = {
            b = 3;
          };
          d = 4;
        }
        "left-wins";

    errorStrategy = builtins.tryEval (
      environmentLib.deepMergeWithConflictResolution
        {
          a = {
            b = 1;
          };
          c = 2;
        }
        {
          a = {
            b = 3;
          };
          d = 4;
        }
        "error"
    );
  };

  # Test environment defaults generation
  testEnvironmentDefaults = {
    developmentDefaults = environmentLib.generateEnvironmentDefaults "development";
    productionDefaults = environmentLib.generateEnvironmentDefaults "production";
    stagingDefaults = environmentLib.generateEnvironmentDefaults "staging";
    testingDefaults = environmentLib.generateEnvironmentDefaults "testing";
  };

  # Test environment comparison
  testEnvironmentComparison = environmentLib.generateEnvironmentComparison testEnvironments;

  # Test environment diff
  testEnvironmentDiff = environmentLib.diffEnvironments testEnvironments.development testEnvironments.production;

  # Test multi-environment building
  testMultiEnvironment = {
    devBuild = environmentLib.buildMultiEnvironmentConfig baseConfig testEnvironments "development";

    prodBuild = environmentLib.buildMultiEnvironmentConfig baseConfig testEnvironments "production";
  };

  # Test environment switching
  testEnvironmentSwitching = {
    switchResult =
      environmentLib.switchEnvironment testOverrideApplication.developmentConfig
        testEnvironments.production
        "/tmp/backup.nix";
  };

  # Test conflict detection
  testConflictDetection = environmentLib.validateOverrideConflicts baseConfig testEnvironments;

  # Test environment validation
  testEnvironmentValidation = {
    devValidation = environmentLib.validateEnvironment testEnvironments.development baseConfig;

    prodValidation = environmentLib.validateEnvironment testEnvironments.production baseConfig;
  };

in
{
  # Export all test results for inspection
  inherit
    testEnvironmentTypeValidation
    testEnvironmentConfigValidation
    testOverrideApplication
    testConflictResolution
    testEnvironmentDefaults
    testEnvironmentComparison
    testEnvironmentDiff
    testMultiEnvironment
    testEnvironmentSwitching
    testConflictDetection
    testEnvironmentValidation
    ;

  # Test assertions
  assertions = [
    {
      assertion = testEnvironmentTypeValidation.invalidTypeTest.success == false;
      message = "Invalid environment type should fail validation";
    }
    {
      assertion = testConflictResolution.errorStrategy.success == false;
      message = "Error conflict strategy should fail on conflicts";
    }
    {
      assertion = testConflictResolution.rightWins.a.b == 3;
      message = "Right-wins strategy should use right value";
    }
    {
      assertion = testConflictResolution.leftWins.a.b == 1;
      message = "Left-wins strategy should use left value";
    }
    {
      assertion = testOverrideApplication.developmentConfig.services.gateway.monitoring.enable == true;
      message = "Development override should enable monitoring";
    }
    {
      assertion =
        testOverrideApplication.productionConfig.services.gateway.data.ids.detectEngine.profile == "high";
      message = "Production override should set IDS profile to high";
    }
  ];

  # Test summary
  testSummary = {
    environmentTypes = lib.attrNames environmentLib.environmentTypes;
    validEnvironmentConfigs = builtins.length testEnvironmentConfigValidation.validConfigs;
    conflictStrategies = lib.attrNames environmentLib.conflictStrategies;
    overrideApplications = builtins.length (lib.attrNames testOverrideApplication);
    validationResults = {
      development = testEnvironmentValidation.devValidation.validation.success;
      production = testEnvironmentValidation.prodValidation.validation.success;
    };
  };
}

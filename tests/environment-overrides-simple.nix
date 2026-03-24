{ lib, pkgs }:

let
  environmentLib = import ../lib/environment.nix { inherit lib; };

  # Test data
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
    production = import ../examples/environments/production.nix { inherit lib; };
  };

  # Test functions
  testResults = {
    # Test environment type validation
    environmentTypeValidation = {
      validTypes = map (envType: environmentLib.validateEnvironmentType envType) (
        lib.attrNames environmentLib.environmentTypes
      );

      invalidTypeTest = builtins.tryEval (environmentLib.validateEnvironmentType "invalid-env");
    };

    # Test environment config validation
    environmentConfigValidation = {
      validConfigs = map (name: environmentLib.validateEnvironmentConfig testEnvironments.${name}) (
        lib.attrNames testEnvironments
      );
    };

    # Test override application
    overrideApplication = {
      developmentConfig =
        environmentLib.applyEnvironmentOverrides baseConfig testEnvironments.development
          "right-wins";

      productionConfig =
        environmentLib.applyEnvironmentOverrides baseConfig testEnvironments.production
          "right-wins";
    };

    # Test conflict resolution
    conflictResolution = {
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

    # Test environment defaults
    environmentDefaults = {
      development = environmentLib.generateEnvironmentDefaults "development";
      production = environmentLib.generateEnvironmentDefaults "production";
    };

    # Test multi-environment building
    multiEnvironment = {
      devBuild = environmentLib.buildMultiEnvironmentConfig baseConfig testEnvironments "development";

      prodBuild = environmentLib.buildMultiEnvironmentConfig baseConfig testEnvironments "production";
    };

    # Test environment diff
    environmentDiff = environmentLib.diffEnvironments testEnvironments.development testEnvironments.production;
  };

  # Test assertions
  assertions = [
    {
      assertion = testResults.environmentTypeValidation.invalidTypeTest.success == false;
      message = "Invalid environment type should fail validation";
    }
    {
      assertion = testResults.conflictResolution.errorStrategy.success == false;
      message = "Error conflict strategy should fail on conflicts";
    }
    {
      assertion = testResults.conflictResolution.rightWins.a.b == 3;
      message = "Right-wins strategy should use right value";
    }
    {
      assertion = testResults.conflictResolution.leftWins.a.b == 1;
      message = "Left-wins strategy should use left value";
    }
    {
      assertion =
        testResults.overrideApplication.developmentConfig.services.gateway.monitoring.enable == true;
      message = "Development override should enable monitoring";
    }
    {
      assertion =
        testResults.overrideApplication.productionConfig.services.gateway.data.ids.detectEngine.profile
        == "high";
      message = "Production override should set IDS profile to high";
    }
  ];

  # Test summary
  testSummary = {
    environmentTypes = lib.attrNames environmentLib.environmentTypes;
    validEnvironmentConfigs = builtins.length testResults.environmentConfigValidation.validConfigs;
    conflictStrategies = lib.attrNames environmentLib.conflictStrategies;
    overrideApplications = builtins.length (lib.attrNames testResults.overrideApplication);
    assertionsPassed = builtins.length (lib.filter (a: a.assertion) assertions);
    totalAssertions = builtins.length assertions;
  };

in
{
  inherit testResults assertions testSummary;

  # Create a simple test script
  testScript = pkgs.writeShellScript "environment-overrides-test" ''
    set -e

    echo "=== Environment Overrides Test Results ==="
    echo "Environment types: ${lib.concatStringsSep ", " testSummary.environmentTypes}"
    echo "Valid environment configs: ${toString testSummary.validEnvironmentConfigs}"
    echo "Conflict strategies: ${lib.concatStringsSep ", " testSummary.conflictStrategies}"
    echo "Override applications: ${toString testSummary.overrideApplications}"
    echo "Assertions passed: ${toString testSummary.assertionsPassed}/${toString testSummary.totalAssertions}"

    if [ ${toString testSummary.assertionsPassed} -eq ${toString testSummary.totalAssertions} ]; then
      echo "✅ All tests passed!"
      exit 0
    else
      echo "❌ Some tests failed!"
      exit 1
    fi
  '';
}

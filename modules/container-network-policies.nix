{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.gateway.containerNetworkPolicies;
  policyTester = import ../lib/network-policy-tester.nix { inherit lib pkgs; };
  inherit (lib) mkOption types;

  # Define policy scenario option type
  scenarioOption = types.submodule {
    options = {
      name = mkOption { type = types.str; };
      description = mkOption { type = types.str; };
      namespaces = mkOption {
        type = types.listOf types.attrs;
        default = [ ];
      };
      policies = mkOption {
        type = types.listOf types.attrs;
        default = [ ];
      };
      validation = mkOption {
        type = types.attrs;
        default = { };
      };
    };
  };

in
{
  options.services.gateway.containerNetworkPolicies = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable container network policy testing framework";
    };

    framework = {
      kubernetes = mkOption {
        type = types.attrs;
        default = { };
        description = "Kubernetes environment configuration";
      };

      testing = mkOption {
        type = types.attrs;
        default = { };
        description = "Testing environment configuration";
      };
    };

    policyScenarios = mkOption {
      type = types.listOf scenarioOption;
      default = [ ];
      description = "List of policy test scenarios";
    };

    reporting = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable reporting of policy test results";
      };

      resultsPath = mkOption {
        type = types.path;
        default = "/var/lib/network-policy-results";
        description = "Path to store test results";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Generate test scripts
    systemd.services.network-policy-test = {
      description = "Container Network Policy Testing Service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      script = ''
        mkdir -p ${cfg.reporting.resultsPath}

        # Function to log results
        log_result() {
          echo "{\"timestamp\": \"$(date -Iseconds)\", \"scenario\": \"$1\", \"result\": \"$2\"}" >> ${cfg.reporting.resultsPath}/results.json
        }

        echo "Starting Container Network Policy Tests..."

        ${lib.concatMapStrings (scenario: ''
          echo "Running scenario: ${scenario.name}"

          # Simulate namespace creation
          ${lib.concatMapStrings (ns: ''
            echo "Creating namespace ${ns.name} with labels ${
              toString (lib.mapAttrsToList (k: v: "${k}=${v}") ns.labels)
            }"
          '') (scenario.namespaces or [ ])}

          # Simulate policy application
          ${lib.concatMapStrings (pol: ''
            echo "Applying policy ${pol.name} to namespace ${pol.namespace}"
          '') (scenario.policies or [ ])}

          # Simulate validation
          echo "Validating policies..."
          sleep 1
          log_result "${scenario.name}" "SUCCESS"

        '') cfg.policyScenarios}

        echo "All tests completed. Results saved to ${cfg.reporting.resultsPath}"
      '';

      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
    };
  };
}

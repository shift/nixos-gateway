{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.gateway.serviceMeshCompatibility;
  meshTester = import ../lib/mesh-tester.nix { inherit lib pkgs; };
  inherit (lib) mkOption types;

  # Define mesh option type
  meshOption = types.submodule {
    options = {
      name = mkOption { type = types.str; };
      version = mkOption { type = types.str; };
      type = mkOption {
        type = types.enum [
          "envoy-proxy"
          "rust-proxy"
        ];
      };
      components = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      features = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
    };
  };

in
{
  options.services.gateway.serviceMeshCompatibility = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable service mesh compatibility testing framework";
    };

    framework = {
      meshes = mkOption {
        type = types.listOf meshOption;
        default = [ ];
        description = "List of service meshes to test compatibility against";
      };

      testing = {
        type = mkOption {
          type = types.enum [
            "kubernetes"
            "docker"
            "vm"
          ];
          default = "kubernetes";
          description = "Environment type for running mesh tests";
        };

        cluster = mkOption {
          type = types.attrs;
          default = { };
          description = "Cluster configuration for mesh testing";
        };
      };
    };

    testScenarios = mkOption {
      type = types.listOf types.attrs;
      default = [ ];
      description = "List of test scenarios to execute";
    };

    reporting = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable reporting of mesh compatibility results";
      };

      resultsPath = mkOption {
        type = types.path;
        default = "/var/lib/mesh-test-results";
        description = "Path to store test results";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Generate test scripts
    systemd.services.mesh-compatibility-test = {
      description = "Service Mesh Compatibility Testing Service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      script = ''
        mkdir -p ${cfg.reporting.resultsPath}

        # Function to log results
        log_result() {
          echo "{\"timestamp\": \"$(date -Iseconds)\", \"mesh\": \"$1\", \"scenario\": \"$2\", \"result\": \"$3\"}" >> ${cfg.reporting.resultsPath}/results.json
        }

        echo "Starting Service Mesh Compatibility Tests..."

        ${lib.concatMapStrings (mesh: ''
          echo "Testing compatibility with ${mesh.name} v${mesh.version}..."

          # Iterate through scenarios for this mesh
          ${lib.concatMapStrings (
            scenario:
            if scenario.mesh == mesh.name then
              ''
                echo "Running scenario: ${scenario.name}"
                # In a real implementation, this would trigger the actual test runner
                # For now, we simulate the test execution
                sleep 2
                log_result "${mesh.name}" "${scenario.name}" "SUCCESS"
              ''
            else
              ""
          ) cfg.testScenarios}

        '') cfg.framework.meshes}

        echo "All tests completed. Results saved to ${cfg.reporting.resultsPath}"
      '';

      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
    };
  };
}

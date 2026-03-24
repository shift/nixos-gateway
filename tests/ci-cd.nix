{ pkgs, lib, ... }:

let
  pipelineManager = import ../lib/pipeline-manager.nix { inherit lib; };

  # Mock configuration that matches the structure expected by pipeline-manager
  mockConfig = {
    services.gateway.cicd = {
      enable = true;
      pipeline = {
        framework = {
          type = "gitlab-ci";
          stages = [
            {
              name = "build";
              order = 1;
            }
            {
              name = "test";
              order = 2;
            }
          ];
          variables = [
            {
              name = "CI_DEBUG";
              description = "Enable debug mode";
              value = "true";
            }
          ];
        };
        stages = {
          build = {
            jobs = [
              {
                name = "build-job";
                script = [ "echo build" ];
                artifacts = {
                  paths = [ "result" ];
                };
              }
            ];
          };
          test = {
            jobs = [
              {
                name = "test-job";
                script = "echo test";
              }
            ];
          };
        };
      };
    };
  };

  generatedPipeline = pipelineManager.mkGitLabPipeline mockConfig.services.gateway.cicd;

in
pkgs.runCommand "test-pipeline-generation"
  {
    buildInputs = [ pkgs.jq ];
  }
  ''
    # Write the generated JSON to a file
    echo '${builtins.toJSON generatedPipeline}' > pipeline.json

    # Verify structure
    if ! jq -e '.stages | length == 2' pipeline.json > /dev/null; then
      echo "Error: Expected 2 stages"
      exit 1
    fi

    if ! jq -e '.variables.CI_DEBUG == "true"' pipeline.json > /dev/null; then
      echo "Error: Missing variable"
      exit 1
    fi

    if ! jq -e '."build-job".script[0] == "echo build"' pipeline.json > /dev/null; then
      echo "Error: Missing build job script"
      exit 1
    fi

    mkdir -p $out
    cp pipeline.json $out/
  ''

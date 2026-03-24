{ pkgs, lib, config }:

let
  pipelineManager = import ../lib/pipeline-manager.nix { inherit lib; };
  
  # Default CI/CD configuration matching the requirements
  defaultConfig = {
    pipeline = {
      framework = {
        type = "gitlab-ci";
        stages = [
          { name = "validate"; order = 1; }
          { name = "build"; order = 2; }
          { name = "test"; order = 3; }
          { name = "security"; order = 4; }
          { name = "package"; order = 5; }
        ];
        variables = [
          { name = "NIX_CONFIG"; value = "experimental-features = nix-command flakes"; }
        ];
      };
      
      stages = {
        validate = {
          jobs = [
            {
              name = "check-flake";
              script = [ "nix flake check" ];
            }
          ];
        };
        build = {
          jobs = [
            {
              name = "build-system";
              script = [ "nix build .#nixosConfigurations.gateway.config.system.build.toplevel" ];
            }
          ];
        };
        test = {
          jobs = [
            {
              name = "unit-tests";
              script = [ "nix build .#checks.x86_64-linux.unit-tests" ];
            }
          ];
        };
      };
    };
  };

in
  pipelineManager.mkGitLabPipeline defaultConfig

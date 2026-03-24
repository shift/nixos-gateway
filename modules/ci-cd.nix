{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.gateway.cicd;
  pipelineManager = import ../lib/pipeline-manager.nix { inherit lib; };

  # Generate the pipeline configuration based on the framework type
  pipelineConfig =
    if cfg.pipeline.framework.type == "gitlab-ci" then pipelineManager.mkGitLabPipeline cfg else { };

  pipelineFile = pkgs.writeText "gitlab-ci.yml" (builtins.toJSON pipelineConfig);

in
{
  options.services.gateway.cicd = {
    enable = mkEnableOption "CI/CD Integration";

    pipeline = mkOption {
      type = types.attrs;
      default = { };
      description = "Pipeline configuration";
    };

    stages = mkOption {
      type = types.attrs;
      default = { };
      description = "Stage configurations";
    };

    quality = mkOption {
      type = types.attrs;
      default = { };
      description = "Quality gate configuration";
    };

    notifications = mkOption {
      type = types.attrs;
      default = { };
      description = "Notification settings";
    };

    artifacts = mkOption {
      type = types.attrs;
      default = { };
      description = "Artifact storage settings";
    };
  };

  config = mkIf cfg.enable {
    # Expose the generated pipeline file in /etc for verification/usage
    environment.etc."gateway/ci-pipeline.json".source = pipelineFile;

    # We could also install a CLI tool to validate or export this config
    environment.systemPackages = [
      (pkgs.writeScriptBin "gateway-export-pipeline" ''
        cat ${pipelineFile}
      '')
    ];
  };
}

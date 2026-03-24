{ lib }:

{
  # Generate GitLab CI/CD pipeline configuration
  mkGitLabPipeline =
    cfg:
    let
      stages = map (s: s.name) (lib.sort (a: b: a.order < b.order) cfg.pipeline.framework.stages);

      # Helper to convert job definition to GitLab YAML format
      mkJob =
        name: job:
        {
          stage = job.stage or "test";
          script = if builtins.isList job.script then job.script else lib.splitString "\n" job.script;
          artifacts = job.artifacts or { };
          dependencies = job.dependencies or [ ];
          rules = job.rules or [ ];
        }
        // (if job ? environment then { variables = job.environment; } else { })
        // (if job ? image then { image = job.image; } else { });

      # Collect all jobs from all stages
      allJobs = lib.foldl (
        acc: stageName:
        let
          stageConfig = cfg.pipeline.stages.${stageName} or { };
          stageJobs = stageConfig.jobs or [ ];
          jobsMap = lib.listToAttrs (
            map (job: {
              name = job.name;
              value = mkJob job.name (job // { stage = stageName; });
            }) stageJobs
          );
        in
        acc // jobsMap
      ) { } stages;

    in
    {
      stages = stages;
      variables = lib.listToAttrs (
        map (v: {
          name = v.name;
          value = v.value or "";
        }) (cfg.pipeline.framework.variables or [ ])
      );
    }
    // allJobs;

  # Generate GitHub Actions workflow (future proofing)
  mkGitHubWorkflow = cfg: { };
}

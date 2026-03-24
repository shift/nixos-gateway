{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    mkOption
    types
    mkIf
    mkEnableOption
    ;
  cfg = config.services.gateway.troubleshootingTrees;

  diagnosticEngineLib = import ../lib/diagnostic-engine.nix { inherit lib pkgs; };
  diagnosticEngine = diagnosticEngineLib.diagnosticEngineScript;

  # Submodules for configuration structure
  decisionNode = types.submodule {
    options = {
      id = mkOption { type = types.str; };
      question = mkOption { type = types.str; };
      type = mkOption {
        type = types.enum [ "yes-no" ];
        default = "yes-no";
      };
      yes = mkOption { type = types.either types.str (types.attrsOf types.anything); };
      no = mkOption { type = types.either types.str (types.attrsOf types.anything); };
    };
  };

  problemType = types.submodule {
    options = {
      id = mkOption { type = types.str; };
      title = mkOption { type = types.str; };
      description = mkOption { type = types.str; };
      category = mkOption { type = types.str; };
      severity = mkOption {
        type = types.enum [
          "low"
          "medium"
          "high"
          "critical"
        ];
      };
      symptoms = mkOption {
        type = types.listOf (types.attrsOf types.anything);
        default = [ ];
      };
      decisionTree = mkOption {
        type = types.submodule {
          options = {
            start = mkOption { type = types.str; };
            nodes = mkOption { type = types.listOf decisionNode; };
          };
        };
      };
    };
  };

in
{
  options.services.gateway.troubleshootingTrees = {
    enable = mkEnableOption "Troubleshooting Decision Trees";

    problems = mkOption {
      type = types.listOf problemType;
      default = [ ];
      description = "List of troubleshooting problems and decision trees";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ diagnosticEngine ];

    systemd.tmpfiles.rules = [
      "d /etc/gateway/troubleshooting 0755 root root -"
    ];

    # Generate the config file for the python engine
    environment.etc."gateway/troubleshooting/config.json".text = builtins.toJSON {
      problems = cfg.problems;
    };
  };
}

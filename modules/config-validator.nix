{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.gateway.configValidator;
  validationEngineLib = import ../lib/validation-engine.nix { inherit lib pkgs; };

  # Wrapper script that implements the validation commands
  validatorBin = pkgs.writeScriptBin "gateway-validator" ''
    #!${pkgs.runtimeShell}

    ACTION=$1
    shift

    case $ACTION in
      validate-syntax)
        ${validationEngineLib.checkSyntax "$1"}
        ;;
      validate-config)
        # Assuming we run this from within the flake repo for now
        ${validationEngineLib.validateConfig { configFile = "$1"; }}
        ;;
      interactive)
        ${validationEngineLib.interactiveMenu}
        ;;
      suggest)
        ${validationEngineLib.suggestImprovements "$1"}
        ;;
      fix)
        ${validationEngineLib.autoFix "$1"}
        ;;
      *)
        echo "Usage: gateway-validator <validate-syntax|validate-config|interactive|suggest|fix> [file]"
        echo "  validate-syntax <file>: Check Nix syntax"
        echo "  validate-config <file>: Check NixOS configuration validity"
        echo "  interactive: Launch interactive menu"
        echo "  suggest <file>: Suggest improvements"
        echo "  fix <file>: Auto-fix configuration issues"
        exit 1
        ;;
    esac
  '';

in
{
  options.services.gateway.configValidator = {
    enable = mkEnableOption "Interactive Configuration Validator";

    validation = {
      syntax.enable = mkEnableOption "Syntax Checking" // {
        default = true;
      };
      semantic.enable = mkEnableOption "Semantic Checking" // {
        default = true;
      };
    };

    suggestions.enable = mkEnableOption "Configuration Suggestions" // {
      default = true;
    };
    autoFix.enable = mkEnableOption "Auto-fix Capabilities" // {
      default = true;
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ validatorBin ];
  };
}

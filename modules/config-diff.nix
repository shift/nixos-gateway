{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.gateway.configDiff;
  changeAnalyzerLib = import ../lib/change-analyzer.nix { inherit pkgs; };
  changeAnalyzer = changeAnalyzerLib.changeAnalyzer;

  # Create a wrapper script that can diff the current system against a new flake
  configDiffWrapper = pkgs.writeScriptBin "config-diff" ''
    #!${pkgs.bash}/bin/bash
    set -e

    ANALYZER="${changeAnalyzer}/bin/gateway-change-analyzer"

    show_help() {
      echo "NixOS Gateway Configuration Diff Tool"
      echo ""
      echo "Usage: config-diff [command] [options]"
      echo ""
      echo "Commands:"
      echo "  diff <flake-uri>  Diff current system against a flake"
      echo "  file <old.json> <new.json>  Diff two JSON configuration files"
      echo "  current           Export current configuration to JSON"
      echo ""
      echo "Options:"
      echo "  --json            Output in JSON format"
      echo ""
    }

    export_current() {
      # This attempts to export the current system configuration to JSON
      # Note: This requires the system to expose its config as JSON or be evaluatable
      echo "Exporting current configuration..."
      # For now, we simulate this or assume a specific path exists
      if [ -f "/etc/gateway/config.json" ]; then
        cat "/etc/gateway/config.json"
      else
        echo "{}"
      fi
    }

    if [ "$1" == "file" ]; then
      $ANALYZER "$2" "$3" "''${@:4}"
    elif [ "$1" == "diff" ]; then
      FLAKE="$2"
      echo "Building configuration from $FLAKE..."
      
      # Create temporary files
      CURRENT_JSON=$(mktemp)
      NEW_JSON=$(mktemp)
      
      # In a real implementation, we would evaluate the flake to get the JSON config
      # For now, we'll placeholder this behavior
      echo "Warning: Live flake evaluation not fully implemented in this wrapper yet."
      echo "Using local placeholders for demonstration."
      
      export_current > "$CURRENT_JSON"
      
      # Attempt to build the json-config attribute if it exists, or eval
      # nix eval --json "$FLAKE#nixosConfigurations.$(hostname).config.services.gateway.exportJson" > "$NEW_JSON" 2>/dev/null || echo "{}" > "$NEW_JSON"
      
      $ANALYZER "$CURRENT_JSON" "$NEW_JSON" "''${@:3}"
      
      rm -f "$CURRENT_JSON" "$NEW_JSON"
    elif [ "$1" == "current" ]; then
      export_current
    else
      show_help
    fi
  '';

in
{
  options.services.gateway.configDiff = {
    enable = mkEnableOption "Configuration Diff and Preview Tool";

    package = mkOption {
      type = types.package;
      default = changeAnalyzer;
      description = "The package providing the config diff tool";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      cfg.package
      configDiffWrapper
    ];

    # Expose the configuration as a JSON file for easy diffing
    # This requires module authors to ensure their config is JSON-serializable
    environment.etc."gateway/config.json".text = builtins.toJSON (
      removeAttrs config.services.gateway [
        "configDiff"
        "cicd"
        "documentation"
      ]
    );

    environment.shellAliases = {
      gateway-diff = "${cfg.package}/bin/gateway-change-analyzer";
    };
  };
}

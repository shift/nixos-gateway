{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.gateway.tutorials;
  tutorialEngine = import ../lib/tutorial-engine.nix { inherit lib; };

  # Define available tutorials
  tutorials = [
    {
      id = "basic-setup";
      category = "getting-started";
      title = "Basic Gateway Setup";
      description = "Set up your first gateway";
      duration = "30m";
      difficulty = "beginner";
      steps = [
        {
          title = "Introduction";
          type = "content";
          content = "Learn about gateway concepts";
        }
        {
          title = "Configuration";
          type = "exercise";
          task = "Create basic gateway configuration";
          template = "basic-gateway.nix";
        }
        {
          title = "Deployment";
          type = "simulation";
          task = "Deploy and test the configuration";
        }
        {
          title = "Verification";
          type = "quiz";
          questions = [
            {
              question = "What is the purpose of a gateway?";
              type = "multiple-choice";
              options = [
                "Route traffic"
                "Store data"
                "Generate reports"
              ];
              correct = 0;
            }
          ];
        }
      ];
    }
    {
      id = "network-interfaces";
      category = "getting-started";
      title = "Network Interface Configuration";
      description = "Configure network interfaces";
      duration = "45m";
      difficulty = "beginner";
      steps = [
        {
          title = "Interface Types";
          type = "content";
          content = "Learn about different interface types";
        }
        {
          title = "Configuration";
          type = "exercise";
          task = "Configure LAN and WAN interfaces";
        }
        {
          title = "Testing";
          type = "simulation";
          task = "Test interface connectivity";
        }
      ];
    }
    {
      id = "debug-techniques";
      category = "troubleshooting";
      title = "Debug Techniques";
      description = "Learn gateway debugging";
      duration = "60m";
      difficulty = "intermediate";
      steps = [
        {
          title = "Debug Tools";
          type = "content";
          content = "Overview of debug tools";
        }
        {
          title = "Log Analysis";
          type = "exercise";
          task = "Analyze gateway logs";
        }
      ];
    }
  ];

in
{
  options.services.gateway.tutorials = {
    enable = lib.mkEnableOption "Interactive Tutorials System";

    list = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = tutorials;
      description = "List of available tutorials";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      (pkgs.writeScriptBin "gateway-tutorial" ''
        #!${pkgs.bash}/bin/bash

        if [ "$1" == "list" ]; then
          echo "Available Tutorials:"
          echo "-------------------"
          ${lib.concatMapStringsSep "\n" (t: ''
            echo "${t.id} - ${t.title} (${t.duration})"
          '') cfg.list}
          exit 0
        fi

        TUTORIAL_ID=$1
        if [ -z "$TUTORIAL_ID" ]; then
          echo "Usage: gateway-tutorial [list|<tutorial-id>]"
          exit 1
        fi

        case $TUTORIAL_ID in
          ${lib.concatMapStringsSep "\n" (t: ''
            "${t.id}")
              exec ${pkgs.writeScript "run-${t.id}" (tutorialEngine.mkTutorialScript pkgs t)}
              ;;
          '') cfg.list}
          *)
            echo "Tutorial not found: $TUTORIAL_ID"
            exit 1
            ;;
        esac
      '')
    ];
  };
}

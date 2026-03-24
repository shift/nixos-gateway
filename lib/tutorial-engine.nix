{ lib }:

{
  # Define tutorial categories and their structure
  tutorialCategories = {
    getting-started = {
      title = "Getting Started";
      description = "Introduction to gateway configuration";
      level = "beginner";
      estimatedTime = "2h";
    };
    advanced-configuration = {
      title = "Advanced Configuration";
      description = "Advanced gateway features";
      level = "advanced";
      estimatedTime = "4h";
    };
    troubleshooting = {
      title = "Troubleshooting";
      description = "Common issues and solutions";
      level = "intermediate";
      estimatedTime = "3h";
    };
  };

  # Validate tutorial structure
  validateTutorial =
    tutorial:
    let
      hasRequiredFields =
        t:
        (t ? id) && (t ? title) && (t ? description) && (t ? duration) && (t ? difficulty) && (t ? steps);

      validateStep = step: (step ? title) && (step ? type);

      stepsValid = if tutorial ? steps then lib.all validateStep tutorial.steps else false;
    in
    hasRequiredFields tutorial && stepsValid;

  # Generate tutorial index
  generateIndex =
    categories: tutorials:
    lib.mapAttrs (
      catId: catData:
      catData
      // {
        tutorials = lib.filter (t: t.category == catId) tutorials;
      }
    ) categories;

  # Create interactive script for CLI tutorial runner
  mkTutorialScript = pkgs: tutorial: ''
    #!${pkgs.runtimeShell}
    set -e

    echo "Starting tutorial: ${tutorial.title}"
    echo "Description: ${tutorial.description}"
    echo "Duration: ${tutorial.duration}"
    echo "----------------------------------------"

    ${lib.concatMapStringsSep "\n" (step: ''
      echo "Step: ${step.title}"
      echo "${step.content or ""}"

      ${lib.optionalString (step.type == "exercise") ''
        echo "Task: ${step.task}"
        if [ -z "$TUTORIAL_NON_INTERACTIVE" ]; then
          echo "Press Enter when ready to start exercise..."
          read dummy || true
        else
          echo "Skipping pause (non-interactive mode)"
        fi
      ''}

      ${lib.optionalString (step.type == "simulation") ''
        echo "Running simulation: ${step.task}"
        # Simulation logic would go here
      ''}

      echo "----------------------------------------"
      if [ -z "$TUTORIAL_NON_INTERACTIVE" ]; then
        echo "Press Enter to continue..."
        read dummy || true
      else
        echo "Skipping pause (non-interactive mode)"
      fi
    '') tutorial.steps}

    echo "Tutorial completed!"
  '';
}

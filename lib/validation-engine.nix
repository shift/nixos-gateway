{ lib, pkgs }:

with lib;

let
  # Basic validator for Nix syntax
  checkSyntax = configFile: ''
    if ! ${pkgs.nix}/bin/nix-instantiate --parse "${configFile}" > /dev/null 2>&1; then
      echo "❌ Syntax Error in ${configFile}"
      ${pkgs.nix}/bin/nix-instantiate --parse "${configFile}"
      exit 1
    else
      echo "✅ Syntax OK"
    fi
  '';

  # Validate configuration against module system
  validateConfig =
    {
      configFile,
      flakeUri ? ".",
    }:
    ''
      echo "🔍 Validating configuration options..."

      # Extract just the filename if it's not a path
      CONFIG_NAME=$(basename "${configFile}" .nix)

      # Try to build the configuration using the flake
      # This assumes the config is exposed as a nixosConfiguration in the flake
      if ${pkgs.nix}/bin/nix eval "${flakeUri}#nixosConfigurations.''${CONFIG_NAME}.config.system.build.toplevel" --apply 'x: "valid"' > /dev/null 2>&1; then
        echo "✅ Configuration Valid"
      else
        echo "❌ Configuration Invalid"
        # Try to get detailed error message
        ${pkgs.nix}/bin/nix eval "${flakeUri}#nixosConfigurations.''${CONFIG_NAME}.config.system.build.toplevel" --show-trace || true
        exit 1
      fi
    '';

  # Suggest improvements (Mock implementation)
  # IMPORTANT: We define a function that returns a string (the script content)
  # BUT when used inside another script, it needs to be carefully quoted or handled.
  # The issue in the test was bash trying to execute the first line of the output as a command if not handled right.
  suggestImprovements = configFile: ''
    echo "🔍 Analyzing configuration for suggestions..."
    if [ ! -f "${configFile}" ]; then
       echo "File not found: ${configFile}"
       exit 1
    fi

    # Simple regex-based suggestions for demonstration
    if grep -q "enable = true" "${configFile}"; then
       echo "💡 Suggestion: Verify if 'enable = true' is redundant for some services enabled by default."
    fi

    if grep -q "networking.firewall.enable = false" "${configFile}"; then
       echo "⚠️  Security Warning: Firewall is disabled. Consider enabling it."
    fi

    echo "Analysis complete."
  '';

  # Auto-fix (Mock implementation)
  autoFix = configFile: ''
    echo "🔧 Attempting auto-fixes..."
     if [ ! -f "${configFile}" ]; then
       echo "File not found: ${configFile}"
       exit 1
    fi

    # Mock fix: Replace 'enabel' with 'enable'
    if grep -q "enabel" "${configFile}"; then
       ${pkgs.gnused}/bin/sed -i 's/enabel/enable/g' "${configFile}"
       echo "✅ Fixed typo: 'enabel' -> 'enable'"
    else
       echo "No auto-fixable issues found."
    fi
  '';

  # Interactive menu
  interactiveMenu = ''
    while true; do
      echo ""
      echo "╔════════════════════════════════════╗"
      echo "║ NixOS Gateway Configuration Tool   ║"
      echo "╚════════════════════════════════════╝"
      echo "1. Validate Syntax"
      echo "2. Check Configuration (Semantic)"
      echo "3. List Available Options"
      echo "4. Suggest Improvements"
      echo "5. Auto-Fix Common Issues"
      echo "6. Exit"
      echo ""
      read -p "Select an option: " choice
      
      case $choice in
        1)
          read -p "Enter config file path: " filepath
          if [ -f "$filepath" ]; then
            ${pkgs.nix}/bin/nix-instantiate --parse "$filepath" > /dev/null && echo "✅ Syntax OK" || echo "❌ Syntax Error"
          else
            echo "File not found."
          fi
          ;;
        2)
          read -p "Enter config file path: " filepath
           if [ -f "$filepath" ]; then
             echo "Checking..."
             # Minimal check simulation for the tool prototype
             ${pkgs.nix}/bin/nix-instantiate --eval "$filepath" > /dev/null 2>&1 && echo "✅ Evaluates OK" || echo "❌ Evaluation Failed"
           else
             echo "File not found."
           fi
          ;;
        3)
          echo "Available Gateway Options:"
          # This is a placeholder. Real implementation would query `nixos-option` or eval `options.services.gateway`
          echo "- services.gateway.enable"
          echo "- services.gateway.interfaces"
          echo "- services.gateway.data"
          ;;
        4)
           read -p "Enter config file path: " filepath
           # We invoke a bash shell to run the suggestion logic
           ${pkgs.bash}/bin/bash -c "${suggestImprovements "$filepath"}"
           ;;
        5)
           read -p "Enter config file path: " filepath
           # We invoke a bash shell to run the fix logic
           ${pkgs.bash}/bin/bash -c "${autoFix "$filepath"}"
           ;;
        6)
          exit 0
          ;;
        *)
          echo "Invalid option."
          ;;
      esac
    done
  '';

in
{
  inherit
    checkSyntax
    validateConfig
    interactiveMenu
    suggestImprovements
    autoFix
    ;
}

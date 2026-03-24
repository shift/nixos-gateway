{ lib, pkgs }:

with lib;

let
  # Helper to create a diagnostic script
  mkDiagnosticScript =
    { name, checks, ... }:
    pkgs.writeScriptBin "diagnose-${name}" ''
      #!${pkgs.bash}/bin/bash

      echo "Running diagnostics for ${name}..."
      echo "----------------------------------------"

      FAILED=0

      ${concatStringsSep "\n" (
        map (check: ''
          echo -n "Checking ${check.description}... "
          if ${check.command}; then
            echo "OK"
          else
            echo "FAILED"
            FAILED=1
          fi
        '') checks
      )}

      echo "----------------------------------------"
      if [ $FAILED -eq 0 ]; then
        echo "All checks passed."
        exit 0
      else
        echo "Some checks failed."
        exit 1
      fi
    '';

  # Generate the main diagnostic script used in debug-mode.nix
  mkDiagnoseScript =
    diagnosticsConfig:
    let
      healthChecks = if diagnosticsConfig.health.enable then diagnosticsConfig.health.checks else [ ];
    in
    pkgs.writeScriptBin "gateway-diagnose" ''
      #!${pkgs.bash}/bin/bash

      echo "Starting Gateway Diagnostics..."
      echo "--------------------------------"

      FAILED_CHECKS=0
      TOTAL_CHECKS=0

      ${concatStringsSep "\n" (
        map (check: ''
          TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
          echo -n "Checking ${check.description}... "
          if ${check.command}; then
            echo "OK"
          else
            echo "FAILED"
            FAILED_CHECKS=$((FAILED_CHECKS + 1))
          fi
        '') healthChecks
      )}

      echo "--------------------------------"
      echo "Diagnostics Complete."
      echo "Total Checks: $TOTAL_CHECKS"
      echo "Failed Checks: $FAILED_CHECKS"

      if [ $FAILED_CHECKS -eq 0 ]; then
        echo "System appears healthy."
        exit 0
      else
        echo "Issues detected."
        exit 1
      fi
    '';

  # Common diagnostic checks
  commonChecks = {
    network = [
      {
        description = "Default Gateway Connectivity";
        command = "ping -c 1 1.1.1.1 >/dev/null 2>&1";
      }
      {
        description = "DNS Resolution";
        command = "host google.com >/dev/null 2>&1";
      }
      {
        description = "Interface Status";
        command = "ip link show up >/dev/null 2>&1";
      }
    ];
    services = [
      {
        description = "Systemd State";
        command = "! systemctl is-system-running | grep -q 'degraded'";
      }
    ];
  };

in
{
  inherit mkDiagnosticScript mkDiagnoseScript commonChecks;

  # Generate a master debug script
  mkDebugTool =
    { components }:
    pkgs.writeScriptBin "gateway-debug" ''
      #!${pkgs.bash}/bin/bash

      COMMAND=$1
      shift

      show_help() {
        echo "NixOS Gateway Debug Tool"
        echo ""
        echo "Usage: gateway-debug <command> [args]"
        echo ""
        echo "Commands:"
        echo "  diagnose <component>   Run diagnostics for a component"
        echo "  logs <component>       View logs for a component"
        echo "  status                 Show overall system status"
        echo "  list                   List available debug components"
        echo ""
      }

      if [ -z "$COMMAND" ]; then
        show_help
        exit 1
      fi

      case $COMMAND in
        diagnose)
          COMPONENT=$1
          if [ -z "$COMPONENT" ]; then
            echo "Available diagnostic components:"
            ${concatStringsSep "\n" (map (c: "echo '  - ${c}'") components)}
          else
            if command -v "diagnose-$COMPONENT" >/dev/null; then
              "diagnose-$COMPONENT"
            else
              echo "Unknown component: $COMPONENT"
              exit 1
            fi
          fi
          ;;
          
        logs)
          COMPONENT=$1
          if [ -z "$COMPONENT" ]; then
            journalctl -f
          else
            journalctl -u "gateway-$COMPONENT-*" -f
          fi
          ;;
          
        status)
          systemctl status "gateway-*" --no-pager
          ;;
          
        list)
          echo "Debug components: ${concatStringsSep ", " components}"
          ;;
          
        *)
          show_help
          exit 1
          ;;
      esac
    '';
}

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.gateway.troubleshooting;
  engine = import ../lib/troubleshooting-engine.nix { inherit lib; };

  # Default Troubleshooting Trees
  defaultTrees = {
    network-connectivity = {
      id = "network-connectivity";
      title = "Network Connectivity Issues";
      startNode = "check-interfaces";
      nodes = {
        check-interfaces = {
          type = "check";
          description = "Checking network interfaces";
          command = "ip link show up | grep -q 'state UP'";
          pass = "check-internet";
          fail = "action-bring-up";
        };
        check-internet = {
          type = "check";
          description = "Checking internet connectivity";
          command = "ping -c 1 8.8.8.8 >/dev/null 2>&1";
          pass = "result-ok";
          fail = "check-dns";
        };
        check-dns = {
          type = "check";
          description = "Checking DNS resolution";
          command = "nslookup google.com >/dev/null 2>&1";
          pass = "result-firewall";
          fail = "result-dns-fail";
        };
        action-bring-up = {
          type = "action";
          text = "Interfaces are down. Attempting to bring them up.";
          command = "systemctl restart systemd-networkd";
          next = "check-interfaces";
        };
        result-ok = {
          type = "result";
          text = "Network appears to be working correctly.";
        };
        result-dns-fail = {
          type = "result";
          text = "Internet is reachable, but DNS is failing. Check /etc/resolv.conf or DNS server settings.";
        };
        result-firewall = {
          type = "result";
          text = "Internet is reachable and DNS works. If specific services fail, check firewall rules.";
        };
      };
    };
  };

in
{
  options.services.gateway.troubleshooting = {
    enable = lib.mkEnableOption "Troubleshooting Decision Trees";

    trees = lib.mkOption {
      type = lib.types.attrsOf lib.types.attrs;
      default = defaultTrees;
      description = "Defined troubleshooting decision trees";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      (pkgs.writeScriptBin "gateway-diagnose" ''
        #!${pkgs.bash}/bin/bash

        if [ "$1" == "list" ]; then
          echo "Available Diagnostic Trees:"
          echo "---------------------------"
          ${lib.concatStringsSep "\n" (
            lib.mapAttrsToList (id: tree: ''
              echo "${id} - ${tree.title}"
            '') cfg.trees
          )}
          exit 0
        fi

        TREE_ID=$1
        if [ -z "$TREE_ID" ]; then
          echo "Usage: gateway-diagnose [list|<tree-id>]"
          exit 1
        fi

        case $TREE_ID in
          ${lib.concatStringsSep "\n" (
            lib.mapAttrsToList (id: tree: ''
              "${id}")
                exec ${pkgs.writeScript "run-${id}" (engine.mkDiagnosticScript pkgs tree)}
                ;;
            '') cfg.trees
          )}
          *)
            echo "Diagnostic tree not found: $TREE_ID"
            exit 1
            ;;
        esac
      '')

      # Dependencies for checks
      pkgs.iproute2
      pkgs.iputils
      pkgs.dnsutils
    ];
  };
}

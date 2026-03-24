{ config, lib, ... }:

with lib;

let
  cfg = config.simulator.signoff;
in

{
  options.simulator.signoff = {
    enable = mkEnableOption "Human signoff workflow system";

    reviewers = mkOption {
      type = types.listOf types.attrs;
      default = [];
      description = "List of authorized reviewers";
      example = [
        {
          name = "John Doe";
          email = "john@example.com";
          role = "Security Engineer";
          id = "john-doe";
        }
      ];
    };

    requireApproval = mkOption {
      type = types.bool;
      default = true;
      description = "Require approval before signoff is considered valid";
    };

    approvalThreshold = mkOption {
      type = types.int;
      default = 1;
      description = "Number of approvals required";
    };
  };

  config = mkIf cfg.enable {
    # Signoff database service
    systemd.services.simulator-signoff-db = {
      description = "Simulator Signoff Database";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        ExecStart = "${pkgs.callPackage ./signoff-db.nix {
          inherit (cfg) reviewers requireApproval approvalThreshold;
        }}/bin/signoff-db";
        Restart = "always";
        User = "simulator";
        Group = "simulator";
      };
    };

    # Ensure signoff directory exists
    systemd.tmpfiles.rules = [
      "d /var/lib/simulator/signoffs 0750 simulator simulator -"
    ];
  };
}
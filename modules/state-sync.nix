{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.gateway.stateSync;
  inherit (lib)
    mkOption
    types
    mkIf
    mkEnableOption
    ;

  lsyncdConfig = pkgs.writeText "lsyncd.conf" ''
    settings {
      logfile = "/var/log/lsyncd.log",
      statusFile = "/var/log/lsyncd.status",
      insist = true,
    }

    ${lib.concatMapStringsSep "\n" (target: ''
      sync {
        default.rsyncssh,
        source = "${target.source}",
        host = "${target.destinationHost}",
        targetdir = "${target.destinationDir}",
        delay = ${toString cfg.delay},
        rsync = {
          archive = true,
          compress = true,
          _extra = { "--omit-dir-times" }
        },
        ssh = {
          identityFile = "${cfg.sshIdentityFile}",
          options = { User = "root", StrictHostKeyChecking = "no" }
        }
      }
    '') cfg.targets}
  '';

in
{
  options.services.gateway.stateSync = {
    enable = mkEnableOption "State Synchronization (lsyncd)";

    delay = mkOption {
      type = types.int;
      default = 5;
      description = "Delay in seconds before syncing changes";
    };

    sshIdentityFile = mkOption {
      type = types.str;
      default = "/root/.ssh/id_rsa";
      description = "Path to SSH private key for syncing";
    };

    targets = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            source = mkOption {
              type = types.str;
              description = "Local directory to sync";
            };
            destinationHost = mkOption {
              type = types.str;
              description = "Target hostname/IP";
            };
            destinationDir = mkOption {
              type = types.str;
              description = "Remote directory";
            };
          };
        }
      );
      default = [ ];
      description = "List of synchronization targets";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.lsyncd
      pkgs.rsync
    ];

    systemd.services.lsyncd = {
      description = "Live Syncing Daemon";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.lsyncd}/bin/lsyncd -nodaemon ${lsyncdConfig}";
        Restart = "always";
        RestartSec = "10s";
      };
    };
  };
}

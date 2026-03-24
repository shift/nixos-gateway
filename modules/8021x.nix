{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.accessControl.nac;
  inherit (lib)
    mkOption
    types
    mkEnableOption
    mkIf
    ;

  # Import NAC configuration helpers
  nacConfig = import ../lib/nac-config.nix { inherit lib pkgs; };
  # eapCerts = import ../lib/eap-certificates.nix { inherit lib pkgs; };

in
{
  imports = [ ./freeradius.nix ];

  options.accessControl.nac = {
    enable = mkEnableOption "802.1X Network Access Control";

    radius = {
      enable = mkEnableOption "RADIUS server";
      server = {
        host = mkOption {
          type = types.str;
          default = "127.0.0.1";
        };
        port = mkOption {
          type = types.port;
          default = 1812;
        };
        secret = mkOption {
          type = types.str;
          default = "secret";
        };
      };

      certificates = {
        caCert = mkOption {
          type = types.path;
          default = "/etc/radius/ca.pem";
        };
        serverCert = mkOption {
          type = types.path;
          default = "/etc/radius/server.pem";
        };
        serverKey = mkOption {
          type = types.path;
          default = "/etc/radius/server.key";
        };
      };
    };

    users = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            username = mkOption { type = types.str; };
            password = mkOption { type = types.str; };
            vlan = mkOption { type = types.int; };
          };
        }
      );
      default = { };
    };

    clients = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            ip = mkOption { type = types.str; };
            secret = mkOption { type = types.str; };
          };
        }
      );
      default = { };
    };
  };

  config = mkIf cfg.enable {
    # Configure internal RADIUS if enabled
    services.freeradius-gateway = mkIf cfg.radius.enable {
      enable = true;
      users = cfg.users;
      clients = cfg.clients;
      certificates = cfg.radius.certificates;
    };

    # Create certificate generation script if using internal radius
    systemd.services.radius-certs = mkIf cfg.radius.enable {
      description = "Generate RADIUS certificates";
      before = [ "freeradius.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        if [ ! -f ${cfg.radius.certificates.caCert} ]; then
          mkdir -p $(dirname ${cfg.radius.certificates.caCert})
          echo "Certificate generation placeholder"
        fi
      '';
    };
  };
}

{ config, lib, pkgs, ... }:

let
  cfg = config.services.gateway.threatIntel or {};

  in
{
  options.services.gateway.threatIntel = {
    enable = lib.mkEnableOption "Threat Intelligence Integration";

    feeds = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Feed name";
          };

          type = lib.mkOption {
            type = lib.types.enum [ "http" "api" "file" "stix" ];
            description = "Feed access type";
          };

          url = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Feed URL for HTTP/API feeds";
          };

          format = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Feed format";
          };
        };
      }));
      default = { };
      description = "Threat intelligence feeds";
    };

    processing = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Threat intelligence processing options";
    };
  };

  config = lib.mkIf cfg.enable {
    # Mock service for testing
    systemd.services.gateway-threat-intel = {
      description = "Gateway Threat Intelligence Service (mock)";
      wantedBy = [ "multi-user.target" ];
      serviceConfig.ExecStart = "/bin/echo 'Threat intelligence mock service started'";
    };
  };
}

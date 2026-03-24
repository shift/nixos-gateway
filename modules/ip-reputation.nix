{ config, lib, pkgs, ... }:

let
  cfg = config.services.gateway.ipReputation or {};

in
{
  options.services.gateway.ipReputation = {
    enable = lib.mkEnableOption "IP Reputation Blocking (stub)";

    sources = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Source name";
          };

          type = lib.mkOption {
            type = lib.types.enum [ "api" "http" "file" "database" ];
            description = "Source access type";
          };

          url = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Source URL for HTTP/API sources";
          };

          apiKey = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "API key for authenticated sources";
          };

          categories = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ "malicious" ];
            description = "Categories to extract";
          };

          scoring = lib.mkOption {
            type = lib.types.attrsOf lib.types.int;
            default = {
              malicious = 100;
              suspicious = 75;
              unknown = 50;
              benign = 0;
            };
            description = "Score mapping for categories";
          };

          weight = lib.mkOption {
            type = lib.types.float;
            default = 1.0;
            description = "Source weight in scoring";
          };

          update = lib.mkOption {
            type = lib.types.submodule {
              options = {
                interval = lib.mkOption {
                  type = lib.types.str;
                  default = "1h";
                  description = "Update interval";
                };

                retry = lib.mkOption {
                  type = lib.types.int;
                  default = 3;
                  description = "Retry attempts";
                };
              };
            };
            description = "Update configuration";
          };
        };
      }));
      default = { };
      description = "IP reputation sources";
    };

    scoring = lib.mkOption {
      type = lib.types.attrsOf lib.types.int;
      default = {
        malicious = 100;
        suspicious = 75;
        unknown = 50;
        benign = 0;
      };
      description = "Default scoring thresholds";
    };

    policies = lib.mkOption {
      type = lib.types.submodule {
        options = {
          action = lib.mkOption {
            type = lib.types.enum [ "block" "allow" "rate_limit" ];
            default = "block";
            description = "Action to take on high-reputation IPs";
          };

          threshold = lib.mkOption {
            type = lib.types.int;
            default = 80;
            description = "Reputation score threshold for action";
          };
        };
      };
      default = { action = "block"; threshold = 80; };
      description = "IP reputation blocking policies";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = false;
        message = "ip-reputation module is stubbed - needs Python implementation";
      }
    ];
  };
}

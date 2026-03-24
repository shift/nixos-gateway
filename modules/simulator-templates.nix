{ config, lib, ... }:

with lib;

let
  cfg = config.simulator.templates;
in

{
  options.simulator.templates = {
    basic = mkOption {
      type = types.attrs;
      default = {
        services.gateway = {
          enable = true;
          interfaces = {
            lan = "eth0";
            wan = "eth1";
          };
        };
      };
      description = "Basic gateway template";
    };

    networking = mkOption {
      type = types.attrs;
      default = {
        services.gateway = {
          enable = true;
          interfaces = {
            lan = "eth0";
            wan = "eth1";
            dmz = "eth2";
          };
          features = [ "routing" "nat" "dhcp" "dns" ];
        };
      };
      description = "Networking-focused template";
    };

    security = mkOption {
      type = types.attrs;
      default = {
        services.gateway = {
          enable = true;
          interfaces = {
            lan = "eth0";
            wan = "eth1";
          };
          features = [ "firewall" "ids" "vpn" "zero-trust" ];
        };
      };
      description = "Security-focused template";
    };

    monitoring = mkOption {
      type = types.attrs;
      default = {
        services.gateway = {
          enable = true;
          interfaces = {
            lan = "eth0";
            wan = "eth1";
          };
          features = [ "monitoring" "logging" "tracing" "health-checks" ];
        };
      };
      description = "Monitoring-focused template";
    };

    full = mkOption {
      type = types.attrs;
      default = {
        services.gateway = {
          enable = true;
          interfaces = {
            lan = "eth0";
            wan = "eth1";
            dmz = "eth2";
            mgmt = "eth3";
          };
          features = [
            "routing" "nat" "dhcp" "dns"
            "firewall" "ids" "vpn" "zero-trust"
            "monitoring" "logging" "tracing" "health-checks"
            "load-balancing" "qos" "backup" "ha"
          ];
        };
      };
      description = "Full-featured template";
    };
  };

  config = {
    # Template selection logic can be added here
  };
}
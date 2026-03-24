{ lib }:

{
  name = "Base Gateway";
  description = "Base gateway template with common functionality that other templates inherit from";

  parameters = {
    lanInterface = {
      type = "string";
      required = true;
      description = "LAN network interface name";
    };
    wanInterface = {
      type = "string";
      required = true;
      description = "WAN network interface name";
    };
    domain = {
      type = "string";
      default = "gateway.local";
      description = "Local domain name";
    };
    enableLogging = {
      type = "bool";
      default = true;
      description = "Enable comprehensive logging";
    };
    enableMonitoring = {
      type = "bool";
      default = false;
      description = "Enable basic monitoring";
    };
    logLevel = {
      type = "string";
      default = "info";
      description = "Logging level (debug/info/warn/error)";
    };
  };

  config =
    {
      lanInterface,
      wanInterface,
      domain,
      enableLogging,
      enableMonitoring,
      logLevel,
      ...
    }:
    {
      services.gateway = {
        enable = true;
        interfaces = {
          lan = lanInterface;
          wan = wanInterface;
        };
        domain = domain;

        data = {
          network = {
            subnets = { };
            dhcp = { };
          };

          hosts = {
            staticDHCPv4Assignments = [ ];
            staticDHCPv6Assignments = [ ];
          };

          firewall = {
            zones = {
              green = {
                description = "LAN zone";
                allowedTCPPorts = [
                  22
                  53
                ];
                allowedUDPPorts = [
                  53
                  67
                  68
                ];
              };
              red = {
                description = "WAN zone";
                allowedTCPPorts = [ ];
                allowedUDPPorts = [ ];
              };
            };

            deviceTypePolicies = {
              default = {
                description = "Default device policy";
                allowedTCPPorts = [
                  22
                  53
                ];
                allowedUDPPorts = [ 53 ];
              };
            };
          };

          ids = {
            detectEngine = {
              profile = "low";
              sghMpmContext = "auto";
              mpmAlgo = "hs";
            };

            protocols = {
              http = {
                enabled = false;
              };
              dns = {
                enabled = true;
                tcp = true;
                udp = true;
              };
            };

            logging = {
              eveLog = {
                enabled = enableLogging;
                types = [
                  "alert"
                  "dns"
                ];
              };
            };
          };
        };
      };

      networking.firewall.enable = false;
      boot.kernel.sysctl = {
        "net.ipv4.ip_forward" = 1;
        "net.ipv6.conf.all.forwarding" = 1;
      };

      # Basic logging configuration
      services.journald = lib.mkIf enableLogging {
        extraConfig = ''
          Storage=persistent
          Compress=yes
          SystemMaxUse=1G
        '';
      };

      # Basic monitoring
      services.prometheus = lib.mkIf enableMonitoring {
        enable = true;
        exporters = {
          node = {
            enable = true;
            enabledCollectors = [
              "systemd"
              "network"
            ];
          };
        };
      };
    };
}

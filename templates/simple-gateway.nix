{ lib }:

{
  name = "Simple Gateway";
  description = "Simple gateway template that inherits from base gateway";

  inherits = "base-gateway";

  parameters = {
    lanNetwork = {
      type = "cidr";
      default = "192.168.1.0/24";
      description = "LAN network in CIDR notation";
    };
    lanGateway = {
      type = "ip";
      default = "192.168.1.1";
      description = "LAN gateway IP address";
    };
    dhcpRangeStart = {
      type = "ip";
      default = "192.168.1.100";
      description = "DHCP pool start address";
    };
    dhcpRangeEnd = {
      type = "ip";
      default = "192.168.1.200";
      description = "DHCP pool end address";
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
      lanNetwork,
      lanGateway,
      dhcpRangeStart,
      dhcpRangeEnd,
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
            subnets = {
              lan = {
                ipv4 = {
                  subnet = lanNetwork;
                  gateway = lanGateway;
                };
              };
            };

            dhcp = {
              poolStart = dhcpRangeStart;
              poolEnd = dhcpRangeEnd;
            };
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
                  80
                  443
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
                  80
                  443
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
                enabled = true;
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
                  "http"
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
    };
}

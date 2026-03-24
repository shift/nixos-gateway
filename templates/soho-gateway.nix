{ lib }:

{
  name = "SOHO Gateway";
  description = "Small office/home office gateway with basic routing, DNS, DHCP, and firewall";

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
      default = "home.local";
      description = "Local domain name";
    };
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
    enableFirewall = {
      type = "bool";
      default = true;
      description = "Enable firewall protection";
    };
    enableIDS = {
      type = "bool";
      default = false;
      description = "Enable intrusion detection system";
    };
    enableMonitoring = {
      type = "bool";
      default = false;
      description = "Enable system monitoring";
    };
  };

  config =
    {
      lanInterface,
      wanInterface,
      domain,
      lanNetwork,
      lanGateway,
      dhcpRangeStart,
      dhcpRangeEnd,
      enableFirewall,
      enableIDS,
      enableMonitoring,
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

          firewall = lib.mkIf enableFirewall {
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
              workstation = {
                description = "Workstation devices";
                allowedTCPPorts = [
                  22
                  80
                  443
                ];
                allowedUDPPorts = [ 53 ];
              };
              mobile = {
                description = "Mobile devices";
                allowedTCPPorts = [
                  80
                  443
                ];
                allowedUDPPorts = [ 53 ];
              };
            };
          };

          ids = lib.mkIf enableIDS {
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
                enabled = true;
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
    };
}

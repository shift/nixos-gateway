{ lib }:

{
  name = "ISP Gateway";
  description = "ISP-grade gateway with BGP routing, QoS, advanced traffic management, and carrier features";

  parameters = {
    lanInterface = {
      type = "string";
      required = true;
      description = "Customer-facing interface";
    };
    wanInterfaces = {
      type = "array";
      required = true;
      description = "Upstream provider interfaces";
    };
    asn = {
      type = "int";
      required = true;
      description = "Autonomous System Number";
    };
    bgpNeighbors = {
      type = "array";
      default = [ ];
      description = "BGP neighbor configurations";
    };
    domain = {
      type = "string";
      default = "isp.local";
      description = "Local domain";
    };
    customerNetworks = {
      type = "array";
      default = [
        "192.168.0.0/16"
        "10.0.0.0/8"
      ];
      description = "Customer network ranges";
    };
    enableQoS = {
      type = "bool";
      default = true;
      description = "Enable quality of service";
    };
    enableBGP = {
      type = "bool";
      default = true;
      description = "Enable BGP routing";
    };
    enableMonitoring = {
      type = "bool";
      default = true;
      description = "Enable ISP monitoring";
    };
    maxBandwidth = {
      type = "int";
      default = 1000;
      description = "Maximum bandwidth in Mbps";
    };
    lanGateway = {
      type = "ip";
      default = "192.168.0.1";
      description = "LAN gateway IP address for BGP router ID";
    };
  };

  config =
    {
      lanInterface,
      wanInterfaces,
      asn,
      bgpNeighbors,
      domain,
      customerNetworks,
      enableQoS,
      enableBGP,
      enableMonitoring,
      maxBandwidth,
      lanGateway,
      ...
    }:
    {
      services.gateway = {
        enable = true;
        interfaces = {
          lan = lanInterface;
          wan = wanInterfaces;
        };
        domain = domain;

        data = {
          network = {
            subnets = {
              customers = {
                ipv4 = {
                  subnet = "192.168.0.0/16";
                  gateway = "192.168.0.1";
                };
              };
              management = {
                ipv4 = {
                  subnet = "10.255.255.0/24";
                  gateway = "10.255.255.1";
                };
              };
            };

            dhcp = {
              poolStart = "192.168.1.100";
              poolEnd = "192.168.1.200";
            };
          };

          hosts = {
            staticDHCPv4Assignments = [ ];
            staticDHCPv6Assignments = [ ];
          };

          firewall = {
            zones = {
              green = {
                description = "Customer network zone";
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
              mgmt = {
                description = "Management zone";
                allowedTCPPorts = [
                  22
                  53
                  80
                  443
                  161
                  162
                ];
                allowedUDPPorts = [
                  53
                  161
                  162
                ];
              };
              red = {
                description = "Upstream provider zone";
                allowedTCPPorts = [ 179 ]; # BGP
                allowedUDPPorts = [
                  123
                  179
                ]; # NTP, BGP
              };
            };

            deviceTypePolicies = {
              customer = {
                description = "Customer equipment";
                allowedTCPPorts = [
                  22
                  80
                  443
                ];
                allowedUDPPorts = [ 53 ];
              };
              router = {
                description = "Network infrastructure";
                allowedTCPPorts = [
                  22
                  179
                ];
                allowedUDPPorts = [
                  53
                  179
                ];
              };
            };
          };

          ids = {
            detectEngine = {
              profile = "high";
              sghMpmContext = "auto";
              mpmAlgo = "hs";
            };

            threading = {
              setCpuAffinity = true;
              managementCpus = [ 0 ];
              workerCpus = [
                1
                2
                3
              ];
            };

            protocols = {
              http = {
                enabled = true;
              };
              tls = {
                enabled = true;
                ports = [ 443 ];
              };
              dns = {
                enabled = true;
                tcp = true;
                udp = true;
              };
              bgp = {
                enabled = true;
              };
            };

            logging = {
              eveLog = {
                enabled = true;
                types = [
                  "alert"
                  "http"
                  "dns"
                  "tls"
                  "flow"
                  "drop"
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
        "net.ipv4.conf.all.rp_filter" = 0; # Needed for BGP
        "net.ipv4.conf.default.rp_filter" = 0;
      };

      # BGP routing configuration
      services.frr = lib.mkIf enableBGP {
        enable = true;
        bgpd = {
          enable = true;
          config = ''
            router bgp ${toString asn}
              bgp router-id ${lanGateway}
              ${lib.concatStringsSep "\n" (
                map (neighbor: ''
                  neighbor ${neighbor.ip} remote-as ${toString neighbor.asn}
                  neighbor ${neighbor.ip} description "${neighbor.description or "Peer"}"
                  ${lib.optionalString (neighbor.passive or false) "neighbor ${neighbor.ip} passive"}
                '') bgpNeighbors
              )}
              
              ${lib.concatStringsSep "\n" (
                map (network: ''
                  network ${network}
                '') customerNetworks
              )}
          '';
        };
      };

      # QoS configuration
      services.tc = lib.mkIf enableQoS {
        enable = true;
        # Traffic shaping rules would be configured here
        # Example: rate limiting per customer
      };

      # ISP monitoring
      services.prometheus = lib.mkIf enableMonitoring {
        enable = true;
        exporters = {
          node = {
            enable = true;
            enabledCollectors = [
              "systemd"
              "network"
              "hwmon"
            ];
          };
          frr = {
            enable = true;
          };
        };

        scrapeConfigs = [
          {
            job_name = "frr";
            static_configs = [ { targets = [ "localhost:9342" ]; } ];
          }
        ];
      };
    };
}

{ lib }:

{
  name = "Cloud Edge Gateway";
  description = "Cloud edge gateway with hybrid connectivity, container networking, and cloud integration";

  parameters = {
    lanInterface = {
      type = "string";
      required = true;
      description = "Local network interface";
    };
    wanInterface = {
      type = "string";
      required = true;
      description = "Cloud/WAN interface";
    };
    domain = {
      type = "string";
      default = "edge.local";
      description = "Edge domain name";
    };
    lanNetwork = {
      type = "cidr";
      default = "172.16.0.0/16";
      description = "Local network";
    };
    lanGateway = {
      type = "ip";
      default = "172.16.0.1";
      description = "LAN gateway";
    };
    containerNetwork = {
      type = "cidr";
      default = "172.17.0.0/16";
      description = "Docker/container network";
    };
    cloudProvider = {
      type = "string";
      default = "aws";
      description = "Cloud provider (aws/gcp/azure)";
    };
    enableContainers = {
      type = "bool";
      default = true;
      description = "Enable container networking";
    };
    enableCloudVPN = {
      type = "bool";
      default = true;
      description = "Enable cloud VPN tunnel";
    };
    enableMonitoring = {
      type = "bool";
      default = true;
      description = "Enable cloud monitoring";
    };
    cloudRegion = {
      type = "string";
      default = "us-east-1";
      description = "Cloud region";
    };
  };

  config =
    {
      lanInterface,
      wanInterface,
      domain,
      lanNetwork,
      lanGateway,
      containerNetwork,
      cloudProvider,
      enableContainers,
      enableCloudVPN,
      enableMonitoring,
      cloudRegion,
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
              containers = lib.mkIf enableContainers {
                ipv4 = {
                  subnet = containerNetwork;
                  gateway = "172.17.0.1";
                };
              };
            };

            dhcp = {
              poolStart = "172.16.0.100";
              poolEnd = "172.16.0.200";
            };
          };

          hosts = {
            staticDHCPv4Assignments = [ ];
            staticDHCPv6Assignments = [ ];
          };

          firewall = {
            zones = {
              green = {
                description = "Local network zone";
                allowedTCPPorts = [
                  22
                  53
                  80
                  443
                  2375
                  2376
                ]; # Docker ports
                allowedUDPPorts = [
                  53
                  67
                  68
                ];
              };
              orange = lib.mkIf enableContainers {
                description = "Container network zone";
                allowedTCPPorts = [
                  80
                  443
                  2375
                  2376
                  8080
                ];
                allowedUDPPorts = [ 53 ];
              };
              red = {
                description = "Cloud/WAN zone";
                allowedTCPPorts = [ 443 ]; # Cloud API access
                allowedUDPPorts = [ 53 ];
              };
            };

            deviceTypePolicies = {
              edge-device = {
                description = "Edge computing devices";
                allowedTCPPorts = [
                  22
                  80
                  443
                  8080
                ];
                allowedUDPPorts = [ 53 ];
              };
              container = {
                description = "Container workloads";
                allowedTCPPorts = [
                  80
                  443
                  8080
                ];
                allowedUDPPorts = [ ];
              };
              sensor = {
                description = "IoT sensors";
                allowedTCPPorts = [ 443 ];
                allowedUDPPorts = [ 53 ];
              };
            };
          };

          ids = {
            detectEngine = {
              profile = "medium";
              sghMpmContext = "auto";
              mpmAlgo = "hs";
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
            };

            logging = {
              eveLog = {
                enabled = true;
                types = [
                  "alert"
                  "http"
                  "dns"
                  "tls"
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

      # Container networking setup
      virtualisation.docker = lib.mkIf enableContainers {
        enable = true;
        enableNvidia = false;
        autoPrune = {
          enable = true;
          dates = "weekly";
        };
      };

      # Cloud VPN tunnel (example for AWS)
      networking.wireguard.interfaces = lib.mkIf enableCloudVPN {
        cloud-vpn = {
          ips = [ "169.254.10.1/30" ];
          listenPort = 51820;
          privateKey = ""; # Cloud secret
          peers = [
            {
              publicKey = ""; # Cloud VPN endpoint
              allowedIPs = [ "0.0.0.0/0" ];
              endpoint = ""; # Cloud VPN endpoint
            }
          ];
        };
      };

      # Cloud monitoring integration
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

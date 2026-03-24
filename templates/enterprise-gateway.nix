{ lib }:

{
  name = "Enterprise Gateway";
  description = "Enterprise-grade gateway with multi-WAN, VPN, IDS, monitoring, and advanced security";

  parameters = {
    lanInterface = {
      type = "string";
      required = true;
      description = "Primary LAN interface name";
    };
    wanInterfaces = {
      type = "array";
      required = true;
      description = "WAN interface names for multi-WAN setup";
    };
    domain = {
      type = "string";
      default = "corp.local";
      description = "Corporate domain name";
    };
    lanNetwork = {
      type = "cidr";
      default = "10.0.0.0/16";
      description = "Corporate LAN network";
    };
    lanGateway = {
      type = "ip";
      default = "10.0.0.1";
      description = "LAN gateway IP address";
    };
    dmzNetwork = {
      type = "cidr";
      default = "10.0.1.0/24";
      description = "DMZ network for public services";
    };
    dmzGateway = {
      type = "ip";
      default = "10.0.1.1";
      description = "DMZ gateway IP address";
    };
    vpnNetwork = {
      type = "cidr";
      default = "10.0.2.0/24";
      description = "VPN client network";
    };
    enableVPN = {
      type = "bool";
      default = true;
      description = "Enable VPN server";
    };
    enableIDS = {
      type = "bool";
      default = true;
      description = "Enable intrusion detection system";
    };
    enableMonitoring = {
      type = "bool";
      default = true;
      description = "Enable comprehensive monitoring";
    };
    enableQoS = {
      type = "bool";
      default = true;
      description = "Enable quality of service";
    };
    idsProfile = {
      type = "string";
      default = "high";
      description = "IDS detection profile (low/medium/high)";
    };
  };

  config =
    {
      lanInterface,
      wanInterfaces,
      domain,
      lanNetwork,
      lanGateway,
      dmzNetwork,
      dmzGateway,
      vpnNetwork,
      enableVPN,
      enableIDS,
      enableMonitoring,
      enableQoS,
      idsProfile,
      ...
    }:
    {
      services.gateway = {
        enable = true;
        interfaces = {
          lan = lanInterface;
          wan = if builtins.isList wanInterfaces then builtins.head wanInterfaces else wanInterfaces;
          dmz = "${lanInterface}:1"; # Alias interface for DMZ
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
              dmz = {
                ipv4 = {
                  subnet = dmzNetwork;
                  gateway = dmzGateway;
                };
              };
              vpn = lib.mkIf enableVPN {
                ipv4 = {
                  subnet = vpnNetwork;
                  gateway = "10.0.2.1";
                };
              };
            };

            dhcp = {
              poolStart = "10.0.0.100";
              poolEnd = "10.0.0.200";
            };
          };

          hosts = {
            staticDHCPv4Assignments = [ ];
            staticDHCPv6Assignments = [ ];
          };

          firewall = {
            zones = {
              green = {
                description = "Corporate LAN zone";
                allowedTCPPorts = [
                  22
                  53
                  80
                  443
                  389
                  636
                  88
                  445
                ];
                allowedUDPPorts = [
                  53
                  67
                  68
                  123
                  137
                  138
                ];
              };
              orange = {
                description = "DMZ zone";
                allowedTCPPorts = [
                  22
                  80
                  443
                ];
                allowedUDPPorts = [ 53 ];
              };
              blue = lib.mkIf enableVPN {
                description = "VPN zone";
                allowedTCPPorts = [
                  22
                  53
                  80
                  443
                ];
                allowedUDPPorts = [ 53 ];
              };
              red = {
                description = "WAN zone";
                allowedTCPPorts = [ ];
                allowedUDPPorts = [ ];
              };
            };

            deviceTypePolicies = {
              workstation = {
                description = "Corporate workstations";
                allowedTCPPorts = [
                  22
                  80
                  443
                  389
                  636
                ];
                allowedUDPPorts = [ 53 ];
              };
              server = {
                description = "Server infrastructure";
                allowedTCPPorts = [
                  22
                  80
                  443
                  389
                  636
                  3306
                  5432
                ];
                allowedUDPPorts = [ 53 ];
              };
              printer = {
                description = "Network printers";
                allowedTCPPorts = [
                  631
                  9100
                ];
                allowedUDPPorts = [ 161 ];
              };
            };
          };

          ids = lib.mkIf enableIDS {
            detectEngine = {
              profile = idsProfile;
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
              smb = {
                enabled = true;
                detectionEnabled = true;
              };
              ftp = {
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
                  "files"
                  "flow"
                  "drop"
                ];
              };
              rotation = {
                logs = {
                  days = 7;
                  compress = true;
                };
                json = {
                  days = 30;
                  compress = true;
                  maxSize = "1G";
                };
              };
            };

            exporter = {
              port = 9917;
              socketPath = "/run/suricata/suricata.socket";
            };
          };
        };
      };

      networking.firewall.enable = false;
      boot.kernel.sysctl = {
        "net.ipv4.ip_forward" = 1;
        "net.ipv6.conf.all.forwarding" = 1;
      };

      # VPN configuration (WireGuard example)
      networking.wireguard.interfaces = lib.mkIf enableVPN {
        wg0 = {
          ips = [ "10.0.2.1/24" ];
          listenPort = 51820;
          privateKey = ""; # Should be set via secrets
          peers = [ ];
        };
      };

      # QoS configuration
      services.tc = lib.mkIf enableQoS {
        enable = true;
        # QoS rules would be configured here
      };
    };
}

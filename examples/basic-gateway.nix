{ config, pkgs, ... }:

{
  imports = [
    (builtins.getFlake "github:youruser/nixos-gateway").nixosModules.gateway
  ];

  services.gateway = {
    enable = true;

    disk = {
      enable = true;
      device = "/dev/disk/by-id/nvme-YOUR_DISK_ID_HERE";
      luks = {
        enable = true;
        tpm2.enable = true;
      };
      btrfs = {
        compression = "zstd";
        extraMountOptions = [ "noatime" ];
      };
    };

    persistence = {
      enable = true;
      persistPath = "/persist";
    };

    interfaces = {
      lan = "eth0";
      wan = "eth1";
    };

    ipv6Prefix = "2001:db8::";
    domain = "home.local";

    data = {
      network = {
        subnets = {
          lan = {
            ipv4 = {
              subnet = "192.168.1.0/24";
              gateway = "192.168.1.1";
            };
            ipv6 = {
              prefix = "2001:db8::/48";
              gateway = "2001:db8::1";
            };
          };
        };

        dhcp = {
          poolStart = "192.168.1.100";
          poolEnd = "192.168.1.200";
        };
      };

      hosts = {
        staticDHCPv4Assignments = [
          {
            name = "server1";
            macAddress = "aa:bb:cc:dd:ee:01";
            ipAddress = "192.168.1.10";
            type = "server";
          }
          {
            name = "laptop1";
            macAddress = "aa:bb:cc:dd:ee:02";
            ipAddress = "192.168.1.20";
            type = "client";
          }
        ];

        staticDHCPv6Assignments = [
          {
            name = "server1";
            duid = "00:01:00:01:2a:be:8d:c8:aa:bb:cc:dd:ee:01";
            address = "2001:db8::10";
          }
        ];
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
          server = {
            description = "Server devices";
            allowedTCPPorts = [
              22
              80
              443
            ];
            allowedUDPPorts = [ 53 ];
          };
          client = {
            description = "Client devices";
            allowedTCPPorts = [
              22
              80
              443
            ];
            allowedUDPPorts = [ 53 ];
          };
        };
      };

      ids = {
        ruleSources = {
          emergingThreats = {
            url = "https://rules.emergingthreats.net/open/suricata/emerging.rules.tar.gz";
            sha256 = "";
            enabled = true;
          };
        };

        detectEngine = {
          profile = "medium";
          sghMpmContext = "auto";
          mpmAlgo = "hs";
        };

        protocols = {
          http.enabled = true;
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
}

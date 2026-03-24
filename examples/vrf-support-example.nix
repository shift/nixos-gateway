{
  description = "VRF (Virtual Routing and Forwarding) Support Example";

  # Example configuration demonstrating VRF support for true Layer 3 isolation
  # Enables overlapping IP ranges and management plane isolation

  networking.vrfs = {
    # Management VRF - isolated from traffic VRFs
    mgmt = {
      enable = true;
      table = 1000;
      interfaces = [ "eth0" ]; # Out-of-band management interface

      routing = {
        enable = true;
        static = [
          {
            destination = "0.0.0.0/0";
            gateway = "10.255.255.1";
            metric = 10;
          }
        ];
      };

      firewall = {
        enable = true;
        rules = [
          "allow ssh from 10.255.254.0/24"
          "allow https from 10.255.254.0/24"
          "drop all"
        ];
      };
    };

    # Customer Blue VRF - First customer network
    blue = {
      enable = true;
      table = 101;
      interfaces = [
        "eth1"
        "eth1.100"
        "eth1.101"
      ];

      routing = {
        enable = true;
        bgp = {
          enable = true;
          asn = 65001;
          routerId = "10.1.1.1";
          neighbors = {
            "10.1.1.254" = {
              remoteAs = 65000;
            };
            "10.1.2.254" = {
              remoteAs = 65002;
            };
          };
        };
        static = [
          {
            destination = "192.168.100.0/24";
            gateway = "10.1.1.254";
            metric = 100;
          }
          {
            destination = "10.0.0.0/8";
            gateway = "10.1.1.254";
            metric = 200;
          }
        ];
      };

      firewall = {
        enable = true;
        rules = [
          "allow established related"
          "allow icmp"
          "allow ssh to 10.1.1.0/24"
          "allow http to 10.1.1.0/24"
          "allow https to 10.1.1.0/24"
          "drop all"
        ];
      };
    };

    # Customer Red VRF - Second customer with overlapping IP space
    red = {
      enable = true;
      table = 102;
      interfaces = [
        "eth2"
        "eth2.100"
        "eth2.101"
      ];

      routing = {
        enable = true;
        bgp = {
          enable = true;
          asn = 65002;
          routerId = "10.1.1.1"; # Same router ID - different VRF
          neighbors = {
            "10.1.1.254" = {
              remoteAs = 65000;
            };
            "10.1.3.254" = {
              remoteAs = 65003;
            };
          };
        };
        static = [
          {
            destination = "192.168.100.0/24"; # Same subnet as Blue VRF!
            gateway = "10.1.1.254";
            metric = 100;
          }
          {
            destination = "10.0.0.0/8";
            gateway = "10.1.1.254";
            metric = 200;
          }
        ];
      };

      firewall = {
        enable = true;
        rules = [
          "allow established related"
          "allow icmp"
          "allow ssh to 10.1.1.0/24"
          "allow ftp to 10.1.1.0/24"
          "drop all"
        ];
      };
    };

    # DMZ VRF - Public-facing services
    dmz = {
      enable = true;
      table = 103;
      interfaces = [ "eth3" ];

      routing = {
        enable = true;
        static = [
          {
            destination = "0.0.0.0/0";
            gateway = "203.0.113.1";
            metric = 10;
          }
        ];
      };

      firewall = {
        enable = true;
        rules = [
          "allow established related"
          "allow icmp"
          "allow http from any"
          "allow https from any"
          "allow smtp from any"
          "drop all"
        ];
      };
    };
  };

  # Interface configurations
  systemd.network.networks = {
    "10-eth0" = {
      matchConfig.Name = "eth0";
      networkConfig = {
        Address = "10.255.254.10/24";
        Gateway = "10.255.255.1";
      };
    };

    "20-eth1" = {
      matchConfig.Name = "eth1";
      networkConfig = {
        Address = "10.1.1.1/24";
      };
    };

    "20-eth2" = {
      matchConfig.Name = "eth2";
      networkConfig = {
        Address = "10.1.1.1/24"; # Same IP as eth1 - different VRF!
      };
    };

    "20-eth3" = {
      matchConfig.Name = "eth3";
      networkConfig = {
        Address = "203.0.113.10/24";
      };
    };

    # VLAN interfaces for Blue VRF
    "30-eth1.100" = {
      matchConfig.Name = "eth1.100";
      networkConfig = {
        Address = "10.1.100.1/24";
        VLAN = "100";
      };
    };

    "30-eth1.101" = {
      matchConfig.Name = "eth1.101";
      networkConfig = {
        Address = "10.1.101.1/24";
        VLAN = "101";
      };
    };

    # VLAN interfaces for Red VRF
    "30-eth2.100" = {
      matchConfig.Name = "eth2.100";
      networkConfig = {
        Address = "10.1.100.1/24"; # Same as Blue VLAN - different VRF!
        VLAN = "100";
      };
    };

    "30-eth2.101" = {
      matchConfig.Name = "eth2.101";
      networkConfig = {
        Address = "10.1.101.1/24"; # Same as Blue VLAN - different VRF!
        VLAN = "101";
      };
    };
  };

  # Example route leaking between VRFs (controlled communication)
  # This would be implemented with additional routing configuration
  services.gateway.data = {
    # Route leaking examples:
    # - Allow management VRF to access all VRFs for monitoring
    # - Allow DMZ to access database servers in Blue VRF
    # - Block direct Blue-Red communication (go through firewall)

    firewall = {
      zones = {
        mgmt = {
          description = "Management VRF";
          interfaces = [ "mgmt" ];
          policy = "accept";
        };

        blue = {
          description = "Customer Blue VRF";
          interfaces = [ "blue" ];
          policy = "drop";
          rules = [
            {
              description = "Allow management access";
              action = "accept";
              source.zone = "mgmt";
              destination.zone = "blue";
            }
          ];
        };

        red = {
          description = "Customer Red VRF";
          interfaces = [ "red" ];
          policy = "drop";
          rules = [
            {
              description = "Allow management access";
              action = "accept";
              source.zone = "mgmt";
              destination.zone = "red";
            }
          ];
        };

        dmz = {
          description = "DMZ VRF";
          interfaces = [ "dmz" ];
          policy = "drop";
          rules = [
            {
              description = "Allow DMZ to Blue database servers";
              action = "accept";
              source.zone = "dmz";
              destination.zone = "blue";
              destination.port = 5432;
              protocol = "tcp";
            }
          ];
        };
      };
    };
  };

  # Monitoring configuration for VRFs
  services.gateway.data = {
    monitoring = {
      enable = true;
      vrf = {
        enable = true;
        interfaces = [ "mgmt" ]; # Monitor from management VRF only
      };
      metrics = {
        exporters = [
          {
            name = "vrf-metrics";
            type = "prometheus";
            port = 9092;
            path = "/metrics";
          }
        ];
      };
    };
  };
}

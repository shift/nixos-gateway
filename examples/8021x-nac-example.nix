{
  description = "802.1X Network Access Control (NAC) Example";

  # Example configuration demonstrating 802.1X NAC for identity-aware networking
  # with dynamic VLAN assignment based on user authentication

  accessControl.nac = {
    enable = true;

    radius = {
      enable = true;
      server = {
        host = "192.168.1.10";
        port = 1812;
        secret = "secure-radius-secret-2024";
      };

      certificates = {
        caCert = "/etc/radius/ca.pem";
        serverCert = "/etc/radius/server.pem";
        serverKey = "/etc/radius/server.key";
      };
    };

    authentication = {
      methods = [
        "eap-tls"
        "peap"
      ];

      certificates = {
        caCert = "/etc/radius/ca.pem";
        serverCert = "/etc/radius/server.pem";
        serverKey = "/etc/radius/server.key";
      };
    };

    # Port configurations for different access points
    ports = {
      # Corporate WiFi - High security
      wlan0 = {
        enable = true;
        mode = "auto";
        reauthTimeout = 3600;
        maxAttempts = 3;
        guestVlan = null; # No guest access on corporate network
        unauthorizedVlan = 998; # Quarantine VLAN for failed auth
      };

      # Guest WiFi - Limited access
      wlan1 = {
        enable = true;
        mode = "force-unauthorized";
        reauthTimeout = 1800;
        maxAttempts = 5;
        guestVlan = 999; # Guest VLAN
        unauthorizedVlan = 999;
      };

      # IoT Network - Device-based access
      wlan2 = {
        enable = true;
        mode = "auto";
        reauthTimeout = 7200;
        maxAttempts = 10;
        guestVlan = 200; # IoT VLAN
        unauthorizedVlan = 997; # Isolate compromised devices
      };
    };

    # User definitions with role-based access
    users = {
      # Network administrators
      "admin.john" = {
        username = "admin.john";
        certificate = "/etc/radius/certs/admin.john.pem";
        vlan = 10; # Management VLAN
        groups = [
          "network-admin"
          "full-access"
        ];
        accessTimes = {
          always = {
            days = [
              "Monday"
              "Tuesday"
              "Wednesday"
              "Thursday"
              "Friday"
              "Saturday"
              "Sunday"
            ];
            startTime = "00:00";
            endTime = "23:59";
          };
        };
      };

      # Regular employees
      "user.alice" = {
        username = "user.alice";
        password = "secure-password-123";
        vlan = 20; # Corporate VLAN
        groups = [
          "employees"
          "corporate-access"
        ];
        accessTimes = {
          workhours = {
            days = [
              "Monday"
              "Tuesday"
              "Wednesday"
              "Thursday"
              "Friday"
            ];
            startTime = "08:00";
            endTime = "18:00";
          };
          weekends = {
            days = [
              "Saturday"
              "Sunday"
            ];
            startTime = "10:00";
            endTime = "16:00";
          };
        };
      };

      # Contractors
      "contractor.bob" = {
        username = "contractor.bob";
        password = "contractor-pass-456";
        vlan = 30; # Contractor VLAN
        groups = [
          "contractors"
          "limited-access"
        ];
        accessTimes = {
          contract = {
            days = [
              "Monday"
              "Tuesday"
              "Wednesday"
              "Thursday"
              "Friday"
            ];
            startTime = "09:00";
            endTime = "17:00";
          };
        };
      };

      # Guest users
      "guest" = {
        username = "guest";
        password = "guest-access";
        vlan = 999; # Guest VLAN
        groups = [ "guests" ];
        accessTimes = {
          guest = {
            days = [
              "Monday"
              "Tuesday"
              "Wednesday"
              "Thursday"
              "Friday"
              "Saturday"
              "Sunday"
            ];
            startTime = "06:00";
            endTime = "22:00";
          };
        };
      };

      # IoT devices
      "iot.camera01" = {
        username = "iot.camera01";
        password = "iot-device-secret";
        vlan = 200; # IoT VLAN
        groups = [ "iot-devices" ];
        accessTimes = {
          always = {
            days = [
              "Monday"
              "Tuesday"
              "Wednesday"
              "Thursday"
              "Friday"
              "Saturday"
              "Sunday"
            ];
            startTime = "00:00";
            endTime = "23:59";
          };
        };
      };
    };

    # NAC policies
    policies = {
      defaultVlan = 1; # Default VLAN for authenticated users
      guestVlan = 999; # Guest access VLAN
      quarantineVlan = 998; # Quarantine VLAN for suspicious devices
    };
  };

  # RADIUS clients (switches and access points)
  services.freeradius-gateway = {
    enable = true;

    users = {
      "admin.john" = {
        username = "admin.john";
        password = "admin-secure-pass";
        vlan = 10;
      };

      "user.alice" = {
        username = "user.alice";
        password = "secure-password-123";
        vlan = 20;
      };

      "contractor.bob" = {
        username = "contractor.bob";
        password = "contractor-pass-456";
        vlan = 30;
      };

      "guest" = {
        username = "guest";
        password = "guest-access";
        vlan = 999;
      };
    };

    clients = {
      "switch01" = {
        ip = "192.168.1.101";
        secret = "switch-secret-01";
      };

      "switch02" = {
        ip = "192.168.1.102";
        secret = "switch-secret-02";
      };

      "ap-corporate" = {
        ip = "192.168.1.201";
        secret = "ap-secret-corp";
      };

      "ap-guest" = {
        ip = "192.168.1.202";
        secret = "ap-secret-guest";
      };
    };

    certificates = {
      caCert = "/etc/radius/ca.pem";
      serverCert = "/etc/radius/server.pem";
      serverKey = "/etc/radius/server.key";
    };
  };

  # Network interface configurations
  systemd.network.networks = {
    "10-wlan0" = {
      matchConfig.Name = "wlan0";
      networkConfig = {
        Address = "192.168.1.1/24";
        # This will be configured by hostapd for 802.1X
      };
    };

    "10-wlan1" = {
      matchConfig.Name = "wlan1";
      networkConfig = {
        Address = "192.168.2.1/24";
      };
    };

    "10-wlan2" = {
      matchConfig.Name = "wlan2";
      networkConfig = {
        Address = "192.168.3.1/24";
      };
    };
  };

  # VLAN configurations
  systemd.network.netdevs = {
    "10-vlan10" = {
      enable = true;
      netdevConfig = {
        Name = "vlan10";
        Kind = "vlan";
        VLAN.Id = 10;
      };
    };

    "10-vlan20" = {
      enable = true;
      netdevConfig = {
        Name = "vlan20";
        Kind = "vlan";
        VLAN.Id = 20;
      };
    };

    "10-vlan30" = {
      enable = true;
      netdevConfig = {
        Name = "vlan30";
        Kind = "vlan";
        VLAN.Id = 30;
      };
    };

    "10-vlan200" = {
      enable = true;
      netdevConfig = {
        Name = "vlan200";
        Kind = "vlan";
        VLAN.Id = 200;
      };
    };

    "10-vlan999" = {
      enable = true;
      netdevConfig = {
        Name = "vlan999";
        Kind = "vlan";
        VLAN.Id = 999;
      };
    };
  };

  # VLAN network configurations
  systemd.network.networks = {
    "20-vlan10" = {
      matchConfig.Name = "vlan10";
      networkConfig = {
        Address = "10.0.10.1/24";
        Description = "Management VLAN";
      };
    };

    "20-vlan20" = {
      matchConfig.Name = "vlan20";
      networkConfig = {
        Address = "10.0.20.1/24";
        Description = "Corporate VLAN";
      };
    };

    "20-vlan30" = {
      matchConfig.Name = "vlan30";
      networkConfig = {
        Address = "10.0.30.1/24";
        Description = "Contractor VLAN";
      };
    };

    "20-vlan200" = {
      matchConfig.Name = "vlan200";
      networkConfig = {
        Address = "10.0.200.1/24";
        Description = "IoT VLAN";
      };
    };

    "20-vlan999" = {
      matchConfig.Name = "vlan999";
      networkConfig = {
        Address = "10.0.999.1/24";
        Description = "Guest VLAN";
      };
    };
  };

  # Firewall rules for VLAN isolation
  services.gateway.data = {
    firewall = {
      zones = {
        management = {
          description = "Management VLAN (10)";
          interfaces = [ "vlan10" ];
          policy = "accept";
          rules = [
            {
              description = "Allow management from admin network";
              action = "accept";
              source.network = "192.168.1.0/24";
              destination.zone = "management";
            }
          ];
        };

        corporate = {
          description = "Corporate VLAN (20)";
          interfaces = [ "vlan20" ];
          policy = "accept";
          rules = [
            {
              description = "Allow corporate services";
              action = "accept";
              protocol = "tcp";
              destination.port = [
                80
                443
                25
                587
              ];
            }
          ];
        };

        contractor = {
          description = "Contractor VLAN (30)";
          interfaces = [ "vlan30" ];
          policy = "accept";
          rules = [
            {
              description = "Limited contractor access";
              action = "accept";
              protocol = "tcp";
              destination.port = [
                80
                443
              ];
            }
          ];
        };

        iot = {
          description = "IoT VLAN (200)";
          interfaces = [ "vlan200" ];
          policy = "accept";
          rules = [
            {
              description = "IoT device communication";
              action = "accept";
              protocol = "tcp";
              destination.port = [
                80
                443
                1883
                8883
              ];
            }
          ];
        };

        guest = {
          description = "Guest VLAN (999)";
          interfaces = [ "vlan999" ];
          policy = "accept";
          rules = [
            {
              description = "Limited guest access";
              action = "accept";
              protocol = "tcp";
              destination.port = [
                80
                443
              ];
            }
            {
              description = "Block internal access from guests";
              action = "drop";
              destination.network = "10.0.0.0/8";
            }
          ];
        };
      };
    };
  };

  # Monitoring for NAC
  services.gateway.data = {
    monitoring = {
      enable = true;
      nac = {
        enable = true;
        logLevel = "info";
        metrics = {
          authenticationAttempts = true;
          vlanAssignments = true;
          failedLogins = true;
          certificateExpiry = true;
        };
      };

      metrics = {
        exporters = [
          {
            name = "nac-metrics";
            type = "prometheus";
            port = 9093;
            path = "/metrics";
          }
        ];
      };
    };
  };
}

# Secret Rotation Automation Example Configuration
# This example demonstrates comprehensive secret rotation setup

{
  config,
  pkgs,
  lib,
  ...
}:

{
  imports = [
    ../modules/certificate-manager.nix
    ../modules/key-rotation.nix
    ../modules/secrets.nix
  ];

  services.gateway = {
    enable = true;
    environment = "production";

    # Secret rotation automation configuration
    secretRotation = {
      enable = true;

      # Certificate rotation configuration
      certificates = {
        # Main gateway certificate with ACME/Let's Encrypt
        gateway = {
          type = "acme";
          domain = "gateway.example.com";
          email = "admin@example.com";
          renewBefore = "30d";
          staging = false;
          reloadServices = [
            "nginx"
            "knot"
          ];
        };

        # Internal services with self-signed certificates
        internal-api = {
          type = "selfSigned";
          domain = "api.internal.example.com";
          renewBefore = "90d";
          keySize = 4096;
          validDays = 365;
          reloadServices = [ "gateway-api" ];
        };

        # Management interface certificate
        management = {
          type = "selfSigned";
          domain = "mgmt.example.com";
          renewBefore = "60d";
          keySize = 2048;
          validDays = 180;
          reloadServices = [ "nginx" ];
        };
      };

      # Key rotation configuration
      keys = {
        # WireGuard VPN keys with peer coordination
        vpn-primary = {
          type = "wireguard";
          interface = "wg0";
          rotationInterval = "90d";
          coordinationRequired = true;
          peerNotification = true;
          peers = [
            "vpn-peer1.example.com"
            "vpn-peer2.example.com"
            "vpn-backup.example.com"
          ];
          dependentServices = [ "wg-quick-wg0" ];
        };

        # Site-to-site VPN keys
        site-to-site = {
          type = "wireguard";
          interface = "wg1";
          rotationInterval = "180d";
          coordinationRequired = true;
          peerNotification = true;
          peers = [ "remote-site.example.com" ];
          dependentServices = [ "wg-quick-wg1" ];
        };

        # DNS TSIG keys for dynamic updates
        dns-primary = {
          type = "tsig";
          name = "gateway-dns-key";
          algorithm = "hmac-sha256";
          rotationInterval = "180d";
          dependentServices = [
            "knot"
            "kea-dhcp-ddns"
          ];
        };

        # DNS secondary TSIG key
        dns-secondary = {
          type = "tsig";
          name = "gateway-dns-secondary";
          algorithm = "hmac-sha512";
          rotationInterval = "365d";
          dependentServices = [ "knot" ];
        };

        # API authentication keys
        api-main = {
          type = "apiKey";
          serviceName = "gateway-api";
          rotationInterval = "30d";
          keyLength = 64;
          dependentServices = [ "gateway-api" ];
          updateCommand = "systemctl reload gateway-api && systemctl reload nginx";
        };

        # Monitoring API key
        monitoring-api = {
          type = "apiKey";
          serviceName = "prometheus";
          rotationInterval = "60d";
          keyLength = 32;
          dependentServices = [
            "prometheus"
            "grafana"
          ];
          updateCommand = "systemctl reload prometheus && systemctl reload grafana";
        };

        # External service API key
        external-service = {
          type = "apiKey";
          serviceName = "external-api";
          rotationInterval = "90d";
          keyLength = 48;
          dependentServices = [ "gateway-external-connector" ];
          updateCommand = "curl -X POST http://localhost:8080/api/reload-key -H 'Authorization: Bearer $NEW_KEY'";
        };
      };

      # Monitoring and alerting configuration
      monitoring = {
        expirationWarnings = [
          "30d"
          "14d"
          "7d"
          "3d"
          "1d"
        ];
        alertOnFailure = true;
        rotationMetrics = true;
      };
    };

    # Existing secrets configuration
    secrets = {
      # Database credentials
      database = {
        type = "databasePassword";
        password = "{{secret:database.main_password}}";
        rotation = {
          enabled = true;
          interval = "180d";
          backup = true;
        };
      };

      # External API credentials
      cloudflare = {
        type = "apiKey";
        key = "{{secret:cloudflare.api_token}}";
        rotation = {
          enabled = true;
          interval = "90d";
        };
      };
    };
  };

  # Network configuration for WireGuard
  networking.wireguard.interfaces = {
    wg0 = {
      ips = [ "10.0.1.1/24" ];
      privateKey = "{{secret:wireguard.wg0_private}}";
      peers = [
        {
          publicKey = "{{secret:wireguard.peer1_public}}";
          allowedIPs = [ "10.0.1.2/32" ];
          endpoint = "vpn-peer1.example.com:51820";
        }
        {
          publicKey = "{{secret:wireguard.peer2_public}}";
          allowedIPs = [ "10.0.1.3/32" ];
          endpoint = "vpn-peer2.example.com:51820";
        }
      ];
    };

    wg1 = {
      ips = [ "10.0.2.1/24" ];
      privateKey = "{{secret:wireguard.wg1_private}}";
      peers = [
        {
          publicKey = "{{secret:wireguard.remote_site_public}}";
          allowedIPs = [ "10.0.2.0/24" ];
          endpoint = "remote-site.example.com:51820";
        }
      ];
    };
  };

  # DNS configuration with TSIG
  services.knot = {
    enable = true;
    settings = {
      server = {
        listen = [ "0.0.0.0@53" ];
        tsig-lifetime = 3600;
      };

      acl = [
        {
          name = "ddns-update-acl";
          action = "update";
          key = "gateway-dns-key";
        }
      ];

      key = [
        {
          id = "gateway-dns-key";
          algorithm = "hmac-sha256";
          secret = "{{secret:dns.gateway_tsig}}";
        }
        {
          id = "gateway-dns-secondary";
          algorithm = "hmac-sha512";
          secret = "{{secret:dns.gateway_tsig_secondary}}";
        }
      ];

      zone = [
        {
          domain = "example.com";
          file = "/var/lib/knot/example.com.zone";
          acl = [ "ddns-update-acl" ];
        }
        {
          domain = "internal.example.com";
          file = "/var/lib/knot/internal.example.com.zone";
          acl = [ "ddns-update-acl" ];
        }
      ];
    };
  };

  # DHCP configuration with DNS updates
  services.kea = {
    dhcp4 = {
      enable = true;
      settings = {
        interfaces-config = {
          interfaces = [
            "eth0"
            "eth1"
          ];
        };

        lease-database = {
          type = "memfile";
          persist = true;
          name = "/var/lib/kea/dhcp4.leases";
        };

        ddns-qualifying-suffix = "example.com";

        ddns-parameters = {
          enable-updates = true;
          override-client-update = true;
          replace-client-name = "when-present";
          generated-prefix = "myhost";
        };

        hooks-libraries = [
          "/nix/store/...-libdhcp_ddns.so"
        ];

        subnet4 = [
          {
            id = 1;
            subnet = "192.168.1.0/24";
            pools = [ { pool = "192.168.1.100 - 192.168.1.200"; } ];
            option-data = [
              {
                name = "routers";
                data = "192.168.1.1";
              }
              {
                name = "domain-name-servers";
                data = "192.168.1.1";
              }
            ];
          }
        ];
      };
    };
  };

  # Web server configuration
  services.nginx = {
    enable = true;

    virtualHosts = {
      "gateway.example.com" = {
        forceSSL = true;
        sslCertificate = "/run/gateway-secrets/gateway.example.com.crt";
        sslCertificateKey = "/run/gateway-secrets/gateway.example.com.key";
        locations."/" = {
          proxyPass = "http://localhost:8080";
        };
      };

      "api.internal.example.com" = {
        forceSSL = true;
        sslCertificate = "/run/gateway-secrets/api.internal.example.com.crt";
        sslCertificateKey = "/run/gateway-secrets/api.internal.example.com.key";
        locations."/" = {
          proxyPass = "http://localhost:3000";
        };
      };

      "mgmt.example.com" = {
        forceSSL = true;
        sslCertificate = "/run/gateway-secrets/mgmt.example.com.crt";
        sslCertificateKey = "/run/gateway-secrets/mgmt.example.com.key";
        locations."/" = {
          proxyPass = "http://localhost:9000";
        };
      };
    };
  };

  # API service
  systemd.services.gateway-api = {
    description = "Gateway API service";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.nodejs}/bin/node /opt/gateway-api/server.js";
      Restart = "always";
      Environment = [
        "API_KEY_FILE=/run/gateway-secrets/gateway-api.apikey"
        "NODE_ENV=production"
      ];
      User = "gateway-api";
      Group = "gateway-api";
    };
  };

  # External service connector
  systemd.services.gateway-external-connector = {
    description = "Gateway external service connector";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.python3}/bin/python /opt/gateway-connector/connector.py";
      Restart = "always";
      Environment = [
        "API_KEY_FILE=/run/gateway-secrets/external-service.apikey"
        "PYTHONPATH=/opt/gateway-connector"
      ];
      User = "gateway-connector";
      Group = "gateway-connector";
    };
  };

  # Monitoring configuration
  services.prometheus = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 9090;

    exporters = {
      node = {
        enable = true;
        enabledCollectors = [
          "systemd"
          "network"
          "disk"
        ];
      };
    };

    scrapeConfigs = [
      {
        job_name = "gateway";
        static_configs = [
          { targets = [ "localhost:9100" ]; }
        ];
      }
    ];
  };

  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_addr = "127.0.0.1";
        http_port = 3000;
        domain = "api.internal.example.com";
      };
      security = {
        admin_user = "admin";
        admin_password = "{{secret:grafana.admin_password}}";
      };
    };
  };

  # Required packages
  environment.systemPackages = with pkgs; [
    openssl
    certbot
    wireguard-tools
    knot
    nginx
    nodejs
    python3
  ];

  # User accounts for services
  users.users = {
    gateway-api = {
      isSystemUser = true;
      group = "gateway-api";
    };

    gateway-connector = {
      isSystemUser = true;
      group = "gateway-connector";
    };
  };

  users.groups = {
    gateway-api = { };
    gateway-connector = { };
  };

  # Firewall configuration
  networking.firewall = {
    enable = true;

    allowedTCPPorts = [
      80 # HTTP
      443 # HTTPS
      53 # DNS
      8080 # API
      3000 # Grafana
      9090 # Prometheus
    ];

    allowedUDPPorts = [
      53 # DNS
      51820 # WireGuard
    ];
  };

  # System configuration
  system.stateVersion = "23.11";
}

# Secret Rotation Automation Example
# This example demonstrates comprehensive secret rotation automation
# for the NixOS Gateway Configuration Framework

{
  config,
  pkgs,
  lib,
  ...
}:

{
  imports = [
    # Import the gateway modules
    (builtins.fetchGit {
      url = "https://github.com/nixos-gateway/nixos-gateway";
      ref = "main";
    }).modules
  ];

  # Enable the gateway with secret rotation automation
  services.gateway = {
    enable = true;

    # Network configuration
    interfaces = {
      lan = "eth1";
      wan = "eth0";
      mgmt = "eth2";
    };

    ipv6Prefix = "2001:db8::";
    domain = "gateway.example.com";

    # Secret rotation automation configuration
    secretRotation = {
      enable = true;

      # Certificate rotation configuration
      certificates = {
        # Main gateway certificate (ACME/Let's Encrypt)
        gateway-main = {
          type = "acme";
          domain = "gateway.example.com";
          email = "admin@example.com";
          renewBefore = "30d";
          staging = false;
          reloadServices = [
            "nginx"
            "knot"
            "postfix"
          ];
          backup = true;
          rollback = true;
        };

        # Internal services certificate (self-signed)
        internal-services = {
          type = "selfSigned";
          domain = "internal.gateway.example.com";
          keySize = 4096;
          validDays = 365;
          renewBefore = "14d";
          reloadServices = [ "nginx" ];
          backup = true;
          rollback = true;
        };

        # VPN certificate
        vpn = {
          type = "selfSigned";
          domain = "vpn.gateway.example.com";
          keySize = 2048;
          validDays = 90;
          renewBefore = "7d";
          reloadServices = [ "openvpn" ];
          backup = true;
          rollback = true;
        };

        # Wildcard certificate for subdomains
        wildcard = {
          type = "acme";
          domain = "*.gateway.example.com";
          email = "admin@example.com";
          renewBefore = "21d";
          staging = false;
          dnsProvider = "cloudflare";
          dnsCredentials = {
            CLOUDFLARE_API_TOKEN = "{{secret:cloudflare-api-token}}";
            CLOUDFLARE_ZONE_ID = "{{secret:cloudflare-zone-id}}";
          };
          reloadServices = [
            "nginx"
            "knot"
          ];
          backup = true;
          rollback = true;
        };
      };

      # Key rotation configuration
      keys = {
        # WireGuard VPN keys
        wireguard-wan = {
          type = "wireguard";
          interface = "wg0";
          rotationInterval = "90d";
          coordinationRequired = true;
          peerNotification = true;
          peers = [
            "peer1.example.com"
            "peer2.example.com"
            "peer3.example.com"
          ];
          dependentServices = [ "wg-quick@wg0" ];
          backup = true;
          rollback = true;
        };

        wireguard-lan = {
          type = "wireguard";
          interface = "wg1";
          rotationInterval = "180d";
          coordinationRequired = false;
          peerNotification = false;
          peers = [ ];
          dependentServices = [ "wg-quick@wg1" ];
          backup = true;
          rollback = true;
        };

        # DNS TSIG keys
        dns-primary = {
          type = "tsig";
          name = "gateway-dns-primary";
          algorithm = "hmac-sha256";
          rotationInterval = "180d";
          dependentServices = [
            "knot"
            "kea-dhcp-ddns"
          ];
          backup = true;
          rollback = true;
        };

        dns-secondary = {
          type = "tsig";
          name = "gateway-dns-secondary";
          algorithm = "hmac-sha512";
          rotationInterval = "365d";
          dependentServices = [ "knot-secondary" ];
          backup = true;
          rollback = true;
        };

        # API keys
        cloudflare-api = {
          type = "apiKey";
          serviceName = "cloudflare-api";
          rotationInterval = "90d";
          keyLength = 64;
          updateCommand = ''
            # Update Cloudflare API token in configuration
            sed -i "s/CLOUDFLARE_API_TOKEN=.*/CLOUDFLARE_API_TOKEN=$NEW_KEY/" /etc/gateway/secrets.env
            systemctl reload gateway-dns-updater
          '';
          dependentServices = [ "gateway-dns-updater" ];
          backup = true;
          rollback = true;
        };

        monitoring-api = {
          type = "apiKey";
          serviceName = "prometheus-remote-write";
          rotationInterval = "30d";
          keyLength = 32;
          updateCommand = ''
                        # Update Prometheus remote write configuration
                        cat > /etc/prometheus/remote-write-secret.yaml << EOF
            api_key: $NEW_KEY
            EOF
                        systemctl reload prometheus
          '';
          dependentServices = [ "prometheus" ];
          backup = true;
          rollback = true;
        };

        # Database credentials
        database-main = {
          type = "apiKey";
          serviceName = "postgresql-main";
          rotationInterval = "60d";
          keyLength = 48;
          updateCommand = ''
            # Update PostgreSQL password
            psql -U postgres -c "ALTER USER gateway_user WITH PASSWORD '$NEW_KEY';"
            systemctl reload postgresql
          '';
          dependentServices = [
            "postgresql"
            "gateway-api"
          ];
          backup = true;
          rollback = true;
        };
      };

      # Rotation monitoring configuration
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

    # Secrets configuration (integrated with rotation)
    secrets = {
      # Cloudflare API token
      cloudflare-api-token = {
        type = "apiKey";
        key = "{{secret:cloudflare-api-token-encrypted}}";
        rotation = {
          enabled = true;
          interval = "90d";
          backup = true;
        };
      };

      # Cloudflare zone ID
      cloudflare-zone-id = {
        type = "apiKey";
        key = "{{secret:cloudflare-zone-id-encrypted}}";
        rotation = {
          enabled = false; # Zone ID doesn't rotate
        };
      };

      # Let's Encrypt account key
      letsencrypt-account = {
        type = "apiKey";
        key = "{{secret:letsencrypt-account-key}}";
        rotation = {
          enabled = false; # Account key rotation is manual
        };
      };
    };

    # Network configuration
    data = {
      network = {
        subnets = {
          lan = {
            ipv4 = {
              subnet = "192.168.1.0/24";
              gateway = "192.168.1.1";
            };
            ipv6 = {
              prefix = "2001:db8:1::/64";
              gateway = "2001:db8:1::1";
            };
          };

          wan = {
            ipv4 = {
              subnet = "203.0.113.0/24";
              gateway = "203.0.113.1";
            };
            ipv6 = {
              prefix = "2001:db8:2::/64";
              gateway = "2001:db8:2::1";
            };
          };

          vpn = {
            ipv4 = {
              subnet = "10.0.0.0/24";
              gateway = "10.0.0.1";
            };
            ipv6 = {
              prefix = "fd00:1::/64";
              gateway = "fd00:1::1";
            };
          };
        };
      };
    };
  };

  # WireGuard configuration
  networking.wireguard.interfaces = {
    wg0 = {
      ips = [
        "10.0.0.1/24"
        "fd00:1::1/64"
      ];
      privateKey = "{{secret:wireguard-wan-private-key}}";
      peers = [
        {
          publicKey = "{{secret:peer1-public-key}}";
          allowedIPs = [
            "10.0.0.2/32"
            "fd00:1::2/128"
          ];
          endpoint = "peer1.example.com:51820";
        }
        {
          publicKey = "{{secret:peer2-public-key}}";
          allowedIPs = [
            "10.0.0.3/32"
            "fd00:1::3/128"
          ];
          endpoint = "peer2.example.com:51820";
        }
      ];
    };

    wg1 = {
      ips = [ "10.1.0.1/24" ];
      privateKey = "{{secret:wireguard-lan-private-key}}";
      peers = [
        {
          publicKey = "{{secret:lan-peer1-public-key}}";
          allowedIPs = [ "10.1.0.2/32" ];
        }
      ];
    };
  };

  # DNS configuration
  services.knot = {
    enable = true;
    settings = {
      server = {
        listen = [
          "0.0.0.0@53"
          "::@53"
        ];
      };

      zones = {
        "gateway.example.com" = {
          file = "/var/lib/knot/gateway.example.com.zone";
          dnssec-signing = true;
          dnssec-policy = "default";
        };
      };

      acl = {
        "transfer-allowed" = {
          address = [ "192.168.1.0/24" ];
          action = "transfer";
        };
      };

      key = {
        "gateway-dns-primary" = {
          algorithm = "hmac-sha256";
          secret = "{{secret:dns-primary-key}}";
        };
      };
    };
  };

  # DHCP configuration
  services.kea = {
    dhcp4 = {
      enable = true;
      settings = {
        interfaces-config = {
          interfaces = [ "eth1" ];
        };

        lease-database = {
          type = "memfile";
          persist = true;
          name = "/var/lib/kea/dhcp4.leases";
        };

        subnet4 = [
          {
            subnet = "192.168.1.0/24";
            pools = [
              {
                pool = "192.168.1.100 - 192.168.1.200";
              }
            ];
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
        enableACME = true;
        locations."/" = {
          proxyPass = "http://localhost:8080";
        };
      };

      "internal.gateway.example.com" = {
        forceSSL = true;
        sslCertificate = "/run/gateway-secrets/internal-services.crt";
        sslCertificateKey = "/run/gateway-secrets/internal-services.key";
        locations."/" = {
          proxyPass = "http://localhost:8081";
        };
      };
    };
  };

  # Monitoring configuration
  services.prometheus = {
    enable = true;

    remoteWrite = [
      {
        url = "https://prometheus-remote.example.com/api/v1/write";
        basicAuth = {
          username = "gateway";
          passwordFile = "/run/gateway-secrets/monitoring-api.apikey";
        };
      }
    ];
  };

  # Required packages
  environment.systemPackages = with pkgs; [
    openssl
    certbot
    wireguard-tools
    knot
    nginx
    prometheus
  ];

  # System configuration
  system.stateVersion = "23.11";

  # Enable required services
  systemd.services = {
    # Custom service for DNS updates
    gateway-dns-updater = {
      description = "Gateway DNS updater service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.coreutils}/bin/true";
        User = "root";
      };
    };
  };

  # Firewall configuration
  networking.firewall = {
    enable = true;

    allowedTCPPorts = [
      22 # SSH
      53 # DNS
      80 # HTTP
      443 # HTTPS
      51820 # WireGuard
    ];

    allowedUDPPorts = [
      53 # DNS
      51820 # WireGuard
    ];
  };

  # Backup configuration
  services.backup = {
    enable = true;
    directories = [
      "/var/backups/gateway-secrets"
      "/var/lib/knot"
      "/var/lib/kea"
    ];
  };
}

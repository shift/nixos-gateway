# Gateway Secrets Configuration (agenix encrypted)
# This file should be encrypted with agenix before deployment

{
  # TLS certificates for gateway services
  tls = {
    gateway-cert = {
      type = "tlsCertificate";
      certificate = ./certs/gateway.crt.age;
      private_key = ./certs/gateway.key.age;
      description = "Gateway TLS certificate for HTTPS services";

      # Secret rotation configuration
      rotation = {
        enabled = true;
        interval = "90d";
        backup = true;
      };

      # Access control
      access = {
        "root" = [
          "read"
          "write"
          "delete"
        ];
        "nginx" = [ "read" ];
        "haproxy" = [ "read" ];
      };

      # agenix integration
      agenix = {
        file = ./gateway-cert.age;
        mode = "0600";
        owner = "root";
        group = "root";
      };
    };
  };

  # WireGuard VPN keys
  vpn = {
    wireguard = {
      type = "wireguardKey";
      private_key = ./wireguard/private.key.age;
      preshared_keys = {
        "peer1" = ./wireguard/peer1-psk.age;
        "peer2" = ./wireguard/peer2-psk.age;
      };
      description = "WireGuard VPN keys for site-to-site connections";

      rotation = {
        enabled = false; # Manual rotation for VPN keys
        interval = "365d";
        backup = true;
      };

      access = {
        "root" = [
          "read"
          "write"
          "delete"
        ];
        "systemd-network" = [ "read" ];
      };

      agenix = {
        file = ./wireguard-keys.age;
        mode = "0600";
        owner = "root";
        group = "systemd-network";
      };
    };
  };

  # DNS TSIG keys for dynamic updates
  dns = {
    tsig_keys = {
      ddns-update = {
        type = "tsigKey";
        key = ./dns/ddns-key.age;
        algorithm = "hmac-sha256";
        name = "ddns-update";
        description = "TSIG key for dynamic DNS updates";

        rotation = {
          enabled = true;
          interval = "180d";
          backup = true;
        };

        access = {
          "root" = [
            "read"
            "write"
            "delete"
          ];
          "bind" = [ "read" ];
          "nsd" = [ "read" ];
        };

        agenix = {
          file = ./dns-ddns-key.age;
          mode = "0640";
          owner = "root";
          group = "named";
        };
      };
    };
  };

  # Monitoring and API keys
  monitoring = {
    prometheus-remote = {
      type = "apiKey";
      key = ./monitoring/prometheus-remote-key.age;
      description = "Prometheus remote write API key";

      rotation = {
        enabled = true;
        interval = "90d";
        backup = true;
      };

      access = {
        "root" = [
          "read"
          "write"
          "delete"
        ];
        "prometheus" = [ "read" ];
      };

      agenix = {
        file = ./prometheus-remote-key.age;
        mode = "0600";
        owner = "prometheus";
        group = "prometheus";
      };
    };

    grafana-admin = {
      type = "apiKey";
      key = ./monitoring/grafana-admin-key.age;
      description = "Grafana admin API key";

      rotation = {
        enabled = true;
        interval = "60d";
        backup = true;
      };

      access = {
        "root" = [
          "read"
          "write"
          "delete"
        ];
        "grafana" = [ "read" ];
      };

      agenix = {
        file = ./grafana-admin-key.age;
        mode = "0600";
        owner = "grafana";
        group = "grafana";
      };
    };
  };

  # Database credentials
  databases = {
    metrics-db = {
      type = "databasePassword";
      password = ./databases/metrics-db-password.age;
      description = "Metrics database password";

      rotation = {
        enabled = true;
        interval = "90d";
        backup = true;
      };

      access = {
        "root" = [
          "read"
          "write"
          "delete"
        ];
        "postgres" = [ "read" ];
        "prometheus" = [ "read" ];
      };

      agenix = {
        file = ./metrics-db-password.age;
        mode = "0600";
        owner = "postgres";
        group = "postgres";
      };
    };

    logs-db = {
      type = "databasePassword";
      password = ./databases/logs-db-password.age;
      description = "Logs database password";

      rotation = {
        enabled = true;
        interval = "90d";
        backup = true;
      };

      access = {
        "root" = [
          "read"
          "write"
          "delete"
        ];
        "postgres" = [ "read" ];
        "loki" = [ "read" ];
      };

      agenix = {
        file = ./logs-db-password.age;
        mode = "0600";
        owner = "postgres";
        group = "postgres";
      };
    };
  };
}

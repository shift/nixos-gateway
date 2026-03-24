# Example secrets configuration for NixOS Gateway
# This file should be encrypted with sops-nix or agenix

{
  # TLS certificates for web services
  tls = {
    type = "tlsCertificate";
    certificate = ./certs/gateway.crt;
    private_key = ./certs/gateway.key;

    # sops-nix integration
    sops = {
      format = "binary";
      mode = "0400";
      owner = "nginx";
      group = "nginx";
    };

    # Access control
    access = {
      "root" = [
        "read"
        "write"
        "delete"
      ];
      "nginx" = [ "read" ];
      "prometheus" = [ "read" ];
    };

    # Rotation configuration
    rotation = {
      enabled = true;
      interval = "30d";
      backup = true;
    };
  };

  # WireGuard VPN configuration
  vpn = {
    type = "wireguardKey";
    private_key = ./keys/wireguard-private.key;

    preshared_keys = {
      "peer1" = ./keys/wireguard-peer1-psk.key;
      "peer2" = ./keys/wireguard-peer2-psk.key;
    };

    # sops-nix integration
    sops = {
      format = "binary";
      mode = "0400";
      owner = "root";
      group = "root";
    };

    access = {
      "root" = [
        "read"
        "write"
        "delete"
      ];
      "systemd-network" = [ "read" ];
    };

    rotation = {
      enabled = false; # Manual rotation for VPN keys
    };
  };

  # DNS TSIG keys for dynamic updates
  dns = {
    type = "tsigKey";
    key = "ThisIsASecretTSIGKeyBase64Encoded==";
    algorithm = "hmac-sha256";
    name = "ddns-update";

    # sops-nix integration
    sops = {
      format = "yaml";
      mode = "0400";
      owner = "bind";
      group = "bind";
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

    rotation = {
      enabled = true;
      interval = "90d";
      backup = true;
    };
  };

  # Monitoring API keys
  monitoring = {
    type = "apiKey";
    key = "prometheus-remote-write-api-key";

    # sops-nix integration
    sops = {
      format = "yaml";
      mode = "0400";
      owner = "prometheus";
      group = "prometheus";
    };

    access = {
      "root" = [
        "read"
        "write"
        "delete"
      ];
      "prometheus" = [ "read" ];
    };

    rotation = {
      enabled = true;
      interval = "60d";
      backup = true;
    };
  };

  # Database credentials
  database = {
    type = "databasePassword";
    password = "secure-database-password";

    # sops-nix integration
    sops = {
      format = "yaml";
      mode = "0400";
      owner = "postgres";
      group = "postgres";
    };

    access = {
      "root" = [
        "read"
        "write"
        "delete"
      ];
      "postgres" = [ "read" ];
    };

    rotation = {
      enabled = true;
      interval = "90d";
      backup = true;
    };
  };

  # External service API keys
  external_apis = {
    cloudflare = {
      type = "apiKey";
      key = "cloudflare-api-token";

      sops = {
        format = "yaml";
        mode = "0400";
        owner = "root";
        group = "root";
      };

      access = {
        "root" = [
          "read"
          "write"
          "delete"
        ];
        "acme" = [ "read" ];
      };

      rotation = {
        enabled = true;
        interval = "180d";
        backup = true;
      };
    };

    pushover = {
      type = "apiKey";
      key = "pushover-notification-key";

      sops = {
        format = "yaml";
        mode = "0400";
        owner = "root";
        group = "root";
      };

      access = {
        "root" = [
          "read"
          "write"
          "delete"
        ];
        "alertmanager" = [ "read" ];
      };

      rotation = {
        enabled = false; # Notification keys rarely need rotation
      };
    };
  };
}

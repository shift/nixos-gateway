# Environment-specific secrets configuration
# This demonstrates how to use different secrets for different environments

{
  # Common secrets shared across all environments
  common = {
    # Base TLS certificate (might be self-signed in dev)
    tls = {
      type = "tlsCertificate";
      certificate = ./certs/gateway-common.crt;
      private_key = ./certs/gateway-common.key;

      sops = {
        format = "binary";
        mode = "0400";
      };

      access = {
        "root" = [
          "read"
          "write"
          "delete"
        ];
      };
    };
  };

  # Development environment secrets
  development = {
    # Development database (weaker passwords acceptable)
    database = {
      type = "databasePassword";
      password = "dev-password-123";

      sops = {
        format = "yaml";
        mode = "0400";
      };

      access = {
        "root" = [
          "read"
          "write"
          "delete"
        ];
        "developer" = [ "read" ];
      };

      rotation = {
        enabled = false; # No rotation needed in dev
      };
    };

    # Development API keys (test keys)
    apis = {
      type = "apiKey";
      key = "dev-api-key-for-testing";

      sops = {
        format = "yaml";
        mode = "0400";
      };

      access = {
        "root" = [
          "read"
          "write"
          "delete"
        ];
        "developer" = [
          "read"
          "write"
        ];
      };
    };
  };

  # Staging environment secrets
  staging = {
    # Staging database (stronger passwords)
    database = {
      type = "databasePassword";
      password = "staging-secure-password-456";

      sops = {
        format = "yaml";
        mode = "0400";
      };

      access = {
        "root" = [
          "read"
          "write"
          "delete"
        ];
        "staging-user" = [ "read" ];
      };

      rotation = {
        enabled = true;
        interval = "30d";
        backup = true;
      };
    };

    # Staging API keys (production-like but for testing)
    apis = {
      type = "apiKey";
      key = "staging-api-key-789";

      sops = {
        format = "yaml";
        mode = "0400";
      };

      access = {
        "root" = [
          "read"
          "write"
          "delete"
        ];
        "staging-user" = [ "read" ];
      };

      rotation = {
        enabled = true;
        interval = "60d";
        backup = true;
      };
    };
  };

  # Production environment secrets
  production = {
    # Production TLS certificates (real certificates)
    tls = {
      type = "tlsCertificate";
      certificate = ./certs/production/gateway.crt;
      private_key = ./certs/production/gateway.key;

      sops = {
        format = "binary";
        mode = "0400";
        owner = "nginx";
        group = "nginx";
      };

      access = {
        "root" = [
          "read"
          "write"
          "delete"
        ];
        "nginx" = [ "read" ];
        "prometheus" = [ "read" ];
      };

      rotation = {
        enabled = true;
        interval = "30d";
        backup = true;
      };
    };

    # Production database (strong passwords)
    database = {
      type = "databasePassword";
      password = "very-secure-production-password-789";

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

    # Production API keys
    apis = {
      type = "apiKey";
      key = "production-api-key-very-secure";

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
        "prometheus" = [ "read" ];
      };

      rotation = {
        enabled = true;
        interval = "60d";
        backup = true;
      };
    };

    # Production VPN keys
    vpn = {
      type = "wireguardKey";
      private_key = ./keys/production/wireguard.key;

      preshared_keys = {
        "datacenter-1" = ./keys/production/dc1-psk.key;
        "datacenter-2" = ./keys/production/dc2-psk.key;
      };

      sops = {
        format = "binary";
        mode = "0400";
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
        enabled = false; # Manual rotation for production VPN
      };
    };
  };

  # Testing environment secrets
  testing = {
    # Mock secrets for automated testing
    mock_tls = {
      type = "tlsCertificate";
      certificate = ./certs/testing/mock.crt;
      private_key = ./certs/testing/mock.key;

      sops = {
        format = "binary";
        mode = "0400";
      };

      access = {
        "root" = [
          "read"
          "write"
          "delete"
        ];
        "test-runner" = [ "read" ];
      };
    };

    # Test database (known password for testing)
    database = {
      type = "databasePassword";
      password = "test-password-known";

      sops = {
        format = "yaml";
        mode = "0400";
      };

      access = {
        "root" = [
          "read"
          "write"
          "delete"
        ];
        "test-runner" = [
          "read"
          "write"
        ];
      };

      rotation = {
        enabled = false; # Fixed password for testing
      };
    };
  };
}

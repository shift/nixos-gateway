# Environment-specific secrets configuration
# This file demonstrates how to use environment-specific secrets

{
  # Common secrets shared across all environments
  common = {
    # Base TLS certificate (different per environment)
    tls = {
      gateway-cert = {
        type = "tlsCertificate";
        certificate = ./common/certs/gateway.crt.age;
        private_key = ./common/certs/gateway.key.age;
        description = "Gateway TLS certificate";

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
          "nginx" = [ "read" ];
        };
      };
    };
  };

  # Development environment secrets
  development = {
    # Development-specific secrets
    monitoring = {
      prometheus-dev = {
        type = "apiKey";
        key = ./development/monitoring/prometheus-dev-key.age;
        description = "Development Prometheus API key";

        rotation = {
          enabled = false; # No rotation in dev
          interval = "365d";
          backup = false;
        };

        access = {
          "root" = [
            "read"
            "write"
            "delete"
          ];
          "prometheus" = [ "read" ];
          "developer" = [ "read" ]; # Dev access in development
        };
      };
    };

    # Development database
    databases = {
      dev-db = {
        type = "databasePassword";
        password = ./development/databases/dev-db-password.age;
        description = "Development database password";

        rotation = {
          enabled = false;
          interval = "365d";
          backup = false;
        };

        access = {
          "root" = [
            "read"
            "write"
            "delete"
          ];
          "postgres" = [ "read" ];
          "developer" = [ "read" ];
        };
      };
    };
  };

  # Staging environment secrets
  staging = {
    # Staging-specific secrets
    monitoring = {
      prometheus-staging = {
        type = "apiKey";
        key = ./staging/monitoring/prometheus-staging-key.age;
        description = "Staging Prometheus API key";

        rotation = {
          enabled = true;
          interval = "60d"; # More frequent rotation in staging
          backup = true;
        };

        access = {
          "root" = [
            "read"
            "write"
            "delete"
          ];
          "prometheus" = [ "read" ];
          "staging-admin" = [ "read" ];
        };
      };
    };

    # Staging database
    databases = {
      staging-db = {
        type = "databasePassword";
        password = ./staging/databases/staging-db-password.age;
        description = "Staging database password";

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
          "postgres" = [ "read" ];
          "staging-admin" = [ "read" ];
        };
      };
    };
  };

  # Production environment secrets
  production = {
    # Production-specific secrets
    monitoring = {
      prometheus-prod = {
        type = "apiKey";
        key = ./production/monitoring/prometheus-prod-key.age;
        description = "Production Prometheus API key";

        rotation = {
          enabled = true;
          interval = "30d"; # Frequent rotation in production
          backup = true;
        };

        access = {
          "root" = [
            "read"
            "write"
            "delete"
          ];
          "prometheus" = [ "read" ];
          # No additional access in production
        };
      };
    };

    # Production database
    databases = {
      prod-db = {
        type = "databasePassword";
        password = ./production/databases/prod-db-password.age;
        description = "Production database password";

        rotation = {
          enabled = true;
          interval = "30d";
          backup = true;
        };

        access = {
          "root" = [
            "read"
            "write"
            "delete"
          ];
          "postgres" = [ "read" ];
          # Minimal access in production
        };
      };
    };

    # Production VPN keys
    vpn = {
      wireguard-prod = {
        type = "wireguardKey";
        private_key = ./production/vpn/wireguard-prod.key.age;
        preshared_keys = {
          "datacenter1" = ./production/vpn/dc1-psk.age;
          "datacenter2" = ./production/vpn/dc2-psk.age;
        };
        description = "Production WireGuard VPN keys";

        rotation = {
          enabled = false; # Manual rotation for production VPN
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
      };
    };
  };

  # Testing environment secrets
  testing = {
    # Test-specific secrets (often mock or temporary)
    monitoring = {
      prometheus-test = {
        type = "apiKey";
        key = ./testing/monitoring/prometheus-test-key.age;
        description = "Test Prometheus API key";

        rotation = {
          enabled = false;
          interval = "365d";
          backup = false;
        };

        access = {
          "root" = [
            "read"
            "write"
            "delete"
          ];
          "prometheus" = [ "read" ];
          "test-runner" = [
            "read"
            "write"
          ]; # Test automation access
        };
      };
    };

    # Test database
    databases = {
      test-db = {
        type = "databasePassword";
        password = ./testing/databases/test-db-password.age;
        description = "Test database password";

        rotation = {
          enabled = false;
          interval = "365d";
          backup = false;
        };

        access = {
          "root" = [
            "read"
            "write"
            "delete"
          ];
          "postgres" = [ "read" ];
          "test-runner" = [
            "read"
            "write"
          ];
        };
      };
    };
  };
}

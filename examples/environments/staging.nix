{ lib, pkgs }:

{
  environment = "staging";

  metadata = {
    description = "Staging environment mirroring production with testing features";
    owner = "qa-team";
    contact = "qa-team@example.com";
    version = "1.0.0";
  };

  overrides = {
    # Gateway service configuration for staging
    services.gateway = {
      data = {
        firewall = {
          zones.green.allowedTCPPorts = [
            22
            53
            80
            443
            9090
          ];
          zones.green.allowedUDPPorts = [
            53
            67
            68
            123
            547
          ];
          zones.mgmt.allowedTCPPorts = [
            22
            53
            80
            443
            9090
            9142
          ];
          zones.mgmt.allowedUDPPorts = [
            53
            123
          ];
        };
        ids = {
          detectEngine.profile = "medium";
          logging.eveLog.types = [
            "alert"
            "http"
            "dns"
            "tls"
            "files"
            "flow"
            "drop"
          ];
          threading.setCpuAffinity = true;
        };
      };
      monitoring = {
        enable = true;
        exporters = {
          node.enable = true;
          systemd.enable = true;
          process.enable = false;
          postgresql.enable = false;
          redis.enable = false;
        };
        grafana = {
          enable = true;
          port = 3000;
          adminPassword = "staging-admin";
        };
        prometheus = {
          enable = true;
          port = 9090;
          retention = "30d";
        };
      };
      logging = {
        level = "info";
        enableConsole = false;
        enableFile = true;
        enableSyslog = true;
      };
    };

    # Staging-specific system settings
    boot.kernel.sysctl = {
      "net.core.rmem_max" = 134217728;
      "net.core.wmem_max" = 134217728;
      "net.ipv4.tcp_rmem" = "4096 65536 134217728";
      "net.ipv4.tcp_wmem" = "4096 65536 134217728";
    };

    # Staging security settings (production-like)
    security = {
      sudo.wheelNeedsPassword = true;
      sudo.execWheelOnly = true;
    };

    # Staging networking
    networking = {
      firewall.enable = true;
      hostName = "gateway-staging";
      domain = "staging.example.com";
    };

    # Staging services
    services = {
      openssh = {
        enable = true;
        settings = {
          PasswordAuthentication = false;
          PermitRootLogin = "no";
          X11Forwarding = false;
        };
      };

      # Staging database (smaller than production)
      postgresql = {
        enable = true;
        enableTCPIP = true;
        settings = {
          max_connections = 100;
          shared_buffers = "128MB";
        };
      };

      # Staging cache
      redis = {
        enable = true;
        bind = "127.0.0.1";
        port = 6379;
        maxmemory = "256mb";
      };
    };

    # Staging environment variables
    environment.variables = {
      NODE_ENV = "staging";
      LOG_LEVEL = "info";
      NIXOS_GATEWAY_ENV = "staging";
    };

    # Staging packages
    environment.systemPackages = with pkgs; [
      vim
      git
      curl
      wget
      htop
      tcpdump
      nmap
    ];
  };
}

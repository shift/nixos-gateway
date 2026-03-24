{ lib, pkgs }:

{
  environment = "production";

  metadata = {
    description = "Production environment optimized for performance and security";
    owner = "ops-team";
    contact = "ops-team@example.com";
    version = "1.0.0";
  };

  overrides = {
    # Gateway service configuration for production
    services.gateway = {
      data = {
        firewall = {
          zones.green.allowedTCPPorts = [
            22
            53
            80
            443
          ];
          zones.green.allowedUDPPorts = [
            53
            67
            68
            123
            47
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
          detectEngine.profile = "high";
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
          threading.managementCpus = [ 0 ];
          threading.workerCpus = [
            1
            2
            3
          ];
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
          adminPassword = "prod-secure-password";
        };
        prometheus = {
          enable = true;
          port = 9090;
          retention = "90d";
        };
      };
      logging = {
        level = "warn";
        enableConsole = false;
        enableFile = true;
        enableSyslog = true;
      };
    };

    # Production-specific system settings (optimized)
    boot.kernel.sysctl = {
      "net.core.rmem_max" = 268435456;
      "net.core.wmem_max" = 268435456;
      "net.ipv4.tcp_rmem" = "4096 87380 268435456";
      "net.ipv4.tcp_wmem" = "4096 65536 268435456";
      "net.ipv4.tcp_congestion_control" = "bbr";
      "net.core.netdev_max_backlog" = 5000;
      "net.ipv4.tcp_max_syn_backlog" = 4096;
    };

    # Production security settings (strict)
    security = {
      sudo.wheelNeedsPassword = true;
      sudo.execWheelOnly = true;
      sudo.extraRules = [ ];
      protectKernelImage = true;
      lockKernelModules = true;
    };

    # Production networking
    networking = {
      firewall.enable = true;
      hostName = "gateway-prod";
      domain = "example.com";
      useDHCP = false;
    };

    # Production services
    services = {
      openssh = {
        enable = true;
        settings = {
          PasswordAuthentication = false;
          PermitRootLogin = "no";
          X11Forwarding = false;
          MaxAuthTries = 3;
          ClientAliveInterval = 300;
          ClientAliveCountMax = 2;
        };
      };

      # Production database (optimized)
      postgresql = {
        enable = true;
        enableTCPIP = true;
        settings = {
          max_connections = 200;
          shared_buffers = "256MB";
          effective_cache_size = "1GB";
          work_mem = "4MB";
          maintenance_work_mem = "64MB";
        };
      };

      # Production cache (optimized)
      redis = {
        enable = true;
        bind = "127.0.0.1";
        port = 6379;
        maxmemory = "512mb";
        maxmemoryPolicy = "allkeys-lru";
      };
    };

    # Production environment variables
    environment.variables = {
      NODE_ENV = "production";
      LOG_LEVEL = "warn";
      NIXOS_GATEWAY_ENV = "production";
    };

    # Production packages (minimal)
    environment.systemPackages = with pkgs; [
      vim
      curl
      wget
      htop
    ];
  };
}

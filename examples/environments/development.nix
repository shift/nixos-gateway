{ lib, pkgs }:

{
  environment = "development";

  metadata = {
    description = "Development environment with enhanced debugging and relaxed security";
    owner = "development-team";
    contact = "dev-team@example.com";
    version = "1.0.0";
  };

  overrides = {
    # Gateway service configuration for development
    services.gateway = {
      data = {
        firewall = {
          zones.green.allowedTCPPorts = [
            22
            53
            80
            443
            8080
            3000
            5000
            9090
          ];
          zones.green.allowedUDPPorts = [
            53
            67
            68
            123
            547
            8080
            3000
          ];
          zones.mgmt.allowedTCPPorts = [
            22
            53
            80
            443
            8080
            3000
            5000
            9090
            9142
          ];
          zones.mgmt.allowedUDPPorts = [
            53
            123
          ];
        };
        ids = {
          detectEngine.profile = "low";
          logging.eveLog.types = [
            "alert"
            "http"
            "dns"
            "tls"
            "files"
            "flow"
            "drop"
            "http2"
            "smtp"
            "ftp"
          ];
          threading.setCpuAffinity = false;
        };
      };
      monitoring = {
        enable = true;
        exporters = {
          node.enable = true;
          systemd.enable = true;
          process.enable = true;
          postgresql.enable = true;
          redis.enable = true;
        };
        grafana = {
          enable = true;
          port = 3000;
          adminPassword = "admin";
        };
        prometheus = {
          enable = true;
          port = 9090;
          retention = "7d";
        };
      };
      logging = {
        level = "debug";
        enableConsole = true;
        enableFile = true;
        enableSyslog = false;
      };
    };

    # Development-specific system settings
    boot.kernel.sysctl = {
      "net.core.rmem_max" = 67108864;
      "net.core.wmem_max" = 67108864;
      "net.ipv4.tcp_rmem" = "4096 65536 67108864";
      "net.ipv4.tcp_wmem" = "4096 65536 67108864";
      "kernel.printk" = "7 4 1 7";
    };

    # Development security settings (relaxed)
    security = {
      sudo.wheelNeedsPassword = false;
      sudo.execWheelOnly = false;
      sudo.extraRules = [
        {
          users = [ "developer" ];
          commands = [ "ALL" ];
        }
      ];
    };

    # Development networking
    networking = {
      firewall.enable = false; # Disabled for easier debugging
      hostName = "gateway-dev";
      domain = "dev.local";
    };

    # Development services
    services = {
      openssh = {
        enable = true;
        settings = {
          PasswordAuthentication = true;
          PermitRootLogin = "yes";
          X11Forwarding = true;
        };
      };

      # Development database
      postgresql = {
        enable = true;
        enableTCPIP = true;
        authentication = ''
          local all all trust
          host all all 127.0.0.1/32 trust
          host all all ::1/128 trust
        '';
      };

      # Development cache
      redis = {
        enable = true;
        bind = "127.0.0.1";
        port = 6379;
      };
    };

    # Development environment variables
    environment.variables = {
      NODE_ENV = "development";
      DEBUG = "*";
      LOG_LEVEL = "debug";
      NIXOS_GATEWAY_ENV = "development";
    };

    # Development packages
    environment.systemPackages = with pkgs; [
      vim
      git
      curl
      wget
      htop
      strace
      tcpdump
      wireshark-cli
      nmap
      postgresql
      redis
    ];
  };
}

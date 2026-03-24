{ lib, pkgs }:

{
  environment = "testing";

  metadata = {
    description = "Testing environment with isolated services and mock data";
    owner = "test-team";
    contact = "test-team@example.com";
    version = "1.0.0";
  };

  overrides = {
    # Gateway service configuration for testing
    services.gateway = {
      data = {
        firewall = {
          zones.green.allowedTCPPorts = [
            22
            53
            80
            443
            8080
            9090
          ];
          zones.green.allowedUDPPorts = [
            53
            67
            68
            123
            547
            8080
          ];
          zones.mgmt.allowedTCPPorts = [
            22
            53
            80
            443
            8080
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
          adminPassword = "test-admin";
        };
        prometheus = {
          enable = true;
          port = 9090;
          retention = "1d";
        };
      };
      logging = {
        level = "debug";
        enableConsole = true;
        enableFile = true;
        enableSyslog = false;
      };
    };

    # Testing-specific system settings (minimal)
    boot.kernel.sysctl = {
      "net.core.rmem_max" = 16777216;
      "net.core.wmem_max" = 16777216;
      "net.ipv4.tcp_rmem" = "4096 65536 16777216";
      "net.ipv4.tcp_wmem" = "4096 65536 16777216";
    };

    # Testing security settings (minimal)
    security = {
      sudo.wheelNeedsPassword = false;
      sudo.execWheelOnly = false;
      sudo.extraRules = [
        {
          users = [ "tester" ];
          commands = [ "ALL" ];
        }
      ];
    };

    # Testing networking (isolated)
    networking = {
      firewall.enable = false; # Disabled for testing
      hostName = "gateway-test";
      domain = "test.local";
      useDHCP = true;
    };

    # Testing services (with mocks)
    services = {
      openssh = {
        enable = true;
        settings = {
          PasswordAuthentication = true;
          PermitRootLogin = "yes";
          X11Forwarding = true;
        };
      };

      # Testing database (in-memory)
      postgresql = {
        enable = true;
        enableTCPIP = true;
        settings = {
          max_connections = 50;
          shared_buffers = "32MB";
          fsync = false; # Faster for testing
          synchronous_commit = "off";
        };
      };

      # Testing cache (in-memory)
      redis = {
        enable = true;
        bind = "127.0.0.1";
        port = 6379;
        maxmemory = "64mb";
        save = ""; # No persistence for testing
      };
    };

    # Testing environment variables
    environment.variables = {
      NODE_ENV = "test";
      DEBUG = "*";
      LOG_LEVEL = "debug";
      NIXOS_GATEWAY_ENV = "testing";
      TEST_MODE = "true";
    };

    # Testing packages (comprehensive)
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
      jq
      bc
      netcat
      telnet
    ];
  };
}

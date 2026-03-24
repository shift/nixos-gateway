# NAT Gateway Example Configuration
# This example demonstrates a complete NAT Gateway setup with multiple instances,
# monitoring, and integration with other gateway services.

{ config, lib, pkgs, ... }:

let
  # Example network configuration
  networkConfig = {
    wanInterface = "eth0";
    lanInterface = "eth1";
    dmzInterface = "eth2";

    subnets = {
      lan = "192.168.1.0/24";
      dmz = "172.16.0.0/24";
      guest = "10.0.0.0/24";
    };

    publicIPs = [
      "203.0.113.10"
      "203.0.113.11"
      "203.0.113.12"
    ];
  };

in {
  # Network interface configuration
  networking = {
    useDHCP = false;
    interfaces = {
      "${networkConfig.wanInterface}" = {
        ipv4.addresses = [
          { address = networkConfig.publicIPs[0]; prefixLength = 24; }
          { address = networkConfig.publicIPs[1]; prefixLength = 24; }
          { address = networkConfig.publicIPs[2]; prefixLength = 24; }
        ];
        ipv4.routes = [
          { address = "0.0.0.0"; prefixLength = 0; via = "203.0.113.1"; }
        ];
      };

      "${networkConfig.lanInterface}" = {
        ipv4.addresses = [
          { address = "192.168.1.1"; prefixLength = 24; }
        ];
      };

      "${networkConfig.dmzInterface}" = {
        ipv4.addresses = [
          { address = "172.16.0.1"; prefixLength = 24; }
        ];
      };
    };

    # Enable IP forwarding for NAT
    firewall.enable = true;
    nat.enable = false; # We'll use our custom NAT Gateway instead
  };

  # Gateway data configuration
  services.gateway = {
    enable = true;

    data = {
      network = {
        interfaces = {
          wan = networkConfig.wanInterface;
          lan = networkConfig.lanInterface;
          dmz = networkConfig.dmzInterface;
        };
        subnets = {
          lan = {
            ipv4 = {
              subnet = networkConfig.subnets.lan;
              gateway = "192.168.1.1";
            };
          };
          dmz = {
            ipv4 = {
              subnet = networkConfig.subnets.dmz;
              gateway = "172.16.0.1";
            };
          };
          guest = {
            ipv4 = {
              subnet = networkConfig.subnets.guest;
              gateway = "10.0.0.1";
            };
          };
        };
      };

      firewall = {
        rules = [
          # Allow outbound traffic from private networks
          {
            name = "allow-outbound-private";
            direction = "outbound";
            source = {
              subnets = [
                networkConfig.subnets.lan
                networkConfig.subnets.dmz
                networkConfig.subnets.guest
              ];
            };
            action = "accept";
          }
          # Block inbound traffic by default
          {
            name = "block-inbound-default";
            direction = "inbound";
            action = "drop";
          }
        ];
      };
    };

    # NAT Gateway configuration
    natGateway = {
      enable = true;

      instances = [
        # Primary NAT instance for LAN and DMZ
        {
          name = "primary-nat";
          publicInterface = networkConfig.wanInterface;
          privateSubnets = [
            networkConfig.subnets.lan
            networkConfig.subnets.dmz
          ];
          publicIPs = [
            networkConfig.publicIPs[0]
            networkConfig.publicIPs[1]
          ];

          maxConnections = 100000;
          timeout = {
            tcp = "24h";
            udp = "300s";
          };

          allowInbound = false;

          # Port forwarding for web services
          portForwarding = [
            {
              protocol = "tcp";
              port = 80;
              targetIP = "192.168.1.100";  # Web server in LAN
              targetPort = 8080;
            }
            {
              protocol = "tcp";
              port = 443;
              targetIP = "192.168.1.100";  # HTTPS
              targetPort = 8443;
            }
            {
              protocol = "tcp";
              port = 2222;
              targetIP = "172.16.0.10";   # SSH in DMZ
              targetPort = 22;
            }
          ];
        }

        # Secondary NAT instance for guest network
        {
          name = "guest-nat";
          publicInterface = networkConfig.wanInterface;
          privateSubnets = [
            networkConfig.subnets.guest
          ];
          publicIPs = [
            networkConfig.publicIPs[2]
          ];

          maxConnections = 25000;
          timeout = {
            tcp = "1h";   # Shorter timeout for guest network
            udp = "60s";
          };

          allowInbound = false;

          # Limited port forwarding for guest network
          portForwarding = [
            {
              protocol = "tcp";
              port = 8080;
              targetIP = "10.0.0.100";   # Guest web service
              targetPort = 80;
            }
          ];
        }
      ];

      # Enable comprehensive monitoring
      monitoring = {
        enable = true;
        prometheusPort = 9092;
      };
    };

    # DNS configuration
    dns = {
      enable = true;
      zones = {
        "lan.local" = {
          master = true;
          records = [
            {
              name = "@";
              type = "A";
              data = "192.168.1.1";
            }
            {
              name = "gateway";
              type = "A";
              data = "192.168.1.1";
            }
            {
              name = "web";
              type = "A";
              data = "192.168.1.100";
            }
          ];
        };
      };
    };

    # DHCP configuration
    dhcp = {
      enable = true;
      pools = [
        {
          subnet = networkConfig.subnets.lan;
          range = "192.168.1.100 192.168.1.200";
          options = {
            routers = "192.168.1.1";
            domain-name-servers = [ "192.168.1.1" ];
            domain-name = "lan.local";
          };
        }
        {
          subnet = networkConfig.subnets.dmz;
          range = "172.16.0.100 172.16.0.200";
          options = {
            routers = "172.16.0.1";
            domain-name-servers = [ "192.168.1.1" ];
          };
        }
        {
          subnet = networkConfig.subnets.guest;
          range = "10.0.0.100 10.0.0.200";
          options = {
            routers = "10.0.0.1";
            domain-name-servers = [ "8.8.8.8" "1.1.1.1" ];
          };
        }
      ];
    };
  };

  # Prometheus monitoring stack
  services.prometheus = {
    enable = true;
    exporters = {
      node = {
        enable = true;
        enabledCollectors = [ "systemd" "conntrack" "netstat" "textfile" ];
        extraFlags = [ "--collector.textfile.directory=/var/lib/prometheus-node-exporter-text-files" ];
      };
    };

    scrapeConfigs = [
      {
        job_name = "node";
        static_configs = [{
          targets = [ "localhost:9100" ];
        }];
      }
      {
        job_name = "nat_gateway";
        static_configs = [{
          targets = [ "localhost:9092" ];
        }];
        scrape_interval = "30s";
      }
    ];

    rules = [
      ''
        groups:
        - name: nat_gateway_alerts
          rules:
          - alert: NatGatewayHighConnectionCount
            expr: nat_gateway_connections_active > 80000
            for: 5m
            labels:
              severity: warning
            annotations:
              summary: "High NAT connection count"
              description: "NAT Gateway has {{ $value }} active connections"

          - alert: NatGatewayHighErrorRate
            expr: rate(nat_gateway_errors_total[5m]) > 10
            for: 5m
            labels:
              severity: warning
            annotations:
              summary: "High NAT error rate"
              description: "NAT Gateway error rate: {{ $value }} errors/minute"
      ''
    ];
  };

  # Grafana for visualization
  services.grafana = {
    enable = true;
    settings = {
      server.http_port = 3000;
      security.admin_password = "admin"; # Change in production!
    };

    provision = {
      datasources = [
        {
          name = "Prometheus";
          type = "prometheus";
          url = "http://localhost:9090";
        }
      ];

      dashboards = [
        {
          name = "NAT Gateway";
          options.path = ./nat-gateway-dashboard.json;
        }
      ];
    };
  };

  # System tuning for NAT performance
  boot.kernel.sysctl = {
    # Connection tracking
    "net.netfilter.nf_conntrack_max" = 1000000;
    "net.nf_conntrack_max" = 1000000;
    "net.netfilter.nf_conntrack_tcp_timeout_established" = 86400;
    "net.netfilter.nf_conntrack_tcp_timeout_time_wait" = 120;
    "net.netfilter.nf_conntrack_udp_timeout" = 30;
    "net.netfilter.nf_conntrack_udp_timeout_stream" = 180;

    # IP forwarding
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;

    # TCP optimizations
    "net.ipv4.tcp_tw_reuse" = 1;
    "net.ipv4.tcp_fin_timeout" = 30;

    # Buffer sizes
    "net.core.rmem_max" = 16777216;
    "net.core.wmem_max" = 16777216;
  };

  # Kernel modules for NAT
  boot.kernelModules = [
    "nf_conntrack"
    "nf_nat"
    "iptable_nat"
    "iptable_filter"
  ];

  # Ensure NAT services start after network
  systemd.services = {
    nat-gateway-monitoring = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
    };
  };

  # Log rotation for NAT logs
  services.logrotate = {
    enable = true;
    settings.nat-gateway = {
      files = "/var/log/nat-gateway/*.log";
      frequency = "daily";
      rotate = 30;
      compress = true;
      postrotate = "systemctl reload nat-gateway-monitoring";
    };
  };

  # Backup configuration for NAT rules
  services.gateway.backup = {
    enable = true;
    paths = [
      "/etc/iptables"
      "/var/lib/prometheus-node-exporter-text-files"
    ];
  };

  # Health monitoring
  services.gateway.health-monitoring = {
    enable = true;
    checks = [
      {
        name = "nat-connectivity";
        type = "script";
        script = ''
          #!/bin/bash
          # Test NAT connectivity
          ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1
          if [ $? -eq 0 ]; then
            echo "NAT connectivity OK"
            exit 0
          else
            echo "NAT connectivity FAILED"
            exit 1
          fi
        '';
        interval = "30s";
      }
    ];
  };

  # Example client configurations
  environment.etc = {
    "examples/nat-client-lan.nix".text = ''
      # Example client in LAN subnet
      networking = {
        interfaces.eth0 = {
          ipv4.addresses = [{
            address = "192.168.1.100";
            prefixLength = 24;
          }];
        };
        defaultGateway = "192.168.1.1";
        nameservers = [ "192.168.1.1" ];
      };

      # Test outbound connectivity
      systemd.services.test-nat = {
        script = "curl -s https://httpbin.org/ip";
        serviceConfig = {
          Type = "oneshot";
        };
      };
    '';

    "examples/nat-client-guest.nix".text = ''
      # Example client in guest subnet
      networking = {
        interfaces.eth0 = {
          ipv4.addresses = [{
            address = "10.0.0.100";
            prefixLength = 24;
          }];
        };
        defaultGateway = "10.0.0.1";
        nameservers = [ "8.8.8.8" "1.1.1.1" ];
      };
    '';
  };
}</content>
<parameter name="filePath">examples/nat-gateway-example.nix
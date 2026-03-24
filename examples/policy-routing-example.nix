# Policy-Based Routing Example Configuration
# This example demonstrates advanced policy-based routing capabilities

{
  config,
  pkgs,
  lib,
  ...
}:

{
  imports = [
    ../modules/default.nix
  ];

  services.gateway = {
    enable = true;

    # Network interfaces
    interfaces = {
      lan = "enp1s0f0";
      wan = "enp1s0f1";
      wan2 = "enp2s0f0";
      vpn = "wg0";
    };

    # Policy-based routing configuration
    policyRouting = {
      enable = true;

      # Define multiple routing tables for different ISPs and connections
      routingTables = {
        # Primary ISP routing table
        table100 = {
          name = "ISP1-Primary";
          priority = 100;
          defaultRoute = "192.168.100.1";
          routes = [
            "10.0.0.0/8 via 192.168.100.1"
            "172.16.0.0/12 via 192.168.100.1"
          ];
        };

        # Secondary ISP routing table
        table200 = {
          name = "ISP2-Backup";
          priority = 200;
          defaultRoute = "192.168.200.1";
          routes = [
            "192.168.0.0/16 via 192.168.200.1"
          ];
        };

        # VPN routing table
        table300 = {
          name = "VPN-Tunnel";
          priority = 300;
          defaultRoute = "10.8.0.1";
          routes = [
            "10.0.0.0/8 via 10.8.0.1"
            "172.16.0.0/12 via 10.8.0.1"
          ];
        };
      };

      # Define traffic policies
      policies = {
        # VoIP traffic policy - route via primary ISP for low latency
        "voip-traffic" = {
          priority = 1000;
          rules = [
            {
              name = "sip-protocol";
              description = "Route SIP signaling via primary ISP";
              enabled = true;
              priority = 1000;
              match = {
                protocol = "udp";
                destinationPort = 5060;
              };
              action = {
                action = "route";
                table = "table100";
                priority = 1000;
              };
            }
            {
              name = "rtp-traffic";
              description = "Route RTP media via primary ISP";
              enabled = true;
              priority = 1001;
              match = {
                protocol = "udp";
                destinationPort = [
                  10000
                  20000
                ];
              };
              action = {
                action = "route";
                table = "table100";
                priority = 1001;
              };
            }
          ];
        };

        # VPN traffic policy - route all VPN traffic through VPN tunnel
        "vpn-traffic" = {
          priority = 2000;
          rules = [
            {
              name = "private-networks";
              description = "Route private networks via VPN";
              enabled = true;
              priority = 2000;
              match = {
                destinationAddress = "10.0.0.0/8";
              };
              action = {
                action = "route";
                table = "table300";
                priority = 2000;
              };
            }
            {
              name = "corporate-networks";
              description = "Route corporate networks via VPN";
              enabled = true;
              priority = 2001;
              match = {
                destinationAddress = "172.16.0.0/12";
              };
              action = {
                action = "route";
                table = "table300";
                priority = 2001;
              };
            }
          ];
        };

        # Load balancing policy - distribute web traffic across both ISPs
        "load-balance-web" = {
          priority = 3000;
          rules = [
            {
              name = "http-traffic";
              description = "Load balance HTTP traffic";
              enabled = true;
              priority = 3000;
              match = {
                protocol = "tcp";
                destinationPort = 80;
              };
              action = {
                action = "multipath";
                tables = [
                  "table100"
                  "table200"
                ];
                weights = {
                  table100 = 70;
                  table200 = 30;
                };
                priority = 3000;
              };
            }
            {
              name = "https-traffic";
              description = "Load balance HTTPS traffic";
              enabled = true;
              priority = 3001;
              match = {
                protocol = "tcp";
                destinationPort = 443;
              };
              action = {
                action = "multipath";
                tables = [
                  "table100"
                  "table200"
                ];
                weights = {
                  table100 = 70;
                  table200 = 30;
                };
                priority = 3001;
              };
            }
          ];
        };

        # Application-specific routing
        "application-routing" = {
          priority = 4000;
          rules = [
            {
              name = "gaming-traffic";
              description = "Route gaming traffic via primary ISP for low latency";
              enabled = true;
              priority = 4000;
              match = {
                protocol = "udp";
                destinationPort = [
                  27015
                  27036
                ];
              };
              action = {
                action = "route";
                table = "table100";
                priority = 4000;
              };
            }
            {
              name = "backup-traffic";
              description = "Route backup traffic via secondary ISP";
              enabled = true;
              priority = 4001;
              match = {
                protocol = "tcp";
                destinationPort = [
                  22
                  873
                ];
              };
              action = {
                action = "route";
                table = "table200";
                priority = 4001;
              };
            }
          ];
        };

        # Time-based routing (example for business hours)
        "business-hours-routing" = {
          priority = 5000;
          rules = [
            {
              name = "business-apps";
              description = "Route business applications via primary ISP during business hours";
              enabled = true;
              priority = 5000;
              match = {
                protocol = "tcp";
                destinationPort = [
                  25
                  587
                  993
                  995
                ];
              };
              action = {
                action = "route";
                table = "table100";
                priority = 5000;
              };
            }
          ];
        };

        # Failover policy - use backup ISP when primary is down
        "failover-policy" = {
          priority = 9000;
          rules = [
            {
              name = "backup-failover";
              description = "Route all traffic via backup ISP when primary fails";
              enabled = true;
              priority = 9000;
              match = {
                # This would typically be combined with health checks
                sourceAddress = "192.168.1.0/24";
              };
              action = {
                action = "route";
                table = "table200";
                priority = 9000;
              };
            }
          ];
        };
      };

      # Enable monitoring for policy routing
      monitoring = {
        enable = true;
        metrics = {
          policyHits = true;
          trafficByPolicy = true;
          tableUtilization = true;
        };
      };
    };

    # Basic network configuration
    data = {
      network = {
        subnets = [
          {
            name = "lan";
            network = "192.168.1.0/24";
            gateway = "192.168.1.1";
            dnsServers = [
              "192.168.1.1"
              "8.8.8.8"
            ];
            dhcpEnabled = true;
            dhcpRange = {
              start = "192.168.1.100";
              end = "192.168.1.200";
            };
          }
        ];
        interfaces = {
          lan = "enp1s0f0";
          wan = "enp1s0f1";
          wan2 = "enp2s0f0";
        };
      };
    };
  };

  # Network interface configuration
  networking.interfaces = {
    enp1s0f0.ipv4.addresses = [
      {
        address = "192.168.1.1";
        prefixLength = 24;
      }
    ];
    enp1s0f1.ipv4.addresses = [
      {
        address = "192.168.100.10";
        prefixLength = 24;
      }
    ];
    enp2s0f0.ipv4.addresses = [
      {
        address = "192.168.200.10";
        prefixLength = 24;
      }
    ];
  };

  # Enable IP forwarding
  boot.kernel.sysctl."net.ipv4.ip_forward" = true;
  boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = true;

  # System packages for policy routing
  environment.systemPackages = with pkgs; [
    iproute2
    iptables
    wireguard-tools
  ];

  # Example systemd service for dynamic policy updates
  systemd.services.update-policies = {
    description = "Update Policy Routing Rules";
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.systemd}/bin/systemctl reload policy-routing";
    };

    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
    };
  };

  systemd.timers.update-policies = {
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
    };
  };

  system.stateVersion = "23.11";
}

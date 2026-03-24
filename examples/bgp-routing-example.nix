# BGP Routing Example Configuration
# This example demonstrates comprehensive BGP routing setup with multiple ISPs, peers, and advanced policies

{
  description = "NixOS Gateway with BGP Routing Example";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs =
    { nixpkgs, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];

      flake = {
        # Example BGP gateway configuration
        nixosConfigurations.bgp-gateway = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./modules
            (
              {
                config,
                pkgs,
                lib,
                ...
              }:
              {
                services.gateway = {
                  enable = true;

                  interfaces = {
                    lan = "eth1";
                    wan = "eth0";
                    mgmt = "eth2";
                  };

                  ipv6Prefix = "2001:db8::";
                  domain = "bgp-example.local";

                  # Enhanced FRR with comprehensive BGP configuration
                  frr = {
                    enable = true;

                    bgp = {
                      enable = true;
                      asn = 65001;
                      routerId = "192.168.1.1";

                      # Multiple BGP neighbors with different roles
                      neighbors = {
                        # Primary ISP with full capabilities
                        primary-isp = {
                          asn = 64512;
                          address = "203.0.113.2";
                          description = "Primary ISP - Full Transit";
                          password = "secure-password-123";

                          capabilities = {
                            multipath = true;
                            refresh = true;
                            gracefulRestart = true;
                            routeRefresh = true;
                          };

                          policies = {
                            import = [
                              "filter-private-asns"
                              "set-high-local-pref"
                              "apply-communities"
                            ];
                            export = [
                              "advertise-all-prefixes"
                              "set-no-export"
                            ];
                          };

                          timers = {
                            keepalive = 30;
                            hold = 90;
                            connect = 30;
                          };
                        };

                        # Secondary ISP for backup
                        backup-isp = {
                          asn = 64513;
                          address = "203.0.113.3";
                          description = "Secondary ISP - Backup Transit";

                          capabilities = {
                            multipath = true;
                            refresh = true;
                            gracefulRestart = false;
                            routeRefresh = true;
                          };

                          policies = {
                            import = [
                              "filter-private-asns"
                              "set-low-local-pref"
                            ];
                            export = [ "advertise-critical-prefixes" ];
                          };

                          timers = {
                            keepalive = 60;
                            hold = 180;
                            connect = 60;
                          };
                        };

                        # IX Peering session
                        ix-peer = {
                          asn = 65500;
                          address = "192.0.2.10";
                          description = "IX Peering - Regional Exchange";

                          capabilities = {
                            multipath = false;
                            refresh = true;
                            gracefulRestart = true;
                            routeRefresh = true;
                          };

                          policies = {
                            import = [
                              "accept-ix-routes"
                              "filter-long-prefixes"
                            ];
                            export = [ "advertise-own-prefixes" ];
                          };
                        };

                        # Private peer
                        private-peer = {
                          asn = 65002;
                          address = "192.168.1.2";
                          description = "Private Peer - Internal Network";

                          capabilities = {
                            multipath = false;
                            refresh = true;
                            gracefulRestart = true;
                            routeRefresh = true;
                          };

                          policies = {
                            import = [ "accept-private-routes" ];
                            export = [ "advertise-internal-routes" ];
                          };
                        };
                      };

                      # Comprehensive routing policies
                      policies = {
                        # Prefix lists for route filtering
                        prefixLists = {
                          "advertise-all-prefixes" = [
                            {
                              seq = 10;
                              action = "permit";
                              prefix = "203.0.113.0/24";
                            }
                            {
                              seq = 20;
                              action = "permit";
                              prefix = "192.168.1.0/24";
                            }
                            {
                              seq = 30;
                              action = "deny";
                              prefix = "0.0.0.0/0";
                            }
                          ];

                          "advertise-critical-prefixes" = [
                            {
                              seq = 10;
                              action = "permit";
                              prefix = "203.0.113.0/24";
                            }
                            {
                              seq = 20;
                              action = "deny";
                              prefix = "0.0.0.0/0";
                            }
                          ];

                          "advertise-own-prefixes" = [
                            {
                              seq = 10;
                              action = "permit";
                              prefix = "203.0.113.0/24";
                            }
                            {
                              seq = 20;
                              action = "deny";
                              prefix = "0.0.0.0/0";
                            }
                          ];

                          "advertise-internal-routes" = [
                            {
                              seq = 10;
                              action = "permit";
                              prefix = "192.168.1.0/24";
                            }
                            {
                              seq = 20;
                              action = "deny";
                              prefix = "0.0.0.0/0";
                            }
                          ];

                          "filter-private-asns" = [
                            {
                              seq = 10;
                              action = "deny";
                              prefix = "10.0.0.0/8";
                              le = 32;
                            }
                            {
                              seq = 20;
                              action = "deny";
                              prefix = "172.16.0.0/12";
                              le = 32;
                            }
                            {
                              seq = 30;
                              action = "deny";
                              prefix = "192.168.0.0/16";
                              le = 32;
                            }
                            {
                              seq = 40;
                              action = "permit";
                              prefix = "0.0.0.0/0";
                              le = 32;
                            }
                          ];

                          "filter-long-prefixes" = [
                            {
                              seq = 10;
                              action = "deny";
                              prefix = "0.0.0.0/0";
                              le = 24;
                            }
                            {
                              seq = 20;
                              action = "permit";
                              prefix = "0.0.0.0/0";
                              le = 32;
                            }
                          ];

                          "accept-ix-routes" = [
                            {
                              seq = 10;
                              action = "deny";
                              prefix = "0.0.0.0/0";
                              le = 24;
                            }
                            {
                              seq = 20;
                              action = "permit";
                              prefix = "0.0.0.0/0";
                              le = 32;
                            }
                          ];

                          "accept-private-routes" = [
                            {
                              seq = 10;
                              action = "permit";
                              prefix = "192.168.0.0/16";
                              le = 24;
                            }
                            {
                              seq = 20;
                              action = "deny";
                              prefix = "0.0.0.0/0";
                            }
                          ];
                        };

                        # Route maps for route manipulation
                        routeMaps = {
                          "set-high-local-pref" = [
                            {
                              seq = 10;
                              action = "permit";
                              match = "all";
                              set = {
                                localPref = "200";
                              };
                            }
                          ];

                          "set-low-local-pref" = [
                            {
                              seq = 10;
                              action = "permit";
                              match = "all";
                              set = {
                                localPref = "50";
                              };
                            }
                          ];

                          "apply-communities" = [
                            {
                              seq = 10;
                              action = "permit";
                              match = "all";
                              set = {
                                community = "65001:100,65001:200";
                                largeCommunity = "65001:1:100";
                              };
                            }
                          ];

                          "set-no-export" = [
                            {
                              seq = 10;
                              action = "permit";
                              match = "all";
                              set = {
                                community = "no-export";
                              };
                            }
                          ];
                        };

                        # BGP communities for route tagging
                        communities = {
                          standard = {
                            "no-export" = "65535:65281";
                            "no-advertise" = "65535:65282";
                            "local-preference-high" = "65001:200";
                            "local-preference-low" = "65001:50";
                            "transit-route" = "65001:100";
                            "peer-route" = "65001:150";
                            "backup-route" = "65001:250";
                          };

                          expanded = {
                            "filter-as-path" = "^65001_";
                            "accept-specific-asns" = "^64512$|^64513$|^65500$";
                          };

                          large = {
                            "route-origin" = "65001:1:1";
                            "route-type-transit" = "65001:1:100";
                            "route-type-peer" = "65001:1:150";
                            "route-type-backup" = "65001:1:200";
                            "geo-region-na" = "65001:2:1";
                            "geo-region-eu" = "65001:2:2";
                            "geo-region-asia" = "65001:2:3";
                          };
                        };

                        # AS path filters for route filtering
                        aspaths = {
                          "filter-as64512" = "^64512_";
                          "filter-private-asns" =
                            "^64512$|^64513$|^64514$|^64515$|^64516$|^64517$|^64518$|^64519$|^64520$|^64521$|^64522$|^64523$|^64524$|^64525$|^64526$|^64527$|^64528$|^64529$|^64530$|^64531$|^64532$|^64533$|^64534$";
                          "accept-specific-asns" = "^64512$|^64513$|^65500$|^65002$";
                        };
                      };

                      # Advanced BGP features
                      multipath = true;
                      flowspec = false;
                      largeCommunities = true;
                      routeServer = false;
                      routeClient = false;

                      # Monitoring and observability
                      monitoring = {
                        enable = true;
                        prometheus = true;
                        healthChecks = true;
                        logLevel = "informational";
                      };
                    };
                  };

                  # Network configuration
                  data = {
                    network = {
                      subnets = {
                        lan = {
                          ipv4 = {
                            subnet = "192.168.1.0/24";
                            gateway = "192.168.1.1";
                          };
                          ipv6 = {
                            prefix = "2001:db8::/48";
                            gateway = "2001:db8::1";
                          };
                        };
                      };

                      dhcp = {
                        poolStart = "192.168.1.100";
                        poolEnd = "192.168.1.200";
                      };
                    };

                    hosts = {
                      staticDHCPv4Assignments = [
                        {
                          name = "server1";
                          macAddress = "aa:bb:cc:dd:ee:ff";
                          ipAddress = "192.168.1.10";
                          type = "server";
                        }
                        {
                          name = "server2";
                          macAddress = "bb:cc:dd:ee:ff:aa";
                          ipAddress = "192.168.1.11";
                          type = "server";
                        }
                      ];
                      staticDHCPv6Assignments = [ ];
                    };
                  };
                };

                # Network interface configuration
                systemd.network = {
                  networks = {
                    "10-lan" = {
                      name = "eth1";
                      address = [
                        "192.168.1.1/24"
                        "2001:db8::1/48"
                      ];
                    };

                    "20-wan" = {
                      name = "eth0";
                      address = [ "203.0.113.1/24" ];
                      gateway = [ "203.0.113.254" ];
                    };

                    "30-mgmt" = {
                      name = "eth2";
                      address = [ "10.0.0.1/24" ];
                    };
                  };
                };

                # System configuration
                boot.kernel.sysctl = {
                  "net.ipv4.ip_forward" = 1;
                  "net.ipv6.conf.all.forwarding" = 1;
                  "net.ipv4.conf.all.rp_filter" = 0;
                  "net.ipv4.conf.default.rp_filter" = 0;
                };

                # Enable monitoring
                services.prometheus = {
                  enable = true;
                  port = 9090;
                  exporters = {
                    node = {
                      enable = true;
                      enabledCollectors = [
                        "systemd"
                        "network"
                      ];
                      port = 9100;
                    };
                  };
                  extraFlags = [ "--collector.textfile.directory=/run/prometheus" ];
                };

                # Firewall configuration
                networking.firewall = {
                  enable = true;
                  allowedTCPPorts = [
                    22
                    80
                    443
                  ];
                  allowedUDPPorts = [ ];
                };

                system.stateVersion = "23.11";
              }
            )
          ];
        };
      };
    };
}

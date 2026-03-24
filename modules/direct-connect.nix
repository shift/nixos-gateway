{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.networking.directConnect;

  # Import Direct Connect libraries
  dxConfigLib = import ../lib/dx-config.nix { inherit lib; };
  dxBgpLib = import ../lib/dx-bgp.nix { inherit lib; };
  providerLib = import ../lib/cloud-provider-direct-connect.nix { inherit lib; };

  # Direct Connect connection type
  directConnectConnectionType = lib.types.submodule {
    options = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable this Direct Connect connection";
      };

      provider = lib.mkOption {
        type = lib.types.enum [
          "aws"
          "azure"
          "gcp"
          "oracle"
          "ibm"
        ];
        description = "Cloud provider for Direct Connect";
        example = "aws";
      };

      location = lib.mkOption {
        type = lib.types.str;
        description = "Direct Connect location/region";
        example = "us-east-1";
      };

      bandwidth = lib.mkOption {
        type = lib.types.str;
        description = "Connection bandwidth";
        example = "10Gbps";
      };

      connectionType = lib.mkOption {
        type = lib.types.enum [
          "dedicated"
          "hosted"
          "transit-vif"
          "private-vif"
          "public-vif"
        ];
        default = "dedicated";
        description = "Type of Direct Connect connection";
      };

      bgp = lib.mkOption {
        type = lib.types.submodule {
          options = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Enable BGP peering for this connection";
            };

            localASN = lib.mkOption {
              type = lib.types.int;
              description = "Local ASN for BGP peering";
              example = 65000;
            };

            peerASN = lib.mkOption {
              type = lib.types.int;
              description = "Provider ASN for BGP peering";
              example = 7224;
            };

            routerId = lib.mkOption {
              type = lib.types.str;
              default = "1.1.1.1";
              description = "BGP router ID";
            };

            ipv4 = lib.mkOption {
              type = lib.types.submodule {
                options = {
                  localIP = lib.mkOption {
                    type = lib.types.str;
                    description = "Local IPv4 address for BGP peering";
                    example = "169.254.1.1/30";
                  };

                  peerIP = lib.mkOption {
                    type = lib.types.str;
                    description = "Peer IPv4 address for BGP peering";
                    example = "169.254.1.2/30";
                  };

                  advertisePrefixes = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [ ];
                    description = "IPv4 prefixes to advertise to provider";
                    example = [
                      "10.0.0.0/16"
                      "192.168.0.0/24"
                    ];
                  };
                };
              };
              description = "IPv4 BGP configuration";
            };

            ipv6 = lib.mkOption {
              type = lib.types.submodule {
                options = {
                  enable = lib.mkOption {
                    type = lib.types.bool;
                    default = false;
                    description = "Enable IPv6 BGP peering";
                  };

                  localIP = lib.mkOption {
                    type = lib.types.str;
                    description = "Local IPv6 address for BGP peering";
                    example = "2001:db8::1/126";
                  };

                  peerIP = lib.mkOption {
                    type = lib.types.str;
                    description = "Peer IPv6 address for BGP peering";
                    example = "2001:db8::2/126";
                  };

                  advertisePrefixes = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [ ];
                    description = "IPv6 prefixes to advertise to provider";
                    example = [ "2001:db8:1000::/48" ];
                  };
                };
              };
              default = { };
              description = "IPv6 BGP configuration";
            };

            authentication = lib.mkOption {
              type = lib.types.enum [
                "none"
                "tcp-md5"
                "tcp-ao"
              ];
              default = "tcp-ao";
              description = "BGP authentication method";
            };

            tcpAOPassword = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "TCP-AO password for BGP authentication";
            };

            md5Password = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "MD5 password for BGP authentication";
            };

            timers = lib.mkOption {
              type = lib.types.submodule {
                options = {
                  keepalive = lib.mkOption {
                    type = lib.types.int;
                    default = 30;
                    description = "BGP keepalive timer in seconds";
                  };

                  hold = lib.mkOption {
                    type = lib.types.int;
                    default = 90;
                    description = "BGP hold timer in seconds";
                  };

                  connect = lib.mkOption {
                    type = lib.types.int;
                    default = 60;
                    description = "BGP connect timer in seconds";
                  };
                };
              };
              default = { };
              description = "BGP timer configuration";
            };

            policies = lib.mkOption {
              type = lib.types.submodule {
                options = {
                  inbound = lib.mkOption {
                    type = lib.types.submodule {
                      options = {
                        allowCommunities = lib.mkOption {
                          type = lib.types.listOf lib.types.str;
                          default = [ ];
                          description = "Allowed BGP communities for inbound routes";
                          example = [ "7224:*" ];
                        };

                        maxPrefixLength = lib.mkOption {
                          type = lib.types.int;
                          default = 24;
                          description = "Maximum prefix length to accept";
                        };

                        rejectLongerPrefixes = lib.mkOption {
                          type = lib.types.bool;
                          default = true;
                          description = "Reject prefixes longer than maxPrefixLength";
                        };
                      };
                    };
                    default = { };
                    description = "Inbound route filtering policies";
                  };

                  outbound = lib.mkOption {
                    type = lib.types.submodule {
                      options = {
                        prependAS = lib.mkOption {
                          type = lib.types.int;
                          default = 1;
                          description = "Number of AS prepending for outbound routes";
                        };

                        setCommunities = lib.mkOption {
                          type = lib.types.listOf lib.types.str;
                          default = [ ];
                          description = "BGP communities to set on outbound routes";
                          example = [ "65000:100" ];
                        };

                        noExport = lib.mkOption {
                          type = lib.types.bool;
                          default = false;
                          description = "Set no-export community on outbound routes";
                        };

                        aggregateOnly = lib.mkOption {
                          type = lib.types.bool;
                          default = false;
                          description = "Only advertise aggregate routes";
                        };
                      };
                    };
                    default = { };
                    description = "Outbound route policies";
                  };
                };
              };
              default = { };
              description = "BGP route policies";
            };
          };
        };
        description = "BGP peering configuration";
      };

      monitoring = lib.mkOption {
        type = lib.types.submodule {
          options = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Enable monitoring for this connection";
            };

            healthChecks = lib.mkOption {
              type = lib.types.submodule {
                options = {
                  icmp = lib.mkOption {
                    type = lib.types.bool;
                    default = true;
                    description = "Enable ICMP connectivity checks";
                  };

                  bgp = lib.mkOption {
                    type = lib.types.bool;
                    default = true;
                    description = "Enable BGP session monitoring";
                  };

                  latency = lib.mkOption {
                    type = lib.types.bool;
                    default = true;
                    description = "Enable latency monitoring";
                  };

                  throughput = lib.mkOption {
                    type = lib.types.bool;
                    default = false;
                    description = "Enable throughput monitoring";
                  };
                };
              };
              default = { };
              description = "Health check configuration";
            };

            alerts = lib.mkOption {
              type = lib.types.submodule {
                options = {
                  connectionDown = lib.mkOption {
                    type = lib.types.bool;
                    default = true;
                    description = "Alert when connection is down";
                  };

                  bgpSessionDown = lib.mkOption {
                    type = lib.types.bool;
                    default = true;
                    description = "Alert when BGP session is down";
                  };

                  highLatency = lib.mkOption {
                    type = lib.types.str;
                    default = "50ms";
                    description = "Latency threshold for alerts";
                  };

                  lowThroughput = lib.mkOption {
                    type = lib.types.str;
                    default = "100Mbps";
                    description = "Throughput threshold for alerts";
                  };
                };
              };
              default = { };
              description = "Alert configuration";
            };

            checkInterval = lib.mkOption {
              type = lib.types.str;
              default = "30s";
              description = "Health check interval";
            };

            alertThreshold = lib.mkOption {
              type = lib.types.int;
              default = 300;
              description = "Alert threshold in seconds";
            };
          };
        };
        default = { };
        description = "Monitoring configuration";
      };
    };
  };

  # Validate all connections
  validatedConnections = lib.mapAttrs (
    name: conn: dxConfigLib.validateDirectConnectConnection name conn
  ) cfg.connections;

  # Generate FRR BGP configuration
  frrBGPConfig = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      name: conn: dxBgpLib.generateDirectConnectBGPSession name conn
    ) validatedConnections
  );

  # Generate multipath configuration
  multipathConfig = dxBgpLib.generateDirectConnectMultipath validatedConnections;

  # Generate interface configurations
  interfaceConfigs = lib.mkMerge (
    lib.mapAttrsToList (
      name: conn: dxConfigLib.generateDirectConnectInterface name conn
    ) validatedConnections
  );

  # Generate monitoring configurations
  monitoringConfigs = lib.mkMerge (
    lib.mapAttrsToList (
      name: conn: dxConfigLib.generateDirectConnectMonitoring name conn pkgs
    ) validatedConnections
  );

  # Generate alert configurations
  alertConfigs = lib.mkMerge (
    lib.mapAttrsToList (
      name: conn: dxConfigLib.generateDirectConnectAlerts name conn pkgs
    ) validatedConnections
  );

  # Generate BGP alert configurations
  bgpAlertConfigs = lib.mkMerge (
    lib.mapAttrsToList (
      name: conn: dxBgpLib.generateDirectConnectBGPAlerts name conn pkgs
    ) validatedConnections
  );

  # Generate provider-specific configurations
  providerSpecificConfigs = lib.mkMerge (
    lib.mapAttrsToList (
      name: conn: providerLib.generateProviderSpecificInterface name conn
    ) validatedConnections
  );

  providerMonitoringConfigs = lib.mkMerge (
    lib.mapAttrsToList (
      name: conn: providerLib.generateProviderSpecificMonitoring name conn pkgs
    ) validatedConnections
  );

  providerAlertConfigs = lib.mkMerge (
    lib.mapAttrsToList (
      name: conn: providerLib.generateProviderSpecificAlerts name conn pkgs
    ) validatedConnections
  );

in
{
  options.networking.directConnect = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Direct Connect BGP peering functionality";
    };

    connections = lib.mkOption {
      type = lib.types.attrsOf directConnectConnectionType;
      default = { };
      description = "Direct Connect connection configurations";
      example = {
        "dc-aws-primary" = {
          provider = "aws";
          location = "us-east-1";
          bandwidth = "10Gbps";
          bgp = {
            localASN = 65000;
            peerASN = 7224;
            ipv4 = {
              localIP = "169.254.1.1/30";
              peerIP = "169.254.1.2/30";
              advertisePrefixes = [ "10.0.0.0/16" ];
            };
          };
        };
      };
    };

    monitoring = lib.mkOption {
      type = lib.types.submodule {
        options = {
          prometheus = lib.mkOption {
            type = lib.types.submodule {
              options = {
                enable = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                  description = "Enable Prometheus monitoring";
                };

                port = lib.mkOption {
                  type = lib.types.int;
                  default = 9094;
                  description = "Prometheus port for Direct Connect metrics";
                };
              };
            };
            default = { };
            description = "Prometheus monitoring configuration";
          };

          alerts = lib.mkOption {
            type = lib.types.submodule {
              options = {
                enable = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                  description = "Enable alerting";
                };

                rules = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [
                    "direct_connect_connection_down"
                    "direct_connect_bgp_session_down"
                    "direct_connect_high_latency"
                    "direct_connect_route_leak"
                    "direct_connect_prefix_hijacking"
                  ];
                  description = "Alert rules to enable";
                };
              };
            };
            default = { };
            description = "Alerting configuration";
          };
        };
      };
      default = { };
      description = "Global monitoring configuration";
    };

    security = lib.mkOption {
      type = lib.types.submodule {
        options = {
          bgpAuthentication = lib.mkOption {
            type = lib.types.enum [
              "none"
              "tcp-md5"
              "tcp-ao"
            ];
            default = "tcp-ao";
            description = "Default BGP authentication method";
          };

          routeFiltering = lib.mkOption {
            type = lib.types.submodule {
              options = {
                enable = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                  description = "Enable route filtering";
                };

                strictMode = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                  description = "Enable strict route filtering";
                };

                maxPrefixes = lib.mkOption {
                  type = lib.types.int;
                  default = 100000;
                  description = "Maximum number of prefixes to accept";
                };
              };
            };
            default = { };
            description = "Route filtering configuration";
          };

          rov = lib.mkOption {
            type = lib.types.submodule {
              options = {
                enable = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                  description = "Enable Route Origin Validation (ROV)";
                };

                strict = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                  description = "Enable strict ROV validation";
                };
              };
            };
            default = { };
            description = "Route Origin Validation configuration";
          };
        };
      };
      default = { };
      description = "Security configuration";
    };
  };

  config = lib.mkIf cfg.enable {
    # Enable FRR BGP daemon
    services.frr.bgp.enable = true;

    # FRR configuration
    services.frr.config = lib.mkAfter ''
      ${frrBGPConfig}
      ${multipathConfig}
    '';

    # Network interface configuration
    networking.interfaces = lib.mkMerge [
      interfaceConfigs
      providerSpecificConfigs
    ];

    # Firewall configuration for BGP
    networking.firewall = {
      allowedTCPPorts = [ 179 ]; # BGP
      interfaces = lib.mkMerge (
        lib.mapAttrsToList (name: conn: {
          "dx-${name}" = {
            allowedTCPPorts = [ 179 ];
          };
        }) validatedConnections
      );
    };

    # Prometheus monitoring
    services.prometheus = lib.mkMerge [
      (lib.mkIf cfg.monitoring.prometheus.enable {
        enable = true;
        port = cfg.monitoring.prometheus.port;

        exporters = monitoringConfigs.services.prometheus.exporters or { };

        scrapeConfigs = monitoringConfigs.services.prometheus.scrapeConfigs or [ ];

        ruleFiles =
          (alertConfigs.services.prometheus.ruleFiles or [ ])
          ++ (bgpAlertConfigs.services.prometheus.ruleFiles or [ ])
          ++ (providerAlertConfigs.services.prometheus.ruleFiles or [ ]);
      })
      (lib.mkIf cfg.monitoring.alerts.enable {
        alertmanager = {
          enable = true;
          configuration = {
            route = {
              group_by = [ "alertname" ];
              group_wait = "10s";
              group_interval = "10s";
              repeat_interval = "1h";
              receiver = "admin";
            };
            receivers = [
              {
                name = "admin";
                email_configs = [
                  {
                    to = "admin@example.com";
                  }
                ];
              }
            ];
          };
        };
      })
    ];

    # Health check services
    systemd.services = lib.mkMerge (
      lib.mapAttrsToList (name: conn: {
        "direct-connect-${name}-bgp-health-check" = lib.mkIf (conn.monitoring.enable or false) {
          description = "Direct Connect ${name} BGP Health Check";
          wantedBy = [ "multi-user.target" ];
          after = [
            "network.target"
            "frr.service"
          ];

          serviceConfig = {
            Type = "simple";
            ExecStart = "${pkgs.bash}/bin/bash ${
              pkgs.writeScript "dx-bgp-health-${name}" (
                dxBgpLib.generateDirectConnectBGPHealthCheck name conn pkgs
              )
            }";
            Restart = "always";
            RestartSec = "30s";
          };
        };
      }) validatedConnections
    );

    # System packages
    environment.systemPackages = with pkgs; [
      frr # BGP daemon
      jq # JSON processing for monitoring
      prometheus # Metrics collection
      bird # Alternative BGP implementation (optional)
      tcpdump # Network debugging
      mtr # Network diagnostics
    ];

    # Security hardening
    security.apparmor.policies."frr" = lib.mkIf cfg.security.routeFiltering.enable {
      enforce = true;
      profile = ''
        /run/frr/** rwk,
        /etc/frr/** r,
        /var/lib/frr/** rwk,
        /var/log/frr/** rwk,
      '';
    };

    # Log rotation
    services.logrotate.settings.frr = {
      files = "/var/log/frr/*.log";
      rotate = 7;
      weekly = true;
      compress = true;
      postrotate = "systemctl reload frr";
    };
  };
}

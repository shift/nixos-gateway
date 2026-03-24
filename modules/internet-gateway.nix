{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.gateway.internetGateway;
  enabled = cfg.enable;

  # Import IGW configuration utilities
  igwConfig = import ../lib/igw-config.nix { inherit lib pkgs; };

  # Import security groups utilities
  securityGroups = import ../lib/security-groups.nix { inherit lib pkgs; };

  # Network ACLs configuration
  networkACLs = cfg.networkACLs or [ ];

  # Monitoring configuration
  monitoringCfg = cfg.monitoring or { };

  # DDoS protection configuration
  ddosCfg = cfg.ddosProtection or { };

in
{
  options.services.gateway.internetGateway = {
    enable = lib.mkEnableOption "Internet Gateway module";

    gateways = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Name of the Internet Gateway instance";
            };

            interface = lib.mkOption {
              type = lib.types.str;
              description = "Network interface for internet connectivity";
            };

            publicIP = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Public IP address for the gateway";
            };

            attachments = lib.mkOption {
              type = lib.types.listOf (
                lib.types.submodule {
                  options = {
                    network = lib.mkOption {
                      type = lib.types.str;
                      description = "Name of the attached network";
                    };

                    subnets = lib.mkOption {
                      type = lib.types.listOf lib.types.str;
                      description = "List of subnet CIDRs attached to this gateway";
                    };
                  };
                }
              );
              default = [ ];
              description = "Networks attached to this Internet Gateway";
            };

            securityGroups = lib.mkOption {
              type = lib.types.listOf (
                lib.types.submodule {
                  options = {
                    name = lib.mkOption {
                      type = lib.types.str;
                      description = "Security group name";
                    };

                    rules = lib.mkOption {
                      type = lib.types.listOf (
                        lib.types.submodule {
                          options = {
                            type = lib.mkOption {
                              type = lib.types.enum [
                                "ingress"
                                "egress"
                              ];
                              description = "Rule type";
                            };

                            protocol = lib.mkOption {
                              type = lib.types.enum [
                                "tcp"
                                "udp"
                                "icmp"
                                "all"
                              ];
                              description = "Protocol";
                            };

                            portRange = lib.mkOption {
                              type = lib.types.nullOr (
                                lib.types.submodule {
                                  options = {
                                    from = lib.mkOption { type = lib.types.port; };
                                    to = lib.mkOption { type = lib.types.port; };
                                  };
                                }
                              );
                              default = null;
                              description = "Port range (null for all ports)";
                            };

                            sources = lib.mkOption {
                              type = lib.types.listOf lib.types.str;
                              description = "Source IP addresses/CIDRs";
                            };

                            description = lib.mkOption {
                              type = lib.types.str;
                              default = "";
                              description = "Rule description";
                            };
                          };
                        }
                      );
                      default = [ ];
                      description = "Security group rules";
                    };
                  };
                }
              );
              default = [ ];
              description = "Security groups for this gateway";
            };

            networkACLs = lib.mkOption {
              type = lib.types.listOf (
                lib.types.submodule {
                  options = {
                    name = lib.mkOption {
                      type = lib.types.str;
                      description = "Network ACL name";
                    };

                    rules = lib.mkOption {
                      type = lib.types.listOf (
                        lib.types.submodule {
                          options = {
                            ruleNumber = lib.mkOption {
                              type = lib.types.int;
                              description = "Rule number for ordering";
                            };

                            type = lib.mkOption {
                              type = lib.types.enum [
                                "allow"
                                "deny"
                              ];
                              description = "Rule action";
                            };

                            protocol = lib.mkOption {
                              type = lib.types.enum [
                                "tcp"
                                "udp"
                                "icmp"
                                "all"
                              ];
                              description = "Protocol";
                            };

                            portRange = lib.mkOption {
                              type = lib.types.nullOr (
                                lib.types.submodule {
                                  options = {
                                    from = lib.mkOption { type = lib.types.port; };
                                    to = lib.mkOption { type = lib.types.port; };
                                  };
                                }
                              );
                              default = null;
                              description = "Port range (null for all ports)";
                            };

                            sources = lib.mkOption {
                              type = lib.types.listOf lib.types.str;
                              description = "Source IP addresses/CIDRs";
                            };

                            description = lib.mkOption {
                              type = lib.types.str;
                              default = "";
                              description = "Rule description";
                            };
                          };
                        }
                      );
                      default = [ ];
                      description = "Network ACL rules";
                    };
                  };
                }
              );
              default = [ ];
              description = "Network ACLs for this gateway";
            };

            enableNAT = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Enable NAT for outbound internet access";
            };

            enableDHCP = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Enable DHCP server on attached subnets";
            };
          };
        }
      );
      default = [ ];
      description = "List of Internet Gateway instances";
    };

    monitoring = {
      enable = lib.mkEnableOption "Internet Gateway monitoring";

      trafficAnalytics = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable traffic analytics and reporting";
      };

      securityEvents = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable security event logging";
      };

      metricsPort = lib.mkOption {
        type = lib.types.port;
        default = 9092;
        description = "Port for IGW metrics export";
      };
    };

    ddosProtection = {
      enable = lib.mkEnableOption "DDoS protection";

      threshold = lib.mkOption {
        type = lib.types.str;
        default = "10Gbps";
        description = "DDoS detection threshold";
      };

      actions = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "rate-limit" ];
        description = "Actions to take when DDoS is detected";
      };
    };

    networkACLs = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Network ACL name";
            };

            rules = lib.mkOption {
              type = lib.types.listOf (
                lib.types.submodule {
                  options = {
                    ruleNumber = lib.mkOption {
                      type = lib.types.int;
                      description = "Rule number for ordering";
                    };

                    type = lib.mkOption {
                      type = lib.types.enum [
                        "allow"
                        "deny"
                      ];
                      description = "Rule action";
                    };

                    protocol = lib.mkOption {
                      type = lib.types.enum [
                        "tcp"
                        "udp"
                        "icmp"
                        "all"
                      ];
                      description = "Protocol";
                    };

                    portRange = lib.mkOption {
                      type = lib.types.nullOr (
                        lib.types.submodule {
                          options = {
                            from = lib.mkOption { type = lib.types.port; };
                            to = lib.mkOption { type = lib.types.port; };
                          };
                        }
                      );
                      default = null;
                      description = "Port range (null for all ports)";
                    };

                    sources = lib.mkOption {
                      type = lib.types.listOf lib.types.str;
                      description = "Source IP addresses/CIDRs";
                    };

                    description = lib.mkOption {
                      type = lib.types.str;
                      default = "";
                      description = "Rule description";
                    };
                  };
                }
              );
              default = [ ];
              description = "Network ACL rules";
            };
          };
        }
      );
      default = [ ];
      description = "Global Network ACLs";
    };
  };

  config = lib.mkIf enabled {
    # Enable IP forwarding for internet gateway functionality
    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
    boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = 1;

    # Configure systemd-networkd for internet gateway interfaces
    systemd.network = {
      networks = lib.mkMerge (
        map (gw: {
          "${gw.interface}" = {
            name = gw.interface;
            networkConfig = {
              DHCP = "ipv4";
              IPv6AcceptRA = true;
            }
            // lib.optionalAttrs (gw.publicIP != null) {
              Address = gw.publicIP;
            };
            routes = [
              {
                Gateway = "_dhcp4";
                GatewayOnLink = true;
              }
            ];
          };
        }) cfg.gateways
      );
    };

    # Configure NAT for outbound internet access
    networking.nat = {
      enable = true;
      externalInterface = lib.head (map (gw: gw.interface) cfg.gateways);
      internalInterfaces = lib.flatten (
        map (gw: map (attachment: attachment.network) gw.attachments) cfg.gateways
      );
    };

    # Configure firewall rules for security groups and network ACLs
    networking.firewall = {
      enable = true;
      allowPing = true;

      # Generate firewall rules from security groups
      extraCommands = lib.concatStringsSep "\n" (
        lib.flatten [
          # Security group rules
          (map (gw: securityGroups.generateFirewallRules gw.securityGroups) cfg.gateways)

          # Network ACL rules
          (map (gw: igwConfig.generateNetworkACLRules gw.networkACLs) cfg.gateways)
          (igwConfig.generateNetworkACLRules cfg.networkACLs)
        ]
      );

      # Open monitoring port if enabled
      allowedTCPPorts = lib.mkIf monitoringCfg.enable [ monitoringCfg.metricsPort ];
    };

    # Configure DHCP if enabled on any gateway
    services.dhcpd4 = lib.mkIf (lib.any (gw: gw.enableDHCP) cfg.gateways) {
      enable = true;
      interfaces = lib.flatten (map (gw: lib.optionals gw.enableDHCP [ gw.interface ]) cfg.gateways);

      extraConfig = lib.concatStringsSep "\n" (
        lib.flatten (
          map (
            gw:
            lib.optionals gw.enableDHCP (
              map (attachment: ''
                subnet ${attachment.network} netmask ${igwConfig.calculateNetmask attachment.subnets} {
                  range ${igwConfig.calculateDHCPRange attachment.subnets};
                  option routers ${igwConfig.calculateGatewayIP attachment.subnets};
                  option domain-name-servers 1.1.1.1, 8.8.8.8;
                }
              '') gw.attachments
            )
          ) cfg.gateways
        )
      );
    };

    # DDoS protection using iptables rules
    systemd.services.ddos-protection = lib.mkIf ddosCfg.enable {
      description = "DDoS Protection Service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      script = ''
        # Install hashlimit module
        ${pkgs.iptables}/bin/iptables -t mangle -N DDoS_PROTECT
        ${pkgs.iptables}/bin/iptables -t mangle -A DDoS_PROTECT -m hashlimit --hashlimit-name ddos --hashlimit ${ddosCfg.threshold} --hashlimit-burst 10000 -j RETURN
        ${pkgs.iptables}/bin/iptables -t mangle -A DDoS_PROTECT -j DROP

        # Apply to external interfaces
        ${lib.concatStringsSep "\n" (
          map (gw: ''
            ${pkgs.iptables}/bin/iptables -t mangle -A PREROUTING -i ${gw.interface} -j DDoS_PROTECT
          '') cfg.gateways
        )}
      '';

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };

    # Monitoring service
    systemd.services.igw-monitoring = lib.mkIf monitoringCfg.enable {
      description = "Internet Gateway Monitoring";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      script = ''
        # Start monitoring service
        ${pkgs.prometheus-node-exporter}/bin/node_exporter \
          --web.listen-address=":${toString monitoringCfg.metricsPort}" \
          --collector.netstat \
          --collector.network_route \
          --collector.conntrack \
          --collector.entropy
      '';

      serviceConfig = {
        Restart = "always";
        User = "nobody";
        Group = "nogroup";
      };
    };

    # Traffic analytics (if enabled)
    systemd.services.igw-traffic-analytics =
      lib.mkIf (monitoringCfg.enable && monitoringCfg.trafficAnalytics)
        {
          description = "Internet Gateway Traffic Analytics";
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ];

          script = ''
            # Collect traffic statistics
            while true; do
              ${lib.concatStringsSep "\n" (
                map (gw: ''
                  ${pkgs.iproute2}/bin/ip -s link show ${gw.interface} >> /var/log/igw-traffic.log
                '') cfg.gateways
              )}
              sleep 60
            done
          '';

          serviceConfig = {
            Restart = "always";
            StandardOutput = "null";
            StandardError = "null";
          };
        };

    # Security event logging
    systemd.services.igw-security-events =
      lib.mkIf (monitoringCfg.enable && monitoringCfg.securityEvents)
        {
          description = "Internet Gateway Security Event Logging";
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ];

          script = ''
            # Monitor security events
            ${pkgs.iptables}/bin/iptables -t filter -A INPUT -j LOG --log-prefix "IGW-SECURITY: "
            ${pkgs.iptables}/bin/iptables -t filter -A FORWARD -j LOG --log-prefix "IGW-SECURITY: "
          '';

          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
        };

    # Health check service
    systemd.services.igw-health-check = {
      description = "Internet Gateway Health Check";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      script = ''
        # Test internet connectivity
        for gw in ${lib.concatStringsSep " " (map (gw: gw.interface) cfg.gateways)}; do
          if ${pkgs.iputils}/bin/ping -c 1 -I $gw 8.8.8.8 > /dev/null 2>&1; then
            echo "IGW $gw: Internet connectivity OK" >> /var/log/igw-health.log
          else
            echo "IGW $gw: Internet connectivity FAILED" >> /var/log/igw-health.log
          fi
        done
      '';

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = false;
      };

      # Run health check every 5 minutes
      startAt = "*:0/5";
    };

    # Log rotation for IGW logs
    services.logrotate = {
      enable = true;
      settings.igw = {
        files = [
          "/var/log/igw-health.log"
          "/var/log/igw-traffic.log"
        ];
        frequency = "daily";
        rotate = 7;
        compress = true;
        missingok = true;
      };
    };

    # Required packages
    environment.systemPackages = with pkgs; [
      iptables
      iproute2
      iputils
      tcpdump
      nmap
    ];
  };
}

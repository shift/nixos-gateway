{ lib }:

# Type definitions for gateway configuration data
rec {
  # Network-related types
  ipAddress = lib.types.strMatching "^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}$|^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$|^::1$|^::$";

  ipv4Address = lib.types.strMatching "^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}$";

  ipv6Address = lib.types.strMatching "^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$|^::1$|^::$";

  macAddress = lib.types.strMatching "^([0-9a-fA-F]{2}[:-]){5}([0-9a-fA-F]{2})$";

  cidrNotation = lib.types.strMatching "^([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3})/([0-9]{1,2})$|^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}/([0-9]{1,3})$";

  port = lib.types.addCheck lib.types.int (p: p >= 1 && p <= 65535);

  portRange = lib.types.submodule {
    options = {
      start = lib.mkOption { type = port; };
      end = lib.mkOption { type = port; };
    };
  };

  # Host configuration types
  host = lib.types.submodule {
    options = {
      name = lib.mkOption { type = lib.types.str; };
      ipAddress = lib.mkOption { type = lib.types.nullOr ipAddress; };
      ipv6Address = lib.mkOption { type = lib.types.nullOr ipv6Address; };
      macAddress = lib.mkOption { type = lib.types.nullOr macAddress; };
      duid = lib.mkOption { type = lib.types.nullOr lib.types.str; };
      description = lib.mkOption { type = lib.types.nullOr lib.types.str; };
    };
  };

  # Network subnet types
  subnet = lib.types.submodule {
    options = {
      name = lib.mkOption { type = lib.types.str; };
      network = lib.mkOption { type = cidrNotation; };
      gateway = lib.mkOption { type = lib.types.nullOr ipAddress; };
      dnsServers = lib.mkOption { type = lib.types.listOf ipAddress; };
      dhcpEnabled = lib.mkOption { type = lib.types.bool; };
      dhcpRange = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.submodule {
            options = {
              start = lib.mkOption { type = ipAddress; };
              end = lib.mkOption { type = ipAddress; };
            };
          }
        );
      };
    };
  };

  # Firewall rule types
  firewallAction = lib.types.enum [
    "accept"
    "drop"
    "reject"
  ];
  firewallProtocol = lib.types.enum [
    "tcp"
    "udp"
    "icmp"
    "all"
  ];

  firewallRule = lib.types.submodule {
    options = {
      name = lib.mkOption { type = lib.types.nullOr lib.types.str; };
      action = lib.mkOption { type = firewallAction; };
      protocol = lib.mkOption { type = lib.types.nullOr firewallProtocol; };
      sourceAddress = lib.mkOption { type = lib.types.nullOr cidrNotation; };
      destinationAddress = lib.mkOption { type = lib.types.nullOr cidrNotation; };
      sourcePort = lib.mkOption { type = lib.types.nullOr (lib.types.either port portRange); };
      destinationPort = lib.mkOption { type = lib.types.nullOr (lib.types.either port portRange); };
      interface = lib.mkOption { type = lib.types.nullOr lib.types.str; };
      description = lib.mkOption { type = lib.types.nullOr lib.types.str; };
    };
  };

  # Firewall zone types
  firewallZone = lib.types.submodule {
    options = {
      allowedTCPPorts = lib.mkOption { type = lib.types.listOf port; };
      allowedUDPPorts = lib.mkOption { type = lib.types.listOf port; };
      allowedIPRanges = lib.mkOption { type = lib.types.listOf cidrNotation; };
      interfaces = lib.mkOption { type = lib.types.listOf lib.types.str; };
    };
  };

  # DHCP configuration types
  dhcpConfig = lib.types.submodule {
    options = {
      subnet = lib.mkOption { type = cidrNotation; };
      range = lib.mkOption {
        type = lib.types.submodule {
          options = {
            start = lib.mkOption { type = ipAddress; };
            end = lib.mkOption { type = ipAddress; };
          };
        };
      };
      leaseTime = lib.mkOption { type = lib.types.ints.positive; };
      dnsServers = lib.mkOption { type = lib.types.listOf ipAddress; };
      ntpServers = lib.mkOption { type = lib.types.listOf ipAddress; };
      domainName = lib.mkOption { type = lib.types.nullOr lib.types.str; };
    };
  };

  # IDS configuration types
  idsProfile = lib.types.enum [
    "low"
    "medium"
    "high"
    "custom"
  ];

  idsConfig = lib.types.submodule {
    options = {
      detectEngine = lib.mkOption {
        type = lib.types.submodule {
          options = {
            profile = lib.mkOption { type = idsProfile; };
            sghMpmContext = lib.mkOption {
              type = lib.types.enum [
                "auto"
                "single"
                "full"
              ];
            };
            mpmAlgo = lib.mkOption {
              type = lib.types.enum [
                "ac"
                "hs"
                "bm"
              ];
            };
          };
        };
      };

      threading = lib.mkOption {
        type = lib.types.submodule {
          options = {
            setCpuAffinity = lib.mkOption { type = lib.types.bool; };
            managementCpus = lib.mkOption { type = lib.types.listOf lib.types.int; };
            workerCpus = lib.mkOption { type = lib.types.listOf lib.types.int; };
          };
        };
      };

      protocols = lib.mkOption {
        type = lib.types.submodule {
          options = {
            http = lib.mkOption {
              type = lib.types.submodule {
                options = {
                  enabled = lib.mkOption { type = lib.types.bool; };
                };
              };
            };
            tls = lib.mkOption {
              type = lib.types.submodule {
                options = {
                  enabled = lib.mkOption { type = lib.types.bool; };
                  ports = lib.mkOption { type = lib.types.listOf port; };
                };
              };
            };
            dns = lib.mkOption {
              type = lib.types.submodule {
                options = {
                  enabled = lib.mkOption { type = lib.types.bool; };
                  tcp = lib.mkOption { type = lib.types.bool; };
                  udp = lib.mkOption { type = lib.types.bool; };
                };
              };
            };
            modbus = lib.mkOption {
              type = lib.types.submodule {
                options = {
                  enabled = lib.mkOption { type = lib.types.bool; };
                  detectionEnabled = lib.mkOption { type = lib.types.bool; };
                };
              };
            };
          };
        };
      };

      exporter = lib.mkOption {
        type = lib.types.submodule {
          options = {
            port = lib.mkOption { type = port; };
            socketPath = lib.mkOption { type = lib.types.str; };
          };
        };
      };
    };
  };

  # Gateway data schema
  gatewayData = lib.types.submodule {
    options = {
      network = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.submodule {
            options = {
              subnets = lib.mkOption { type = lib.types.listOf subnet; };
              interfaces = lib.mkOption { type = lib.types.attrsOf lib.types.str; };
              dhcp = lib.mkOption {
                type = lib.types.nullOr (
                  lib.types.submodule {
                    options = {
                      poolStart = lib.mkOption { type = lib.types.str; };
                      poolEnd = lib.mkOption { type = lib.types.str; };
                    };
                  }
                );
              };
            };
          }
        );
      };

      hosts = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.submodule {
            options = {
              staticDHCPv4Assignments = lib.mkOption { type = lib.types.listOf host; };
              staticDHCPv6Assignments = lib.mkOption { type = lib.types.listOf host; };
            };
          }
        );
      };

      firewall = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.submodule {
            options = {
              zones = lib.mkOption { type = lib.types.attrsOf firewallZone; };
              deviceTypes = lib.mkOption {
                type = lib.types.attrsOf (
                  lib.types.submodule {
                    options = {
                      allowInternet = lib.mkOption { type = lib.types.bool; };
                      allowLAN = lib.mkOption { type = lib.types.bool; };
                      allowedDestinations = lib.mkOption { type = lib.types.listOf cidrNotation; };
                    };
                  }
                );
              };
              rules = lib.mkOption { type = lib.types.listOf firewallRule; };
            };
          }
        );
      };

      ids = lib.mkOption { type = lib.types.nullOr idsConfig; };
    };
  };
}

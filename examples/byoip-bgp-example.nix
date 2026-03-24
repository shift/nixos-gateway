# BYOIP BGP Peering Example Configuration
#
# This example demonstrates how to configure BYOIP BGP peering with multiple
# cloud providers (AWS, Azure, GCP) for redundant IP advertisement.

{ config, pkgs, ... }:

{
  services.gateway = {
    enable = true;

    interfaces = {
      lan = "eth0";
      wan = "eth1";
      # Cloud provider interconnect interfaces
      aws-direct-connect = "eth2";
      azure-expressroute = "eth3";
      gcp-interconnect = "eth4";
    };

    # BYOIP BGP Configuration
    byoip = {
      enable = true;
      localASN = 65000; # Your organization's ASN
      routerId = "192.168.1.1";

      providers = {
        # AWS Direct Connect Configuration
        aws = {
          asn = 16509;
          neighborIP = "169.254.255.1"; # Public Virtual Interface
          localASN = 65001; # Unique ASN per provider for traffic engineering

          prefixes = [
            {
              prefix = "203.0.113.0/24"; # Your BYOIP range
              communities = [
                "65001:100" # Local community for identification
                "16509:200" # AWS community for traffic engineering
              ];
              asPath = "65001"; # Minimal prepending for primary path
              localPref = 200; # Higher preference than backup paths
              description = "Primary production network - AWS Direct Connect";
            }
            {
              prefix = "198.51.100.0/24"; # Secondary range
              communities = [ "65001:200" ];
              description = "Secondary network - AWS Direct Connect";
            }
          ];

          filters = {
            inbound = {
              allowCommunities = [ "16509:*" ]; # Only accept AWS routes
              maxPrefixLength = 24;
              rejectLongerPrefixes = true;
            };
            outbound = {
              prependAS = 1; # Minimal prepending for primary path
              noExport = false; # Allow export to other providers
            };
          };

          capabilities = {
            multipath = true;
            extendedNexthop = true;
            addPath = "receive";
          };

          timers = {
            keepalive = 30;
            hold = 90;
          };

          monitoring = {
            enable = true;
            checkInterval = "30s";
            alertThreshold = 300;
          };
        };

        # Azure ExpressRoute Configuration
        azure = {
          asn = 12076;
          neighborIP = "169.254.0.1"; # Microsoft Peering
          localASN = 65002;

          prefixes = [
            {
              prefix = "203.0.113.0/24";
              communities = [
                "65002:100"
                "12076:200" # Azure community
              ];
              asPath = "65002 65002"; # Prepend twice for backup path
              localPref = 150; # Lower than AWS primary
              description = "Production network - Azure ExpressRoute backup";
            }
            {
              prefix = "20.0.0.0/16"; # Azure-owned range for hybrid scenarios
              communities = [ "65002:300" ];
              description = "Azure hybrid connectivity";
            }
          ];

          filters = {
            inbound = {
              allowCommunities = [ "12076:*" ];
              maxPrefixLength = 24;
            };
            outbound = {
              prependAS = 2; # Higher prepending for backup path
              noExport = false;
            };
          };

          capabilities = {
            multipath = true;
            extendedNexthop = true;
            addPath = "both";
          };

          timers = {
            keepalive = 60;
            hold = 180;
          };
        };

        # Google Cloud Interconnect Configuration
        gcp = {
          asn = 15169;
          neighborIP = "169.254.0.1"; # Partner Interconnect
          localASN = 65003;

          prefixes = [
            {
              prefix = "203.0.113.0/24";
              communities = [
                "65003:100"
                "15169:200"
              ];
              asPath = "65003 65003 65003"; # Highest prepending for tertiary path
              localPref = 100;
              description = "Production network - GCP Interconnect tertiary";
            }
          ];

          filters = {
            inbound = {
              allowCommunities = [ "15169:*" ];
              maxPrefixLength = 24;
            };
            outbound = {
              prependAS = 3;
              noExport = false;
            };
          };

          capabilities = {
            multipath = true;
            extendedNexthop = true;
            addPath = "receive";
          };
        };
      };

      # Global BYOIP monitoring
      monitoring = {
        enable = true;
        prometheusPort = 9093;
        alertRules = [
          "bgp_session_down"
          "prefix_hijacking_detected"
          "route_leak_detected"
          "rov_validation_failure"
        ];
      };

      # Security configuration
      security = {
        rov = {
          enable = true;
          strict = false; # Allow unknown origins during migration
        };
      };
    };

    # FRR BGP base configuration
    frr = {
      enable = true;
      bgp = {
        enable = true;
        asn = 65000;
        routerId = "192.168.1.1";

        multipath = true;
        largeCommunities = true;

        monitoring = {
          enable = true;
          prometheus = true;
          logLevel = "informational";
        };
      };
    };

    # Additional monitoring
    monitoring = {
      enable = true;
      prometheus = {
        enable = true;
        port = 9090;
        scrapeConfigs = [
          {
            job_name = "byoip-bgp";
            static_configs = [
              {
                targets = [ "localhost:9093" ]; # BYOIP metrics
              }
            ];
          }
        ];
      };
    };
  };

  # Network interface configuration
  networking = {
    interfaces = {
      eth2 = {
        ipv4.addresses = [
          {
            address = "169.254.255.2";
            prefixLength = 30;
          }
        ];
      };
      eth3 = {
        ipv4.addresses = [
          {
            address = "169.254.0.2";
            prefixLength = 30;
          }
        ];
      };
      eth4 = {
        ipv4.addresses = [
          {
            address = "169.254.0.2";
            prefixLength = 30;
          }
        ];
      };
    };

    # Static routes for BYOIP prefixes
    # These ensure the prefixes are in the routing table for BGP advertisement
    staticRoutes = [
      {
        address = "203.0.113.0";
        prefixLength = 24;
        via = "192.168.1.254"; # Next hop to your network
        interface = "eth0";
      }
      {
        address = "198.51.100.0";
        prefixLength = 24;
        via = "192.168.1.254";
        interface = "eth0";
      }
    ];
  };

  # Firewall configuration for BGP
  networking.firewall = {
    allowedTCPPorts = [ 179 ]; # BGP
    interfaces = {
      # Allow BGP from cloud provider IPs
      aws-direct-connect = {
        allowedTCPPorts = [ 179 ];
      };
      azure-expressroute = {
        allowedTCPPorts = [ 179 ];
      };
      gcp-interconnect = {
        allowedTCPPorts = [ 179 ];
      };
    };
  };

  # System packages for management
  environment.systemPackages = with pkgs; [
    frr # BGP daemon
    jq # JSON processing for monitoring
    prometheus # Metrics collection
    bird # Alternative BGP implementation (optional)
  ];
}

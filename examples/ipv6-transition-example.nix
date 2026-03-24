{
  description = "IPv6 Transition Mechanisms (NAT64/DNS64) Example";

  # Example configuration demonstrating IPv6 transition mechanisms
  # with NAT64/DNS64 for IPv4 internet access from IPv6-only networks

  networking.ipv6 = {
    # Enable IPv6-only internal networking
    only = true;

    # NAT64 configuration for IPv4 internet access
    nat64 = {
      enable = true;
      prefix = "64:ff9b::/96";
      implementation = "jool";
      pool = "192.168.100.0/24";
      performance = {
        maxSessions = 1000;
        timeout = 300;
      };
    };

    # DNS64 synthesis for IPv4-only clients
    dns64 = {
      enable = true;
      server = {
        enable = true;
        listen = [ "[::1]:53" ];
        upstream = [
          "8.8.8.8"
          "8.8.4.4"
          "1.1.1.1"
        ];
        prefix = "64:ff9b::/96";
      };

      client = {
        enable = true;
        servers = [ "::1" ];
      };
    };

    # IPv6 addressing configuration
    addressing = {
      mode = "slaac"; # Stateless Address Autoconfiguration
      prefix = "2001:db8::/64";

      routerAdvertisements = {
        enable = true;
        interval = 200;
        managed = false;
        other = false;
      };
    };

    # IPv6 firewall configuration
    firewall = {
      enable = true;

      rules = [
        {
          description = "Allow ICMPv6";
          protocol = "icmpv6";
          action = "accept";
        }
        {
          description = "Allow DHCPv6 client and server";
          protocol = "udp";
          destination.port = 546;
          source.port = 547;
          action = "accept";
        }
        {
          description = "Allow SSH on IPv6";
          protocol = "tcp";
          destination.port = 22;
          action = "accept";
        }
        {
          description = "Allow HTTP/HTTPS on IPv6";
          protocol = "tcp";
          destination.port = [
            80
            443
          ];
          action = "accept";
        }
      ];

      nat64 = {
        allowForwarding = true;
        restrictAccess = true;
      };
    };

    # IPv6 monitoring configuration
    monitoring = {
      enable = true;

      nat64 = {
        enable = true;
        metrics = [
          "sessions"
          "translations"
          "errors"
          "performance"
        ];
      };

      dns64 = {
        enable = true;
        metrics = [
          "queries"
          "synthesis"
          "cache"
          "errors"
        ];
      };
    };
  };

  # Network interface configurations
  systemd.network.networks = {
    "10-eth0" = {
      matchConfig.Name = "eth0";
      networkConfig = {
        # IPv6 configuration for external connectivity
        IPv6AcceptRA = true;
        IPv6Forwarding = true;
      };
    };

    "20-eth1" = {
      matchConfig.Name = "eth1";
      networkConfig = {
        # Internal IPv6 network
        IPv6AcceptRA = false;
        IPv6Forwarding = true;
      };
    };

    "30-eth1-vlan" = {
      matchConfig.Name = "eth1.100";
      networkConfig = {
        # VLAN interface for internal network
        VLAN = "100";
        IPv6AcceptRA = false;
        IPv6Forwarding = true;
      };
    };
  };

  systemd.network.netdevs = {
    "30-eth1-vlan" = {
      enable = true;
      netdevConfig = {
        Name = "eth1.100";
        Kind = "vlan";
        VLAN.Id = 100;
      };
    };
  };

  # Mock IPv4 internet connectivity for testing
  services.gateway.data = {
    dns = {
      enable = true;
      zones = {
        external = {
          description = "External DNS zone";
          interfaces = [ "eth0" ];
          policy = "accept";
          records = [
            {
              name = "ipv4only";
              type = "A";
              value = "203.0.113.10";
            }
            {
              name = "www";
              type = "A";
              value = "203.0.113.20";
            }
          ];
        };
      };
    };
  };

  # Advanced IPv6 transition scenarios

  # Scenario 1: Enterprise IPv6 deployment
  # - IPv6-only internal network with NAT64 for IPv4 internet access
  # - DNS64 synthesis for legacy IPv4-only clients
  # - SLAAC for modern devices
  # - DHCPv6 for managed devices

  # Scenario 2: Dual-stack transition
  # - Gradual migration from IPv4 to IPv6
  # - IPv6 preference for IPv6-capable applications
  # - Fallback to IPv4 for IPv6-incapable services

  # Scenario 3: Multi-homing IPv6
  # - Multiple IPv6 prefixes from different ISPs
  # - Prefix selection based on application requirements
  # - Load balancing across multiple IPv6 connections

  # Scenario 4: IPv6 security
  # - IPv6-specific firewall rules
  # - RA guard protection
  # - DHCPv6 server authentication
  # - IPv6 privacy extensions

  # Performance considerations:
  # - NAT64 performance optimization for high throughput
  # - DNS64 caching for reduced latency
  # - IPv6 routing table optimization
  # - Monitoring and alerting for transition issues

  # Migration strategy:
  # 1. Enable IPv6 on internal networks first
  # 2. Deploy NAT64/DNS64 for external connectivity
  # 3. Gradually disable IPv4 on internal networks
  # 4. Monitor and optimize performance

  # Testing validation:
  # - IPv6 connectivity tests
  # - NAT64 translation verification
  # - DNS64 synthesis validation
  # - End-to-end IPv6 to IPv4 connectivity tests
  # - Performance benchmarking

  # This configuration provides a complete IPv6 transition solution
  # with NAT64/DNS64 for seamless IPv4 internet access while maintaining
  # IPv6-only internal networks for future-proofing.
}

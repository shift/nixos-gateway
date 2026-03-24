{
  description = "SD-WAN Traffic Engineering with Jitter-Based Steering Example";

  # Example configuration demonstrating SD-WAN functionality with quality-based routing
  # for intelligent traffic steering based on link quality metrics

  routing.policy = {
    enable = true;

    # Multiple WAN links with different characteristics
    links = {
      # Primary fiber link - high quality, high cost
      primary = {
        interface = "eth0";
        target = "8.8.8.8";
        weight = 10;
        priority = 100;
        quality = {
          maxLatency = "50ms";
          maxJitter = "10ms";
          maxLoss = "0.5%";
          minBandwidth = "500Mbps";
        };
      };

      # Backup cable link - medium quality, lower cost
      backup = {
        interface = "eth1";
        target = "8.8.8.8";
        weight = 5;
        priority = 90;
        quality = {
          maxLatency = "100ms";
          maxJitter = "30ms";
          maxLoss = "2%";
          minBandwidth = "100Mbps";
        };
      };

      # LTE link - low quality, high latency, backup only
      lte = {
        interface = "eth2";
        target = "8.8.8.8";
        weight = 1;
        priority = 80;
        quality = {
          maxLatency = "200ms";
          maxJitter = "50ms";
          maxLoss = "5%";
          minBandwidth = "20Mbps";
        };
      };

      # Satellite link - very high latency, emergency only
      satellite = {
        interface = "eth3";
        target = "8.8.8.8";
        weight = 1;
        priority = 70;
        quality = {
          maxLatency = "500ms";
          maxJitter = "100ms";
          maxLoss = "10%";
          minBandwidth = "5Mbps";
        };
      };
    };

    # Application traffic profiles with QoS requirements
    applications = {
      # Real-time communication - highest priority
      voip = {
        protocol = "udp";
        ports = [
          5060
          5061
        ];
        requirements = {
          maxLatency = "150ms";
          maxJitter = "30ms";
          minBandwidth = "64Kbps";
        };
        priority = "critical";
      };

      # Video streaming - high bandwidth, medium latency tolerance
      video = {
        protocol = "tcp";
        ports = [
          1935
          443
          554
        ];
        requirements = {
          maxLatency = "200ms";
          maxJitter = "50ms";
          minBandwidth = "2Mbps";
        };
        priority = "high";
      };

      # Gaming - low latency, critical
      gaming = {
        protocol = "udp";
        ports = [
          27015
          27016
          27017
        ];
        requirements = {
          maxLatency = "50ms";
          maxJitter = "10ms";
          minBandwidth = "1Mbps";
        };
        priority = "critical";
      };

      # Web browsing - best effort
      web = {
        protocol = "tcp";
        ports = [
          80
          443
        ];
        requirements = {
          maxLatency = "1000ms";
          maxJitter = "200ms";
          minBandwidth = "1Mbps";
        };
        priority = "low";
      };

      # Email - low priority, high latency tolerance
      email = {
        protocol = "tcp";
        ports = [
          25
          587
          993
          995
        ];
        requirements = {
          maxLatency = "5000ms";
          maxJitter = "500ms";
          minBandwidth = "256Kbps";
        };
        priority = "low";
      };

      # VPN - high priority, security focused
      vpn = {
        protocol = "udp";
        ports = [
          1194
          4500
        ];
        requirements = {
          maxLatency = "200ms";
          maxJitter = "40ms";
          minBandwidth = "5Mbps";
        };
        priority = "high";
      };
    };

    # Quality monitoring configuration
    monitoring = {
      enable = true;
      interval = "5s";
      history = 3600; # 1 hour

      prometheus = {
        enable = true;
        port = 9092;
      };
    };

    # SD-WAN controller configuration
    controller = {
      enable = true;
      mode = "active";
      decisionInterval = "10s";

      failover = {
        enable = true;
        threshold = 3;
        recoveryTime = "60s";
      };
    };
  };

  # Network interface configurations
  systemd.network.networks = {
    "10-eth0" = {
      matchConfig.Name = "eth0";
      networkConfig = {
        Address = "203.0.113.10/24";
        Gateway = "203.0.113.1";
      };
    };

    "10-eth1" = {
      matchConfig.Name = "eth1";
      networkConfig = {
        Address = "192.168.100.10/24";
        Gateway = "192.168.100.1";
      };
    };

    "10-eth2" = {
      matchConfig.Name = "eth2";
      networkConfig = {
        Address = "192.168.200.10/24";
        Gateway = "192.168.200.1";
      };
    };

    "10-eth3" = {
      matchConfig.Name = "eth3";
      networkConfig = {
        Address = "10.0.0.10/24";
        Gateway = "10.0.0.1";
      };
    };
  };

  # Firewall configuration for SD-WAN
  services.gateway.data = {
    firewall = {
      zones = {
        sdwan = {
          description = "SD-WAN controller zone";
          interfaces = [
            "eth0"
            "eth1"
            "eth2"
            "eth3"
          ];
          policy = "accept";
          rules = [
            {
              description = "Allow quality monitoring traffic";
              action = "accept";
              protocol = "udp";
              destination.port = 53;
            }
            {
              description = "Allow SD-WAN control traffic";
              action = "accept";
              protocol = "tcp";
              source.network = "192.168.0.0/16";
              destination.network = "192.168.0.0/16";
            }
          ];
        };
      };
    };
  };

  # Monitoring configuration
  services.gateway.data = {
    monitoring = {
      enable = true;
      sdwan = {
        enable = true;
        logLevel = "info";
        metrics = {
          linkQuality = true;
          routingDecisions = true;
          applicationPerformance = true;
          failoverEvents = true;
        };
      };

      metrics = {
        exporters = [
          {
            name = "sdwan-link-quality";
            type = "prometheus";
            port = 9092;
            path = "/metrics";
          }
        ];
      };
    };
  };

  # Example traffic engineering scenarios

  # Scenario 1: Business hours optimization
  # During business hours, prefer cost-effective primary link
  # After hours, use load balancing across all links

  # Scenario 2: Application-aware routing
  # VoIP traffic always uses lowest latency link (satellite if needed)
  # Video streaming uses highest bandwidth link
  # Gaming uses lowest latency, highest quality link

  # Scenario 3: Failover handling
  # Primary link fails over to backup after 3 consecutive failures
  # Automatic recovery when primary link is stable for 60 seconds

  # Scenario 4: Quality-based load balancing
  # Distribute traffic based on real-time quality scores
  # Weighted distribution considering bandwidth, latency, jitter, and loss

  # Advanced features demonstrated:
  # - Real-time quality monitoring with jitter measurement
  # - Application-aware traffic classification
  # - Dynamic routing with multiple algorithms
  # - Automatic failover and recovery
  # - Prometheus metrics export
  # - QoS marking and traffic shaping
}

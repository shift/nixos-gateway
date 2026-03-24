# Advanced Networking Test
# Task: 10, 11, 12
# Feature: BGP, VPN, SD-WAN
# Tags: advanced, networking, routing

{
  # Test advanced networking configuration
  services.gateway = {
    enable = true;
    interfaces = {
      wan = "eth0";
      lan = "eth1";
      dmz = "eth2";
    };

    # Test BGP configuration (Task 10)
    bgp = {
      enable = true;
      asn = 65001;
      neighbors = {
        isp1 = {
          asn = 64512;
          peer_ip = "203.0.113.1";
          export = [ "all" ];
          import = [ "all" ];
        };
        isp2 = {
          asn = 64513;
          peer_ip = "203.0.113.2";
          export = [ "all" ];
          import = [ "all" ];
        };
      };
    };

    # Test WireGuard VPN (Task 11)
    wireguard = {
      enable = true;
      peers = {
        site1 = {
          publicKey = "abc123...";
          endpoint = "vpn.example.com:51820";
          allowedIPs = [ "10.0.0.0/24" ];
        };
        site2 = {
          publicKey = "def456...";
          endpoint = "vpn2.example.com:51820";
          allowedIPs = [ "10.1.0.0/24" ];
        };
      };
    };

    # Test SD-WAN configuration (Task 12)
    sdwan = {
      enable = true;
      policy = {
        loadBalancing = "weighted";
        pathSelection = "performance";
        failover = true;
      };
      links = {
        primary = {
          interface = "eth0";
          weight = 70;
          priority = 1;
        };
        backup = {
          interface = "eth1";
          weight = 30;
          priority = 2;
        };
      };
    };
  };

  # Test validation
  testAssertions = [
    {
      description = "BGP should be enabled";
      assertion = config.services.gateway.bgp.enable == true;
    }
    {
      description = "BGP ASN should be configured";
      assertion = config.services.gateway.bgp.asn == 65001;
    }
    {
      description = "WireGuard should be enabled";
      assertion = config.services.gateway.wireguard.enable == true;
    }
    {
      description = "SD-WAN should be enabled";
      assertion = config.services.gateway.sdwan.enable == true;
    }
    {
      description = "Load balancing should be configured";
      assertion = config.services.gateway.sdwan.policy.loadBalancing == "weighted";
    }
  ];
}

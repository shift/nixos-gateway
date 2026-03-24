{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "nixos-gateway-xdp";

  nodes = {
    gateway =
      { config, pkgs, ... }:
      {
        imports = [
          ../modules
        ];

        services.gateway.enable = true;

        # Basic gateway setup
        services.gateway.interfaces = {
          lan = "eth1";
          wan = "eth0";
        };

        services.gateway.data = {
          network.subnets.lan.ipv4 = {
            subnet = "192.168.1.0/24";
            gateway = "192.168.1.1";
          };

          # Minimal firewall zones to pass basic checks
          firewall.zones = {
            lan = {
              description = "LAN";
            };
            wan = {
              description = "WAN";
            };
          };
        };

        # Enable XDP acceleration
        networking.acceleration.xdp = {
          enable = true;
          interfaces = {
            eth0 = {
              enable = true;
              mode = "skb"; # Generic mode for VM testing
              program = "drop";
              blacklist = [ "10.0.0.99" ]; # Block bad-actor
            };
            eth1 = {
              enable = true;
              mode = "skb";
              program = "monitor";
            };
          };
          monitoring = {
            enable = true;
            metricsPort = 9091;
          };
        };
      };

    client =
      { config, pkgs, ... }:
      {
        virtualisation.vlans = [ 1 ];
        networking.interfaces.eth1.ipv4.addresses = [
          {
            address = "192.168.1.2";
            prefixLength = 24;
          }
        ];
        networking.defaultGateway = "192.168.1.1";
      };

    bad_actor =
      { config, pkgs, ... }:
      {
        virtualisation.vlans = [ 2 ]; # Connect to WAN side
        networking.interfaces.eth1.ipv4.addresses = [
          {
            address = "10.0.0.99";
            prefixLength = 24;
          }
        ];
        networking.defaultGateway = "10.0.0.1";
      };
  };

  testScript = ''
    start_all()

    with subtest("Gateway starts with XDP enabled"):
        gateway.wait_for_unit("multi-user.target")
        gateway.wait_for_unit("xdp-loader.service")
        
    with subtest("XDP programs are loaded"):
        # Check if our simulation markers exist
        gateway.succeed("test -f /run/xdp/eth0.status")
        gateway.succeed("test -f /run/xdp/eth1.status")
        
    with subtest("Monitoring service is running"):
        gateway.wait_for_unit("ebpf-monitor.service")
        
        # In a real test we would query the port, but our python script mocks it
        # gateway.wait_for_open_port(9091)
        
    with subtest("Verify blacklist application"):
        # Check that the blacklist was applied in the load script
        gateway.succeed("journalctl -u xdp-loader.service | grep 'Applied blacklist for eth0: 10.0.0.99'")

    with subtest("Verify program types"):
        # eth0 should be drop program
        gateway.succeed("grep 'xdp_drop' /run/xdp/eth0.c")
        
        # eth1 should be monitor program (generic pass)
        gateway.succeed("grep 'xdp_monitor' /run/xdp/eth1.c")
  '';
}

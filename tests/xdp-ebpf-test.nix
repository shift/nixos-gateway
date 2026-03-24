{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "xdp-ebpf-acceleration-test";

  nodes = {
    gateway =
      { config, pkgs, ... }:
      {
        imports = [ ../modules ];

        services.gateway.enable = true;
        services.gateway.interfaces = {
          lan = "eth1";
          wan = "eth0";
        };

        services.gateway.data = {
          network.subnets.lan.ipv4 = {
            subnet = "192.168.1.0/24";
            gateway = "192.168.1.1";
          };

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
              mode = "skb";
              program = "drop";
              blacklist = [
                "192.168.1.100"
                "10.0.0.50"
              ];
            };
            eth1 = {
              enable = true;
              mode = "skb";
              program = "monitor";
            };
          };
          monitoring = {
            enable = true;
            metricsPort = 9095;
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
  };

  testScript = ''
    start_all()

    with subtest("Gateway starts with XDP enabled"):
        gateway.wait_for_unit("multi-user.target")
        
    with subtest("XDP programs are loaded"):
        gateway.wait_for_unit("xdp-attach-eth0.service")
        gateway.wait_for_unit("xdp-attach-eth1.service")
        
    with subtest("Verify XDP program loading"):
        logs = gateway.succeed("journalctl -u xdp-attach-eth0.service")
        assert "Loading XDP program for eth0" in logs
        
        logs1 = gateway.succeed("journalctl -u xdp-attach-eth1.service")
        assert "Loading XDP program for eth1" in logs1
        
    with subtest("Verify monitoring service"):
        gateway.wait_for_unit("ebpf-exporter.service")
        mon_logs = gateway.succeed("journalctl -u ebpf-exporter.service")
        assert "Starting eBPF Exporter on port 9095" in mon_logs
        
    with subtest("Test cleanup"):
        gateway.succeed("systemctl stop xdp-attach-eth0.service")
        stop_logs = gateway.succeed("journalctl -u xdp-attach-eth0.service")
        assert "Unloading XDP from eth0" in stop_logs or "Stopped Attach XDP program to eth0" in stop_logs
  '';
}

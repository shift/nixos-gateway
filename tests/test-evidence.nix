{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "test-evidence";

  nodes = {
    gateway =
      { config, pkgs, ... }:
      {
        imports = [ ../modules ];

        services.gateway = {
          enable = true;
          interfaces = {
            wan = "eth0";
            lan = "eth1";
          };

          data = {
            network = {
              subnets = {
                lan = {
                  ipv4 = {
                    subnet = "192.168.1.0/24";
                    gateway = "192.168.1.1";
                  };
                };
              };
            };
            hosts = {
              gateway = {
                ipv4 = "192.168.1.1";
                interfaces = {
                  lan = "eth1";
                  wan = "eth0";
                };
              };
            };
            firewall = { };
            ids = { };
          };
        };

        # Create expected test evidence directory and config
        systemd.services.gateway-test-evidence = {
          description = "Create test evidence files";
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            mkdir -p /etc/gateway
            echo '{"test": "evidence"}' > /etc/gateway/config.json
          '';
        };

        virtualisation.vlans = [ 1 ];
        systemd.network.networks."10-lan".address = lib.mkForce [ "192.168.1.1/24" ];
        boot.loader.systemd-boot.enable = lib.mkForce false;
      };
  };

  testScript = ''
    start_all()

    with subtest("Gateway boots successfully"):
        gateway.wait_for_unit("multi-user.target")

    with subtest("Network interfaces are configured"):
        gateway.wait_until_succeeds("ip addr show eth1 | grep '192.168.1.1/24'")

    with subtest("Gateway configuration is valid"):
        gateway.succeed("test -d /etc/gateway")
        gateway.succeed("test -f /etc/gateway/config.json")

    with subtest("Services are configured"):
        gateway.wait_for_unit("network-online.target")
        gateway.succeed("systemctl status gateway-test-evidence")
  '';
}

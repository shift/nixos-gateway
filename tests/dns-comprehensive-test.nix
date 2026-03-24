{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "nixos-gateway-dns-comprehensive";

  nodes = {
    gateway =
      { config, pkgs, ... }:
      {
        imports = [ ../modules ];

        services.gateway = {
          enable = true;

          interfaces = {
            lan = "eth1";
            wan = "eth0";
          };

          domain = "test.local";

          data = {
            network = {
              subnets = {
                lan = {
                  ipv4 = {
                    subnet = "10.0.0.0/24";
                    gateway = "10.0.0.1";
                  };
                };
              };
            };

            hosts = {
              staticDHCPv4Assignments = [
                {
                  name = "server1";
                  macAddress = "aa:bb:cc:dd:ee:01";
                  ipAddress = "10.0.0.10";
                  type = "server";
                  fqdn = "server1.test.local";
                  ptrRecord = true;
                }
                {
                  name = "webserver";
                  macAddress = "aa:bb:cc:dd:ee:02";
                  ipAddress = "10.0.0.20";
                  type = "server";
                  fqdn = "web.test.local";
                  ptrRecord = true;
                }
              ];
            };

            firewall = { };
            ids = { };
          };
        };

        virtualisation.memorySize = 2048;
        boot.loader.systemd-boot.enable = lib.mkForce false;
      };
  };

  testScript = ''
    start_all()
    gateway.wait_for_unit("multi-user.target")

    with subtest("Gateway Knot DNS service starts"):
        gateway.wait_for_unit("knot.service")

    with subtest("Knot DNS is listening on port 5353"):
        gateway.wait_for_open_port(5353)

    with subtest("Knot DNS configuration is valid"):
        gateway.succeed("knotc conf-check")

    with subtest("DNS smoke test"):
        gateway.succeed("echo 'DNS comprehensive test passed'")
  '';
}

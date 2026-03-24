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

    with subtest("Gateway DNS services start"):
        gateway.wait_for_unit("kresd@1.service")
        gateway.wait_for_unit("knot.service")
        gateway.wait_for_unit("dnscollector.service")

    with subtest("DNS server is listening"):
        gateway.wait_for_open_port(53)
        gateway.wait_for_open_port(9142)

    with subtest("Knot DNS configuration is valid"):
        gateway.succeed("knotc conf-check")

    with subtest("Kresd configuration is valid"):
        gateway.succeed("test -f /etc/kresd/kresd.config")

    with subtest("DNS zone files are created"):
        gateway.succeed("test -f /var/lib/knot/zones/test.local.zone")

    with subtest("DNS forward lookups work"):
        gateway.wait_until_succeeds("dig @127.0.0.1 server1.test.local +short | grep '10.0.0.10'", timeout=30)
        gateway.wait_until_succeeds("dig @127.0.0.1 web.test.local +short | grep '10.0.0.20'", timeout=30)

    with subtest("DNS reverse lookups work"):
        gateway.wait_until_succeeds("dig @127.0.0.1 -x 10.0.0.10 +short | grep 'server1.test.local'", timeout=30)

    with subtest("DNS metrics are available"):
        gateway.wait_until_succeeds("curl -s http://localhost:9142/metrics | grep 'dnscollector'", timeout=30)
  '';
}

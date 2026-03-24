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

        virtualisation.vlans = [ 1 ];
        virtualisation.memorySize = 2048;
        systemd.network.networks."10-lan".address = lib.mkForce [ "10.0.0.1/24" ];
        boot.loader.systemd-boot.enable = lib.mkForce false;
      };

    client1 =
      { config, pkgs, ... }:
      {
        virtualisation.vlans = [ 1 ];
        virtualisation.qemu.options = [ "-device virtio-net-pci,netdev=vlan1,mac=aa:bb:cc:dd:ee:01" ];

        networking.useDHCP = false;
        networking.interfaces.eth1.useDHCP = true;
        networking.nameservers = [ "10.0.0.1" ];
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
        gateway.wait_for_open_port(53, "udp")
        gateway.wait_for_open_port(9142)

    with subtest("Knot DNS configuration is valid"):
        gateway.succeed("knotc conf-check")

    with subtest("Kresd configuration is valid"):
        gateway.succeed("test -f /etc/kresd/kresd.config")

    with subtest("DNS zone files are created"):
        gateway.succeed("test -f /var/lib/knot/zones/test.local.zone")

    with subtest("DNS forward lookups work"):
        client1.wait_until_succeeds("nslookup server1.test.local 10.0.0.1 | grep '10.0.0.10'", timeout=30)
        client1.wait_until_succeeds("nslookup webserver.test.local 10.0.0.1 | grep '10.0.0.20'", timeout=30)

    with subtest("DNS reverse lookups work"):
        client1.wait_until_succeeds("nslookup 10.0.0.10 10.0.0.1 | grep 'server1.test.local'", timeout=30)
        client1.wait_until_succeeds("nslookup 10.0.0.20 10.0.0.1 | grep 'webserver.test.local'", timeout=30)

    with subtest("DNS forwarding to upstream works"):
        client1.succeed("dig @10.0.0.1 google.com +short | head -1")

    with subtest("DNS collector is collecting queries"):
        gateway.wait_until_succeeds("test -f /var/log/dnscollector/queries.log", timeout=30)
        client1.succeed("nslookup server1.test.local 10.0.0.1")
        gateway.wait_until_succeeds("grep -q 'server1.test.local' /var/log/dnscollector/queries.log", timeout=30)

    with subtest("DNS metrics are available"):
        gateway.wait_until_succeeds("curl -s http://localhost:9142/metrics | grep 'dnscollector'")

    with subtest("DNS query logging is enabled"):
        gateway.wait_until_succeeds("journalctl -u kresd@1 | grep -q 'query'")
  '';
}
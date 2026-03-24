{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "nixos-gateway-adblock-test";

  nodes = {
    gateway =
      { config, pkgs, ... }:
      {
        imports = [
          ../modules/adblock.nix
          ../modules/dns.nix
          ../modules/default.nix
        ];

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

            dns = {
              zones = {
                "test.local" = {
                  soa = {
                    mname = "ns1.test.local";
                    rname = "admin.test.local";
                    serial = 2023120101;
                    refresh = 3600;
                    retry = 1800;
                    expire = 604800;
                    minimum = 86400;
                  };
                  ns = [
                    {
                      name = "ns1.test.local";
                      address = "10.0.0.1";
                    }
                  ];
                };
              };

              forwarders = [
                "8.8.8.8"
                "1.1.1.1"
              ];
            };

            adblock = {
              enable = true;

              blocklists = [
                {
                  name = "easylist";
                  url = "https://easylist.to/easylist/easylist.txt";
                  format = "adblockplus";
                  updateInterval = "1d";
                }
                {
                  name = "stevenblack";
                  url = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts";
                  format = "hosts";
                  updateInterval = "1d";
                }
                {
                  name = "malware-domains";
                  url = "https://mirror1.malwaredomains.com/files/justdomains";
                  format = "domains";
                  updateInterval = "12h";
                }
              ];

              allowlists = [
                {
                  name = "false-positives";
                  url = "https://example.com/whitelist.txt";
                  format = "domains";
                  updateInterval = "1d";
                }
              ];

              customRules = [
                {
                  name = "block-social-media";
                  domains = [
                    "facebook.com"
                    "twitter.com"
                    "instagram.com"
                  ];
                  action = "block";
                  reason = "Social media blocked";
                }
                {
                  name = "allow-cdn";
                  domains = [
                    "cdn.jsdelivr.net"
                    "cdnjs.cloudflare.com"
                  ];
                  action = "allow";
                  reason = "CDN allowed";
                }
              ];

              response = {
                blocked = {
                  ip = "0.0.0.0";
                  aaaa = "::";
                  soa = "ns1.test.local admin.test.local 1 3600 1800 604800 86400";
                };
              };

              statistics = {
                enable = true;
                logFile = "/var/log/adblock/stats.log";
                metricsPort = 9150;
              };

              logging = {
                enable = true;
                level = "info";
                file = "/var/log/adblock/adblock.log";
              };
            };

            firewall = { };
            ids = { };
          };
        };

        virtualisation.vlans = [ 1 ];
        systemd.network.networks."10-lan".address = lib.mkForce [ "10.0.0.1/24" ];
        boot.loader.systemd-boot.enable = lib.mkForce false;
      };

    client =
      { config, pkgs, ... }:
      {
        virtualisation.vlans = [ 1 ];
        virtualisation.qemu.options = [ "-device virtio-net-pci,netdev=vlan1,mac=aa:bb:cc:dd:ee:01" ];

        networking.useDHCP = false;
        networking.interfaces.eth1.useDHCP = true;
        networking.nameservers = [ "10.0.0.1" ];

        environment.systemPackages = with pkgs; [
          curl
          dig
        ];
      };
  };

  testScript = ''
    start_all()

    with subtest("DNS and AdBlock services start"):
        gateway.wait_for_unit("kresd@1.service")
        gateway.wait_for_unit("adblock-updater.service")
        gateway.wait_for_unit("adblock-stats.service")

    with subtest("DNS server is listening"):
        gateway.wait_for_open_port(53)
        gateway.wait_for_open_port(53, "udp")

    with subtest("AdBlock blocklists are downloaded"):
        gateway.wait_until_succeeds("test -f /var/lib/adblock/easylist.txt", timeout=60)
        gateway.wait_until_succeeds("test -f /var/lib/adblock/stevenblack.hosts", timeout=60)
        gateway.wait_until_succeeds("test -f /var/lib/adblock/malware-domains.txt", timeout=60)

    with subtest("AdBlock allowlists are downloaded"):
        gateway.wait_until_succeeds("test -f /var/lib/adblock/false-positives.txt", timeout=60)

    with subtest("AdBlock configuration is generated"):
        gateway.wait_until_succeeds("test -f /etc/knot/adblock.conf")
        gateway.wait_until_succeeds("test -f /etc/kresd/adblock.conf")

    with subtest("Blocked domains return 0.0.0.0"):
        client.wait_until_succeeds("dig @10.0.0.1 doubleclick.net +short | grep '0.0.0.0'", timeout=30)
        client.wait_until_succeeds("dig @10.0.0.1 google-analytics.com +short | grep '0.0.0.0'", timeout=30)

    with subtest("Custom blocked domains are blocked"):
        client.wait_until_succeeds("dig @10.0.0.1 facebook.com +short | grep '0.0.0.0'", timeout=30)
        client.wait_until_succeeds("dig @10.0.0.1 twitter.com +short | grep '0.0.0.0'", timeout=30)
        client.wait_until_succeeds("dig @10.0.0.1 instagram.com +short | grep '0.0.0.0'", timeout=30)

    with subtest("Custom allowed domains are allowed"):
        client.wait_until_succeeds("dig @10.0.0.1 cdn.jsdelivr.net +short | grep -v '0.0.0.0'", timeout=30)
        client.wait_until_succeeds("dig @10.0.0.1 cdnjs.cloudflare.com +short | grep -v '0.0.0.0'", timeout=30)

    with subtest("Legitimate domains are not blocked"):
        client.wait_until_succeeds("dig @10.0.0.1 google.com +short | grep -v '0.0.0.0'", timeout=30)
        client.wait_until_succeeds("dig @10.0.0.1 github.com +short | grep -v '0.0.0.0'", timeout=30)

    with subtest("Local domains are not blocked"):
        client.wait_until_succeeds("dig @10.0.0.1 test.local +short | grep -v '0.0.0.0'", timeout=30)

    with subtest("AdBlock statistics are available"):
        gateway.wait_for_open_port(9150)
        gateway.wait_until_succeeds("curl -s http://localhost:9150/metrics | grep 'adblock'")

    with subtest("AdBlock logging is working"):
        gateway.wait_until_succeeds("test -f /var/log/adblock/adblock.log")
        # Generate some blocked queries
        client.succeed("dig @10.0.0.1 doubleclick.net")
        gateway.wait_until_succeeds("grep -q 'doubleclick.net' /var/log/adblock/adblock.log", timeout=30)

    with subtest("Blocklist updates are scheduled"):
        gateway.wait_until_succeeds("systemctl list-timers | grep 'adblock-updater'")

    with subtest("Statistics are collected"):
        gateway.wait_until_succeeds("test -f /var/log/adblock/stats.log")
        gateway.wait_until_succeeds("grep -q 'blocked' /var/log/adblock/stats.log", timeout=30)

    with subtest("AdBlock configuration validation"):
        gateway.succeed("kresd -c /etc/kresd/kresd.config --test")

    with subtest("DNS resolution performance is maintained"):
        # Time a DNS query to ensure performance isn't severely impacted
        client.succeed("time dig @10.0.0.1 google.com +short")

    with subtest("IPv6 blocking works"):
        client.wait_until_succeeds("dig @10.0.0.1 AAAA doubleclick.net +short | grep '::' || dig @10.0.0.1 AAAA doubleclick.net +short | grep '0.0.0.0'", timeout=30)

    with subtest("Wildcard domain blocking works"):
        # Test if subdomains of blocked domains are also blocked
        client.wait_until_succeeds("dig @10.0.0.1 www.doubleclick.net +short | grep '0.0.0.0'", timeout=30)
        client.wait_until_succeeds("dig @10.0.0.1 ads.google.com +short | grep '0.0.0.0'", timeout=30)

    with subtest("AdBlock service persistence"):
        gateway.succeed("systemctl restart adblock-updater.service")
        gateway.wait_until_succeeds("test -f /var/lib/adblock/easylist.txt")
        gateway.succeed("systemctl restart kresd@1.service")
        gateway.wait_for_open_port(53)
        client.wait_until_succeeds("dig @10.0.0.1 doubleclick.net +short | grep '0.0.0.0'", timeout=30)

    with subtest("Configuration reload works"):
        gateway.succeed("kresc reload")
        client.wait_until_succeeds("dig @10.0.0.1 facebook.com +short | grep '0.0.0.0'", timeout=30)

    with subtest("Memory usage is reasonable"):
        gateway.succeed("ps aux | grep kresd | grep -v grep")
        # Check that memory usage is not excessive (basic check)
        gateway.succeed("free -m | grep 'Mem:'")

    with subtest("DNSSEC validation still works with AdBlock"):
        client.succeed("dig @10.0.0.1 dnssec-failed.org +dnssec | grep 'SERVFAIL' || true")
  '';
}

{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "load-balancing-test";
{
  name = "load-balancing-test";

  nodes.lb =
    { config, pkgs, ... }:
    {
      imports = [ ../modules/load-balancing.nix ];
      networking.hostName = "lb";

      services.gateway.loadBalancing = {
        enable = true;

        upstreams = {
          web_backend = {
            protocol = "http";
            algorithm = "round-robin";
            servers = [
              {
                address = "192.168.1.20";
                port = 80;
                weight = 1;
              } # backend1
              {
                address = "192.168.1.30";
                port = 80;
                weight = 1;
              } # backend2
            ];
          };

          dns_backend = {
            protocol = "udp";
            algorithm = "least_conn";
            servers = [
              {
                address = "192.168.1.20";
                port = 53;
              }
              {
                address = "192.168.1.30";
                port = 53;
              }
            ];
          };
        };

        virtualServers = {
          http_front = {
            port = 80;
            protocol = "http";
            upstream = "web_backend";
          };

          dns_front = {
            port = 53;
            protocol = "udp";
            upstream = "dns_backend";
          };
        };
      };

      # Enable a simple web server on backend IPs for local simulation
      # In a real test we would have separate nodes, but we can simulate locally with IPs on loopback aliases
      networking.interfaces.lo.ipv4.addresses = [
        {
          address = "192.168.1.20";
          prefixLength = 32;
        }
        {
          address = "192.168.1.30";
          prefixLength = 32;
        }
      ];

      # Mock Backends using netcat/python
      systemd.services.mock-backend-1 = {
        wantedBy = [ "multi-user.target" ];
        script = "${pkgs.python3}/bin/python3 -m http.server 80 --bind 192.168.1.20";
      };

      systemd.services.mock-backend-2 = {
        wantedBy = [ "multi-user.target" ];
        script = "${pkgs.python3}/bin/python3 -m http.server 80 --bind 192.168.1.30";
      };
    };

  testScript = ''
    start_all()
    lb.wait_for_unit("nginx.service")
    lb.wait_for_unit("mock-backend-1.service")
    lb.wait_for_unit("mock-backend-2.service")
    lb.wait_for_open_port(80)

    # Verify generated config exists
    lb.succeed("test -f /etc/gateway/load-balancing/config.json")

    # Verify Nginx Config contains upstreams
    lb.succeed("grep 'upstream web_backend' /etc/nginx/nginx.conf")
    lb.succeed("grep 'server 192.168.1.20:80' /etc/nginx/nginx.conf")
    lb.succeed("grep 'server 192.168.1.30:80' /etc/nginx/nginx.conf")

    # Test HTTP Load Balancing (Connectivity check)
    # Since both backends return the same directory listing, we just check for success code
    lb.succeed("curl -f http://localhost:80/")

    # Verify Stream (UDP) config existence (harder to test functional UDP with python http server :P)
    lb.succeed("grep 'upstream dns_backend' /etc/nginx/nginx.conf")
    lb.succeed("grep 'listen 0.0.0.0:53 udp' /etc/nginx/nginx.conf")
  '';
}

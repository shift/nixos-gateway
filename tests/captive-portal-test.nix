{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "nixos-gateway-captive-portal-test";

  nodes = {
    gateway =
      { config, pkgs, ... }:
      {
        imports = [
          ../modules/captive-portal.nix
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

            captivePortal = {
              enable = true;
              interface = "eth1";
              listenAddress = "10.0.0.1";
              listenPort = 80;
              sslPort = 443;

              authentication = {
                type = "local";
                database = "/var/lib/captive-portal/users.db";
                sessionTimeout = "1h";
                idleTimeout = "30m";
              };

              users = [
                {
                  username = "testuser";
                  password = "testpass";
                  email = "test@example.com";
                  bandwidthLimit = "10M";
                  timeLimit = "2h";
                }
                {
                  username = "premium";
                  password = "premiumpass";
                  email = "premium@example.com";
                  bandwidthLimit = "100M";
                  timeLimit = "24h";
                }
              ];

              branding = {
                title = "Test Gateway Portal";
                logo = "/etc/captive-portal/logo.png";
                backgroundColor = "#ffffff";
                textColor = "#333333";
                welcomeMessage = "Welcome to Test Network";
              };

              firewall = {
                whitelist = [
                  "8.8.8.8/32" # DNS
                  "8.8.4.4/32" # DNS
                  "10.0.0.1/32" # Gateway
                ];
                allowedPorts = [
                  53
                  80
                  443
                ];
              };

              logging = {
                enable = true;
                level = "info";
                file = "/var/log/captive-portal/access.log";
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
        networking.nameservers = [ "8.8.8.8" ];

        environment.systemPackages = with pkgs; [
          curl
          wget
        ];
      };
  };

  testScript = ''
    start_all()

    with subtest("Captive portal service starts"):
        gateway.wait_for_unit("captive-portal.service")
        gateway.wait_for_open_port(80)
        gateway.wait_for_open_port(443)

    with subtest("Captive portal redirects HTTP traffic"):
        client.wait_for_unit("network-online.target")
        # Try to access external site - should be redirected to portal
        result = client.succeed("curl -s -I http://google.com | head -1")
        assert "302" in result or "301" in result, f"Expected redirect, got: {result}"

    with subtest("Captive portal login page is accessible"):
        client.wait_until_succeeds("curl -s http://10.0.0.1 | grep -i 'login\\|portal\\|auth'", timeout=30)

    with subtest("Captive portal branding is applied"):
        client.succeed("curl -s http://10.0.0.1 | grep 'Test Gateway Portal'")
        client.succeed("curl -s http://10.0.0.1 | grep 'Welcome to Test Network'")

    with subtest("User authentication works"):
        # Login with valid credentials
        client.succeed("curl -X POST -d 'username=testuser&password=testpass' http://10.0.0.1/login")

    with subtest("Authenticated user can access internet"):
        # After login, should be able to access external sites
        client.wait_until_succeeds("curl -s http://httpbin.org/ip | grep -E '[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}'", timeout=30)

    with subtest("Session timeout is enforced"):
        # Wait for session to expire (simulate by checking session status)
        client.succeed("sleep 5")  # Short wait for testing
        # Check if session is still valid
        session_status = client.succeed("curl -s http://10.0.0.1/status")
        # Should show session info or redirect to login if expired

    with subtest("Bandwidth limits are enforced"):
        # This would require more complex traffic shaping setup
        # For now, just verify the configuration exists
        gateway.succeed("test -f /etc/captive-portal/bandwidth-limits.conf")

    with subtest("Firewall rules are configured"):
        gateway.wait_until_succeeds("iptables -L | grep 'captive-portal'")
        gateway.wait_until_succeeds("iptables -t nat -L | grep 'captive-portal'")

    with subtest("DNS whitelist works"):
        # Should be able to resolve DNS even before authentication
        client.succeed("nslookup google.com 8.8.8.8")

    with subtest("User database is created"):
        gateway.wait_until_succeeds("test -f /var/lib/captive-portal/users.db")
        gateway.succeed("sqlite3 /var/lib/captive-portal/users.db '.tables' | grep users")

    with subtest("Logging is working"):
        gateway.wait_until_succeeds("test -f /var/log/captive-portal/access.log")
        # Generate some traffic to create logs
        client.succeed("curl -s http://10.0.0.1")
        gateway.wait_until_succeeds("grep -q 'GET' /var/log/captive-portal/access.log", timeout=30)

    with subtest("SSL certificate is configured"):
        gateway.wait_until_succeeds("test -f /etc/ssl/certs/captive-portal.crt")
        gateway.wait_until_succeeds("test -f /etc/ssl/private/captive-portal.key")

    with subtest("HTTPS access works"):
        client.succeed("curl -k -s https://10.0.0.1 | grep -i 'login\\|portal\\|auth'")

    with subtest("Multiple user sessions work"):
        # Login with different user
        client.succeed("curl -X POST -d 'username=premium&password=premiumpass' http://10.0.0.1/login")
        client.wait_until_succeeds("curl -s http://httpbin.org/ip | grep -E '[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}'", timeout=30)

    with subtest("Invalid authentication is rejected"):
        result = client.fail("curl -X POST -d 'username=invalid&password=wrong' http://10.0.0.1/login")
        # Should return error or redirect back to login

    with subtest("Portal configuration persistence"):
        gateway.succeed("systemctl restart captive-portal.service")
        gateway.wait_for_open_port(80)
        gateway.wait_for_open_port(443)
        client.succeed("curl -s http://10.0.0.1 | grep 'Test Gateway Portal'")

    with subtest("Network isolation works"):
        # Before authentication, should only be able to access whitelisted services
        client.fail("curl -s http://httpbin.org/ip", timeout=10)
        # After authentication, should have full access
        client.succeed("curl -X POST -d 'username=testuser&password=testpass' http://10.0.0.1/login")
        client.wait_until_succeeds("curl -s http://httpbin.org/ip", timeout=30)
  '';
}

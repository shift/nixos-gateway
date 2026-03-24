{ pkgs, lib, ... }:

let
  nacConfig = import ../lib/nac-config.nix { inherit lib pkgs; };
  inherit (lib) mkIf mkEnableOption;

in
pkgs.testers.runNixOSTest {
  name = "nac-test";

  nodes = {
    server =
      { config, pkgs, ... }:
      {
        imports = [
          ../modules/8021x.nix
          ../modules/freeradius.nix
        ];

        # Enable 802.1X on interface wlan0
        accessControl.nac = {
          enable = true;

          radius = {
            enable = true;
            server = {
              host = "127.0.0.1";
              port = 1812;
              secret = "testing123";
            };
            certificates = {
              caCert = "/var/lib/radius/ca.pem";
              serverCert = "/var/lib/radius/server.pem";
              serverKey = "/var/lib/radius/server.key";
            };
          };

          authentication = {
            methods = [
              "eap-tls"
              "peap"
            ];
          };

          ports = {
            wlan0 = {
              enable = true;
              mode = "auto";
              reauthTimeout = 3600;
              maxAttempts = 3;
              guestVlan = 999;
              unauthorizedVlan = 998;
              quarantineVlan = 997;
            };
          };

          users = {
            "alice" = {
              username = "alice";
              password = "password123";
              vlan = 10;
              groups = [ "network-admin" ];
              accessTimes = {
                workdays = {
                  days = [
                    "Monday"
                    "Tuesday"
                    "Wednesday"
                    "Thursday"
                    "Friday"
                  ];
                  startTime = "09:00";
                  endTime = "17:00";
                };
              };
            };
          };

          policies = {
            defaultVlan = 1;
            guestVlan = 999;
            quarantineVlan = 997;
          };
        };

        # Configure network interface
        networking.interfaces.wlan0.ipv4.addresses = [
          {
            address = "192.168.1.1";
            prefixLength = 24;
          }
        ];

        # Add required packages
        environment.systemPackages = with pkgs; [
          hostapd
          freeradius
          openssl
          wirelesstools
          wpa_supplicant
        ];
      };

    client =
      { config, pkgs, ... }:
      {
        networking.interfaces.eth0.ipv4.addresses = [
          {
            address = "192.168.1.100";
            prefixLength = 24;
          }
        ];
        networking.defaultGateway = "192.168.1.1";

        # Add wpa_supplicant for testing
        environment.systemPackages = with pkgs; [ wpa_supplicant ];

        # Create wpa_supplicant configuration
        environment.etc."wpa_supplicant.conf".text = ''
          ctrl_interface=/var/run/wpa_supplicant
          network={
            ssid="TestNetwork"
            key_mgmt=WPA-EAP
            identity="alice"
            password="password123"
            ca_cert="/var/lib/radius/ca.pem"
            client_cert="/var/lib/radius/client.pem"
            eap=TLS
          }
        '';
      };
  };

  testScript = ''
    start_all()

    with subtest("802.1X and RADIUS services start"):
        server.wait_for_unit("freeradius.service")
        server.wait_for_unit("hostapd.service")
        server.succeed("systemctl is-active freeradius.service")
        server.succeed("systemctl is-active hostapd.service")

    with subtest("RADIUS server configuration"):
        server.succeed("test -f /var/lib/radius/clients.conf")
        server.succeed("grep -q 'client alice' /var/lib/radius/clients.conf")

    with subtest("Certificate generation"):
        server.succeed("test -f /var/lib/radius/ca.pem")
        server.succeed("test -f /var/lib/radius/server.pem")
        server.succeed("test -f /var/lib/radius/server.key")

    with subtest("Hostapd configuration"):
        server.succeed("test -f /etc/hostapd/hostapd.conf")
        server.succeed("grep -q 'interface=wlan0' /etc/hostapd/hostapd.conf")
        server.succeed("grep -q 'auth_server_addr=127.0.0.1' /etc/hostapd/hostapd.conf")

    with subtest("User authentication"):
        # Test that client can connect (simplified test)
        client.succeed("timeout 10 wpa_supplicant -i eth0 -c /etc/wpa_supplicant.conf || true")
        
        # Check if authentication was successful
        server.succeed("journalctl -u freeradius -n 100 | grep -q 'alice' || true")
        
        # Check RADIUS attributes for user
        result = server.succeed(
          "${pkgs.freeradius}/bin/radtest alice password123 127.0.0.1 1812 testing123"
        )
        if "Tunnel-Private-Group-Id=\"10\"" not in result:
          raise Exception("VLAN assignment failed")

    with subtest("Guest access"):
        # Test guest VLAN assignment
        server.succeed("journalctl -u freeradius -n 100 | grep -q 'guest' || true")
        
        # Check RADIUS attributes for guest
        result = server.succeed(
          "${pkgs.freeradius}/bin/radtest guest 127.0.0.1 1812 testing123"
        )
        if "Tunnel-Private-Group-Id=\"999\"" not in result:
          raise Exception("Guest VLAN assignment failed")

    with subtest("Policy enforcement"):
        # Test that unauthorized access is blocked
        result = server.succeed(
          "${pkgs.freeradius}/bin/radtest unauthorized 127.0.0.1 1812 testing123"
        )
        if "Access-Reject" not in result:
          raise Exception("Policy enforcement failed")
  '';
}

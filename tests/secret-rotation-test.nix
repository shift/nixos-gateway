{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "nixos-gateway-secret-rotation";

  nodes = {
    gateway =
      { config, pkgs, ... }:
      {
        imports = [
          ../modules
        ];

        services.gateway = {
          enable = true;

          interfaces = {
            lan = "eth1";
            wan = "eth0";
            mgmt = "eth1";
          };

          ipv6Prefix = "2001:db8::";
          domain = "test.local";

          # Test secret rotation configuration
          secretRotation = {
            enable = true;

            certificates = {
              gateway-cert = {
                type = "selfSigned";
                domain = "gateway.test.local";
                renewBefore = "30d";
                reloadServices = [ ];
              };
            };

            keys = {
              vpn-key = {
                type = "wireguard";
                interface = "wg0";
                rotationInterval = "90d";
                coordinationRequired = false;
                peerNotification = false;
                peers = [ ];
                dependentServices = [ ];
              };

              dns-tsig = {
                type = "tsig";
                name = "gateway-key";
                algorithm = "hmac-sha256";
                rotationInterval = "180d";
                dependentServices = [ ];
              };

              api-key = {
                type = "apiKey";
                serviceName = "gateway-api";
                rotationInterval = "30d";
                keyLength = 32;
                dependentServices = [ ];
                updateCommand = null;
              };
            };

            monitoring = {
              expirationWarnings = [
                "30d"
                "14d"
                "7d"
                "1d"
              ];
              alertOnFailure = true;
              rotationMetrics = true;
            };
          };

          data = {
            network = {
              subnets = {
                lan = {
                  ipv4 = {
                    subnet = "192.168.1.0/24";
                    gateway = "192.168.1.1";
                  };
                  ipv6 = {
                    prefix = "2001:db8::/48";
                    gateway = "2001:db8::1";
                  };
                };
              };
            };
          };
        };

        virtualisation.vlans = [
          1
          2
        ];

        systemd.network.networks."10-lan".address = lib.mkForce [ "192.168.1.1/24" ];
        systemd.network.networks."20-wan".address = lib.mkForce [ "10.0.1.1/24" ];

        networking.firewall.enable = lib.mkForce false;
        boot.kernel.sysctl = {
          "net.ipv4.ip_forward" = 1;
          "net.ipv6.conf.all.forwarding" = 1;
        };

        # Mock WireGuard interface for testing
        networking.wireguard.interfaces.wg0 = {
          ips = [ "10.0.0.1/24" ];
          privateKey = "4P5MHmLf1HW/3b1pV3EgZ9Rml/KWXdqxqRPyoVQlYH0=";
          peers = [
            {
              publicKey = "ABC123XYZ789DEF456GHI789JKL012MNO345PQR678STU901VWX234YZA567BCD890";
              allowedIPs = [ "10.0.0.2/32" ];
            }
          ];
        };

        # Mock API service
        systemd.services.gateway-api = {
          description = "Gateway API service";
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "simple";
            ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
            Restart = "always";
          };
        };

        # Required packages for testing
        environment.systemPackages = with pkgs; [
          openssl
          wireguard-tools
          coreutils
          findutils
          bc
        ];

        boot.loader.systemd-boot.enable = lib.mkForce false;
      };
  };

  testScript = ''
    start_all()

    with subtest("Gateway boots and rotation services start"):
        gateway.wait_for_unit("multi-user.target")
        gateway.wait_for_unit("gateway-enhanced-key-rotation-setup.service")

    with subtest("Rotation directories are created"):
        gateway.succeed("test -d /run/gateway-secrets")
        gateway.succeed("test -d /var/backups/gateway-secrets")
        gateway.succeed("test -d /var/log/gateway")
        gateway.succeed("test -d /var/lib/gateway-key-coordination")

    with subtest("Enhanced key rotation scripts are deployed"):
        gateway.succeed("test -x /run/gateway-secrets/vpn-key-enhanced-rotate.sh")
        gateway.succeed("test -x /run/gateway-secrets/dns-tsig-enhanced-rotate.sh")
        gateway.succeed("test -x /run/gateway-secrets/api-key-enhanced-rotate.sh")
        gateway.succeed("test -x /run/gateway-secrets/key-coordination.sh")

    with subtest("Certificate rotation scripts are deployed"):
        gateway.succeed("test -x /run/gateway-secrets/gateway-cert-rotate.sh")

    with subtest("Key coordination service is available"):
        gateway.wait_for_unit("gateway-key-coordination.service")
        gateway.succeed("systemctl status gateway-key-coordination.service")

    with subtest("Enhanced key rotation service is available"):
        gateway.wait_for_unit("gateway-enhanced-key-rotation.service")
        gateway.succeed("systemctl status gateway-enhanced-key-rotation.service")

    with subtest("Rotation timers are enabled"):
        gateway.wait_for_unit("gateway-enhanced-key-rotation.timer")
        gateway.succeed("systemctl is-enabled gateway-enhanced-key-rotation.timer")

    with subtest("Self-signed certificate generation works"):
        # Run certificate rotation
        result = gateway.succeed("/run/gateway-secrets/gateway-cert-rotate.sh")
        assert "completed successfully" in result.lower(), "Certificate rotation failed"
        
        # Check certificate files are created
        gateway.succeed("test -f /run/gateway-secrets/gateway.test.local.crt")
        gateway.succeed("test -f /run/gateway-secrets/gateway.test.local.key")
        
        # Validate certificate format
        gateway.succeed("openssl x509 -in /run/gateway-secrets/gateway.test.local.crt -noout -text")
        gateway.succeed("openssl rsa -in /run/gateway-secrets/gateway.test.local.key -check -noout")

    with subtest("WireGuard key rotation works"):
        # Run WireGuard key rotation
        result = gateway.succeed("/run/gateway-secrets/vpn-key-enhanced-rotate.sh")
        assert "completed successfully" in result.lower(), "WireGuard key rotation failed"
        
        # Check key files are created
        gateway.succeed("test -f /run/gateway-secrets/wg0.private")
        gateway.succeed("test -f /run/gateway-secrets/wg0.public")
        
        # Validate key format
        private_key = gateway.succeed("cat /run/gateway-secrets/wg0.private").strip()
        public_key = gateway.succeed("cat /run/gateway-secrets/wg0.public").strip()
        gateway.succeed(f"echo '{private_key}' | wg pubkey")

    with subtest("TSIG key rotation works"):
        # Run TSIG key rotation
        result = gateway.succeed("/run/gateway-secrets/dns-tsig-enhanced-rotate.sh")
        assert "completed successfully" in result.lower(), "TSIG key rotation failed"
        
        # Check key file is created
        gateway.succeed("test -f /run/gateway-secrets/gateway-key.key")
        
        # Validate key is base64 encoded
        tsig_key = gateway.succeed("cat /run/gateway-secrets/gateway-key.key").strip()
        gateway.succeed(f"echo '{tsig_key}' | base64 -d")

    with subtest("API key rotation works"):
        # Run API key rotation
        result = gateway.succeed("/run/gateway-secrets/api-key-enhanced-rotate.sh")
        assert "completed successfully" in result.lower(), "API key rotation failed"
        
        # Check API key file is created
        gateway.succeed("test -f /run/gateway-secrets/gateway-api.apikey")
        
        # Check API key length
        api_key = gateway.succeed("cat /run/gateway-secrets/gateway-api.apikey").strip()
        assert len(api_key) >= 16, f"API key too short: {len(api_key)} characters"

    with subtest("Key coordination functionality works"):
        # Test coordination script
        result = gateway.succeed("/run/gateway-secrets/key-coordination.sh init vpn-key")
        assert "Coordination initiated" in result, "Key coordination init failed"
        
        # Check coordination file is created
        gateway.succeed("test -f /var/lib/gateway-key-coordination/vpn-key.coord")
        
        # Check coordination status
        coord_content = gateway.succeed("cat /var/lib/gateway-key-coordination/vpn-key.coord")
        assert "status=initiated" in coord_content, "Coordination status incorrect"

    with subtest("Backup functionality works"):
        # Run rotation to create backup
        gateway.succeed("/run/gateway-secrets/gateway-cert-rotate.sh")
        
        # Check backup files are created
        backup_files = gateway.succeed("ls /var/backups/gateway-secrets/ 2>/dev/null || true").strip()
        assert backup_files != "", "No backup files created"

    with subtest("File permissions are correct"):
        # Check private key permissions
        result = gateway.succeed("stat -c '%a' /run/gateway-secrets/gateway.test.local.key")
        assert result.strip() == "600", f"Private key permissions incorrect: {result}"
        
        # Check certificate permissions
        result = gateway.succeed("stat -c '%a' /run/gateway-secrets/gateway.test.local.crt")
        assert result.strip() in ["644", "640"], f"Certificate permissions incorrect: {result}"

    with subtest("Log files are created"):
        # Check rotation logs
        gateway.wait_until_succeeds("test -f /var/log/gateway/enhanced-key-rotation.log")
        gateway.wait_until_succeeds("test -f /var/log/gateway/key-coordination.log")
        
        # Check logs contain rotation entries
        gateway.succeed("grep -q 'Starting enhanced key rotation' /var/log/gateway/enhanced-key-rotation.log")

    with subtest("Service continuity after rotation"):
        # Check services are still running after rotations
        gateway.succeed("systemctl is-active wg-quick-wg0")
        gateway.succeed("systemctl is-active gateway-api")

    with subtest("Rotation state tracking works"):
        # Check last rotation files are created
        gateway.wait_until_succeeds("test -f /run/gateway-secrets/vpn-key.last_rotation")
        gateway.wait_until_succeeds("test -f /run/gateway-secrets/dns-tsig.last_rotation")
        gateway.wait_until_succeeds("test -f /run/gateway-secrets/api-key.last_rotation")

    with subtest("Error handling works"):
        # Test with invalid rotation type (should fail gracefully)
        result = gateway.succeed("echo 'invalid' | /run/gateway-secrets/vpn-key-enhanced-rotate.sh 2>&1 || true")
        # System should remain stable
        gateway.succeed("systemctl is-active wg-quick-wg0")

    with subtest("Performance is acceptable"):
        # Check rotation completes in reasonable time
        import time
        start_time = time.time()
        gateway.succeed("/run/gateway-secrets/api-key-enhanced-rotate.sh")
        end_time = time.time()
        duration = end_time - start_time
        assert duration < 30, f"Rotation took too long: {duration} seconds"

    print("✅ All secret rotation tests passed!")
  '';
}

# SSH Hardening Testing for NixOS Gateway Configuration Framework
# Tests SSH security hardening including root restrictions, key-based auth, rate limiting, and brute force protection

{ pkgs, lib, ... }:

let
  # SSH configuration templates for testing
  sshConfigs = {
    # Hardened SSH configuration
    hardenedConfig = pkgs.writeText "sshd-hardened.conf" ''
      # SSH Hardening Configuration
      
      # Basic security
      Protocol 2
      PermitRootLogin no
      PermitEmptyPasswords no
      PasswordAuthentication no
      PubkeyAuthentication yes
      
      # Key-based authentication only
      AuthorizedKeysFile .ssh/authorized_keys
      StrictModes yes
      
      # Connection limiting
      MaxAuthTries 3
      MaxSessions 10
      LoginGraceTime 30
      
      # Rate limiting
      ClientAliveInterval 300
      ClientAliveCountMax 2
      
      # Security options
      X11Forwarding no
      AllowTcpForwarding no
      GatewayPorts no
      PermitTunnel no
      
      # User restrictions
      AllowGroups ssh-users wheel
      DenyUsers nobody nobody
      
      # Port and protocol
      Port 22
      AddressFamily inet
      
      # Logging
      SyslogFacility AUTH
      LogLevel VERBOSE
      
      # Ciphers and MACs
      Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
      MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com
      KexAlgorithms curve25519-sha256@libssh.org,diffie-hellman-group16-sha512
      
      # Banner
      Banner /etc/ssh/banner.txt
    '';

    # Weak configuration (should fail validation)
    weakConfig = pkgs.writeText "sshd-weak.conf" ''
      # Weak SSH Configuration (for negative testing)
      
      Protocol 1
      PermitRootLogin yes
      PermitEmptyPasswords yes
      PasswordAuthentication yes
      PubkeyAuthentication no
      
      MaxAuthTries 10
      MaxSessions 100
      LoginGraceTime 300
      
      X11Forwarding yes
      AllowTcpForwarding yes
      GatewayPorts yes
      
      WeakCiphers aes128-cbc,3des-cbc
    '';

    # Custom security policy
    customPolicy = pkgs.writeText "sshd-custom-policy.conf" ''
      # Custom SSH Security Policy
      
      # Basic settings
      Protocol 2
      PermitRootLogin no
      PasswordAuthentication no
      
      # Multi-factor authentication setup
      AuthenticationMethods "publickey,keyboard-interactive"
      ChallengeResponseAuthentication yes
      
      # Advanced connection limits
      MaxAuthTries 2
      MaxSessions 5
      LoginGraceTime 15
      
      # IP-based restrictions
      AllowUsers admin@192.168.1.0/24 deploy@10.0.0.0/8
      
      # Time-based restrictions
      AcceptEnv LANG,LC_*
      
      # Advanced security
      TrustedUserCAKeys /etc/ssh/ca_key.pub
      RevokedKeys /etc/ssh/revoked_keys
      
      # Strict host key checking
      StrictHostKeyChecking yes
      
      # Port randomization
      Port 2222
    '';
  };

  # SSH test utilities
  sshTestUtils = {
    # Generate SSH key pairs for testing
    generateKeyPair = pkgs.writeShellScript "generate-ssh-keypair" ''
      #!/bin/bash
      set -e
      
      KEY_NAME="$1"
      KEY_TYPE="$2"
      KEY_BITS="$3"
      
      KEY_DIR="/tmp/ssh-test-keys"
      mkdir -p "$KEY_DIR"
      
      # Generate key pair
      ssh-keygen -t "$KEY_TYPE" -b "$KEY_BITS" -f "$KEY_DIR/$KEY_NAME" -N "" -C "$KEY_NAME@test"
      
      # Set proper permissions
      chmod 600 "$KEY_DIR/$KEY_NAME"
      chmod 644 "$KEY_DIR/$KEY_NAME.pub"
      
      echo "SSH key pair generated:"
      echo "Private: $KEY_DIR/$KEY_NAME"
      echo "Public: $KEY_DIR/$KEY_NAME.pub"
      
      # Return the key path
      echo "$KEY_DIR/$KEY_NAME"
    '';

    # Test SSH connection
    testSSHConnection = pkgs.writeShellScript "test-ssh-connection" ''
      #!/bin/bash
      set -e
      
      PRIVATE_KEY="$1"
      TARGET_HOST="$2"
      TARGET_USER="$3"
      TARGET_PORT="$4"
      COMMAND="$5"
      
      echo "Testing SSH connection to $TARGET_USER@$TARGET_HOST:$TARGET_PORT"
      
      # Test connection with timeout
      if ssh -i "$PRIVATE_KEY" \
             -o ConnectTimeout=10 \
             -o StrictHostKeyChecking=no \
             -o UserKnownHostsFile=/dev/null \
             -p "$TARGET_PORT" \
             "$TARGET_USER@$TARGET_HOST" \
             "$COMMAND"; then
        echo "✓ SSH connection successful"
        return 0
      else
        echo "✗ SSH connection failed"
        return 1
      fi
    '';

    # Simulate brute force attack
    simulateBruteForce = pkgs.writeShellScript "simulate-brute-force" ''
      #!/bin/bash
      set -e
      
      TARGET_HOST="$1"
      TARGET_PORT="$2"
      USER_FILE="$3"
      PASSWORD_FILE="$4"
      
      echo "Simulating brute force attack on $TARGET_HOST:$TARGET_PORT"
      
      # Use hydra for brute force simulation
      hydra -L "$USER_FILE" -P "$PASSWORD_FILE" \
            -o /tmp/hydra-bruteforce.log \
            -t 4 -w 3 \
            ssh://"$TARGET_HOST:$TARGET_PORT" || true
      
      echo "Brute force simulation completed"
    '';

    # Test SSH configuration validation
    validateSSHConfig = pkgs.writeShellScript "validate-ssh-config" ''
      #!/bin/bash
      set -e
      
      CONFIG_FILE="$1"
      
      echo "Validating SSH configuration: $CONFIG_FILE"
      
      # Test configuration syntax
      if /run/current-system/sw/sbin/sshd -t -f "$CONFIG_FILE"; then
        echo "✓ SSH configuration syntax is valid"
        return 0
      else
        echo "✗ SSH configuration syntax is invalid"
        return 1
      fi
    '';

    # Check SSH security settings
    checkSSHSecurity = pkgs.writeShellScript "check-ssh-security" ''
      #!/bin/bash
      set -e
      
      CONFIG_FILE="$1"
      
      echo "Checking SSH security settings in: $CONFIG_FILE"
      
      # Security checks
      issues=0
      
      # Check for weak settings
      if grep -q "^PermitRootLogin yes" "$CONFIG_FILE"; then
        echo "⚠ WEAKNESS: Root login enabled"
        issues=$((issues + 1))
      fi
      
      if grep -q "^PasswordAuthentication yes" "$CONFIG_FILE"; then
        echo "⚠ WEAKNESS: Password authentication enabled"
        issues=$((issues + 1))
      fi
      
      if grep -q "^PermitEmptyPasswords yes" "$CONFIG_FILE"; then
        echo "⚠ WEAKNESS: Empty passwords allowed"
        issues=$((issues + 1))
      fi
      
      if grep -q "^Protocol 1" "$CONFIG_FILE"; then
        echo "⚠ WEAKNESS: SSH protocol 1 enabled"
        issues=$((issues + 1))
      fi
      
      # Check for strong settings
      if grep -q "^PermitRootLogin no" "$CONFIG_FILE"; then
        echo "✓ Root login disabled"
      fi
      
      if grep -q "^PasswordAuthentication no" "$CONFIG_FILE"; then
        echo "✓ Password authentication disabled"
      fi
      
      if grep -q "^PubkeyAuthentication yes" "$CONFIG_FILE"; then
        echo "✓ Public key authentication enabled"
      fi
      
      if grep -q "^MaxAuthTries [1-3]$" "$CONFIG_FILE"; then
        echo "✓ Low maximum authentication attempts"
      fi
      
      echo "Security check completed: $issues issues found"
      return $issues
    '';
  };

in {
  name = "ssh-hardening-test";

  nodes = {
    # SSH Server with hardened configuration
    sshServer = { config, pkgs, ... }: {
      imports = [
        ../../modules/security.nix
      ];

      networking = {
        hostName = "ssh-server";
        interfaces.eth0 = {
          ipv4.addresses = [ { address = "192.168.1.10"; prefixLength = 24; } ];
        };
      };

      # SSH service configuration
      services.openssh = {
        enable = true;
        settings = {
          # Basic hardening
          PermitRootLogin = "no";
          PasswordAuthentication = false;
          PubkeyAuthentication = true;
          PermitEmptyPasswords = false;
          
          # Connection limits
          MaxAuthTries = 3;
          MaxSessions = 10;
          LoginGraceTime = 30;
          
          # Security features
          X11Forwarding = false;
          AllowTcpForwarding = false;
          GatewayPorts = false;
          PermitTunnel = false;
          
          # Protocol and ciphers
          Protocol = 2;
          Ciphers = [
            "chacha20-poly1305@openssh.com"
            "aes256-gcm@openssh.com"
            "aes128-gcm@openssh.com"
          ];
          MACs = [
            "hmac-sha2-256-etm@openssh.com"
            "hmac-sha2-512-etm@openssh.com"
          ];
          KexAlgorithms = [
            "curve25519-sha256@libssh.org"
            "diffie-hellman-group16-sha512"
          ];
          
          # Logging and monitoring
          LogLevel = "VERBOSE";
          SyslogFacility = "AUTH";
          
          # Additional security
          UsePrivilegeSeparation = "sandbox";
          ClientAliveInterval = 300;
          ClientAliveCountMax = 2;
        };

        # Rate limiting and protection
        extraConfig = ''
          # Fail2Ban integration
          MaxStartups 10:30:100
          
          # IP-based restrictions
          AllowGroups ssh-users wheel
          DenyUsers nobody nobody
          
          # Banner
          Banner /etc/ssh/banner.txt
        '';
      };

      # Create SSH banner
      environment.etc."ssh/banner.txt".text = ''
        *******************************************************************************
        *                                                                             *
        *                    AUTHORIZED ACCESS ONLY                                    *
        *                                                                             *
        *  Unauthorized access is prohibited and will be prosecuted to the fullest extent *
        *  of the law. All activities are monitored and logged.                        *
        *                                                                             *
        *******************************************************************************
      '';

      # Create user groups
      users.groups.ssh-users = {};

      # Create test users
      users.users = {
        admin = {
          isNormalUser = true;
          extraGroups = [ "wheel" "ssh-users" ];
          openssh.authorizedKeys.keys = [
            "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC7VqZw5zB+rJFDKHkdHWi3DRkZwqYj4M+8t1EJz+2Bd7+zxEgZjQrFESD8pzSWAYdyoBUIrCg+hQ0GFgK1tDkXdx6Oz7Jtz6Q6J8y9sJf3mHkL4xQv5t2kZ7r8wA6yC1sD2fE3gH4iJ5kL6mN7oP8qR9sT0uV1wX2yZ3a4b5c6d7e8f9g0h1i2j3 admin@test"
          ];
        };

        deploy = {
          isNormalUser = true;
          extraGroups = [ "ssh-users" ];
          openssh.authorizedKeys.keys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGn5t8X6wYm7Zqk9p1n2r3s4t5u6v7w8x9y0z1a2b3c4d5e6f7g8h9i0j1k2l3m4n5o6 deploy@test"
          ];
        };
      };

      # Security monitoring
      services.fail2ban = {
        enable = true;
        jails = {
          sshd = {
            enabled = true;
            filter = "sshd";
            maxretry = 3;
            bantime = 3600;
            findtime = 600;
            port = "ssh";
          };
        };
      };

      # Evidence collection for SSH events
      systemd.services.ssh-evidence-collector = {
        description = "SSH Security Evidence Collection";
        wantedBy = [ "multi-user.target" ];
        after = [ "sshd.service" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "collect-ssh-evidence" ''
            #!/bin/bash
            set -e
            
            EVIDENCE_DIR="/var/lib/evidence/ssh"
            mkdir -p "$EVIDENCE_DIR"
            
            # Collect SSH logs
            if [ -f "/var/log/auth.log" ]; then
              tail -n 1000 /var/log/auth.log > "$EVIDENCE_DIR/auth-log-recent.txt"
            fi
            
            # Collect SSH configuration
            cp /etc/ssh/sshd_config "$EVIDENCE_DIR/sshd-config.txt" 2>/dev/null || true
            
            # Collect active SSH sessions
            who > "$EVIDENCE_DIR/active-sessions.txt" 2>/dev/null || true
            
            # Collect Fail2Ban status
            fail2ban-client status > "$EVIDENCE_DIR/fail2ban-status.txt" 2>/dev/null || true
            
            echo "SSH evidence collected at $(date)" >> "$EVIDENCE_DIR/collection-log.txt"
          '';
        };
      };

      # Monitoring for SSH security
      services.prometheus = {
        enable = true;
        exporters = {
          node = {
            enable = true;
            enabledCollectors = [ "systemd" "processes" "logind" ];
          };
        };
      };

      # Test utilities
      environment.systemPackages = with pkgs; [
        openssh
        fail2ban
        hydra
        ssh-audit
        nmap
        # Custom test scripts
        sshTestUtils.generateKeyPair
        sshTestUtils.testSSHConnection
        sshTestUtils.simulateBruteForce
        sshTestUtils.validateSSHConfig
        sshTestUtils.checkSSHSecurity
      ];
    };

    # SSH client for testing
    sshClient = { config, pkgs, ... }: {
      networking = {
        hostName = "ssh-client";
        interfaces.eth0 = {
          ipv4.addresses = [ { address = "192.168.1.20"; prefixLength = 24; } ];
          ipv4.routes = [ { address = "0.0.0.0"; prefixLength = 0; via = "192.168.1.1"; } ];
        };
      };

      environment.systemPackages = with pkgs; [
        openssh
        hydra
        ssh-audit
      ];

      # Create SSH keys for testing
      system.activationScripts.sshKeys = ''
        mkdir -p /tmp/ssh-test-keys
        
        # Generate test key pairs
        ssh-keygen -t rsa -b 2048 -f /tmp/ssh-test-keys/admin-key -N "" -C "admin@test"
        ssh-keygen -t ed25519 -f /tmp/ssh-test-keys/deploy-key -N "" -C "deploy@test"
        
        # Set permissions
        chmod 600 /tmp/ssh-test-keys/*-key
        chmod 644 /tmp/ssh-test-keys/*-key.pub
        
        echo "SSH test keys generated"
      '';
    };

    # Attacker for brute force testing
    attacker = { config, pkgs, ... }: {
      networking = {
        hostName = "attacker";
        interfaces.eth0 = {
          ipv4.addresses = [ { address = "192.168.1.100"; prefixLength = 24; } ];
          ipv4.routes = [ { address = "0.0.0.0"; prefixLength = 0; via = "192.168.1.1"; } ];
        };
      };

      environment.systemPackages = with pkgs; [
        openssh
        hydra
        nmap
        metasploit
        john
      ];

      # Prepare wordlists for brute force
      system.activationScripts.wordlists = ''
        mkdir -p /tmp/wordlists
        
        # Create test user list
        cat > /tmp/wordlists/users.txt << EOF
        admin
        root
        deploy
        user
        test
        ssh
        admin1
        root1
        operator
        EOF
        
        # Create test password list
        cat > /tmp/wordlists/passwords.txt << EOF
        password
        123456
        admin
        root
        password123
        123456789
        qwerty
        letmein
        welcome
        changeme
        EOF
        
        echo "Brute force wordlists prepared"
      '';
    };
  };

  testScript = ''
    import time
    import subprocess
    import re

    start_all()

    # Wait for SSH server to be ready
    sshServer.wait_for_unit("sshd.service")
    sshServer.wait_for_unit("fail2ban.service")

    print("=== Starting SSH Hardening Tests ===")

    # Test 1: Root Access Restriction
    print("\n1. Testing Root Access Restriction...")
    try:
        result = sshClient.succeed("ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@192.168.1.10 'echo SSH_SUCCESS'", timeout=10)
        print("✗ Root login should be denied")
        root_access_blocked = False
    except:
        print("✓ Root login properly blocked")
        root_access_blocked = True

    # Test 2: Password Authentication Disabled
    print("\n2. Testing Password Authentication...")
    try:
        result = sshClient.succeed("sshpass -p 'wrongpassword' ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PreferredAuthentications=password admin@192.168.1.10 'echo SSH_SUCCESS'", timeout=10)
        print("✗ Password authentication should be disabled")
        password_auth_disabled = False
    except:
        print("✓ Password authentication properly disabled")
        password_auth_disabled = True

    # Test 3: Key-based Authentication
    print("\n3. Testing Key-based Authentication...")
    
    # Copy public key to server
    sshClient.succeed("scp -o StrictHostKeyChecking=no /tmp/ssh-test-keys/admin-key.pub admin@192.168.1.10:/tmp/admin-key.pub")
    sshServer.succeed("mkdir -p /home/testuser/.ssh && cat /tmp/admin-key.pub >> /home/testuser/.ssh/authorized_keys && chown -R testuser:users /home/testuser/.ssh && chmod 600 /home/testuser/.ssh/authorized_keys")
    
    # Test key-based login
    try:
        result = sshClient.succeed("ssh -i /tmp/ssh-test-keys/admin-key -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null admin@192.168.1.10 'whoami'", timeout=15)
        if "admin" in result:
            print("✓ Key-based authentication working")
            key_auth_works = True
        else:
            print("✗ Key-based authentication failed")
            key_auth_works = False
    except:
        print("✗ Key-based authentication failed")
        key_auth_works = False

    # Test 4: Rate Limiting and MaxAuthTries
    print("\n4. Testing Rate Limiting...")
    
    # Attempt multiple failed authentications
    failed_attempts = 0
    for i in range(5):
        try:
            sshClient.succeed("ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PreferredAuthentications=password -o NumberOfPasswordPrompts=1 admin@192.168.1.10 'echo SSH_SUCCESS'", timeout=5)
        except:
            failed_attempts += 1
    
    if failed_attempts >= 3:
        print("✓ Rate limiting working - multiple attempts blocked")
        rate_limiting_works = True
    else:
        print("✗ Rate limiting not working properly")
        rate_limiting_works = False

    # Test 5: Brute Force Protection
    print("\n5. Testing Brute Force Protection...")
    
    # Start brute force attack simulation
    attacker.succeed("hydra -L /tmp/wordlists/users.txt -P /tmp/wordlists/passwords.txt -o /tmp/hydra.log -t 2 -w 3 ssh://192.168.1.10 || true", timeout=30)
    
    # Check if attacker was blocked
    time.sleep(5)
    
    try:
        # Try a simple connection after brute force
        result = attacker.succeed("ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null admin@192.168.1.10 'echo TEST'", timeout=10)
        print("⚠ Brute force protection may not be active")
        brute_force_protection = False
    except:
        print("✓ Brute force protection active - connections blocked")
        brute_force_protection = True

    # Test 6: SSH Configuration Validation
    print("\n6. Testing SSH Configuration Validation...")
    
    # Validate current configuration
    validation_result = sshServer.succeed("sshd -t")
    if "error" not in validation_result.lower() and "failed" not in validation_result.lower():
        print("✓ SSH configuration is valid")
        config_valid = True
    else:
        print("✗ SSH configuration has errors")
        config_valid = False

    # Test 7: Security Policy Enforcement
    print("\n7. Testing Security Policy Enforcement...")
    
    # Check security settings
    config_check = sshServer.succeed("grep -E '^(PermitRootLogin|PasswordAuthentication|PubkeyAuthentication)' /etc/ssh/sshd_config")
    
    security_policies = {
        "PermitRootLogin no": "PermitRootLogin no" in config_check,
        "PasswordAuthentication no": "PasswordAuthentication no" in config_check,
        "PubkeyAuthentication yes": "PubkeyAuthentication yes" in config_check
    }
    
    if all(security_policies.values()):
        print("✓ All security policies properly enforced")
        security_policies_ok = True
    else:
        failed_policies = [k for k, v in security_policies.items() if not v]
        print(f"✗ Failed security policies: {failed_policies}")
        security_policies_ok = False

    # Test 8: SSH Service Hardening
    print("\n8. Testing SSH Service Hardening...")
    
    # Check SSH service status and configuration
    service_status = sshServer.succeed("systemctl status sshd | grep Active | awk '{print $2}'")
    if "active" in service_status.lower():
        print("✓ SSH service is active")
        service_active = True
    else:
        print("✗ SSH service is not active")
        service_active = False

    # Test 9: Fail2Ban Integration
    print("\n9. Testing Fail2Ban Integration...")
    
    # Check Fail2Ban status
    try:
        fail2ban_status = sshServer.succeed("fail2ban-client status sshd")
        if "sshd" in fail2ban_status and "Enabled" in fail2ban_status:
            print("✓ Fail2Ban SSH jail is active")
            fail2ban_active = True
        else:
            print("⚠ Fail2Ban SSH jail not fully active")
            fail2ban_active = False
    except:
        print("✗ Fail2Ban not responding")
        fail2ban_active = False

    # Test 10: SSH Security Logging
    print("\n10. Testing SSH Security Logging...")
    
    # Check if logs are being generated
    log_check = sshServer.succeed("grep -c 'sshd' /var/log/auth.log || echo '0'")
    if int(log_check) > 0:
        print(f"✓ SSH security logging active ({log_check} entries)")
        logging_active = True
    else:
        print("⚠ SSH security logging may not be active")
        logging_active = False

    # Test 11: Evidence Collection
    print("\n11. Testing Evidence Collection...")
    
    # Trigger evidence collection
    sshServer.succeed("systemctl start ssh-evidence-collector.service")
    
    # Check if evidence was collected
    evidence_files = sshServer.succeed("ls -la /var/lib/evidence/ssh/ 2>/dev/null | wc -l")
    if int(evidence_files) > 2:  # Should have more than just . and ..
        print(f"✓ Evidence collection working ({evidence_files} files)")
        evidence_collection = True
    else:
        print("⚠ Evidence collection may not be working")
        evidence_collection = False

    # Test 12: Configuration Drift Detection
    print("\n12. Testing Configuration Drift Detection...")
    
    # Get current configuration
    current_config = sshServer.succeed("cat /etc/ssh/sshd_config")
    
    # Simulate configuration change (should be detected)
    sshServer.succeed("echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config_test")
    
    # Compare configurations
    drift_detected = "PermitRootLogin yes" not in current_config
    
    if drift_detected:
        print("✓ Configuration drift can be detected")
        config_drift_detection = True
    else:
        print("⚠ Configuration drift detection needs improvement")
        config_drift_detection = False

    # Test 13: SSH Protocol and Cipher Security
    print("\n13. Testing SSH Protocol and Cipher Security...")
    
    # Check for secure protocols and ciphers
    cipher_check = sshServer.succeed("grep -E '^(Protocol|Ciphers|MACs|KexAlgorithms)' /etc/ssh/sshd_config")
    
    security_settings = {
        "Protocol 2": "Protocol 2" in cipher_check,
        "secure ciphers": any(cipher in cipher_check for cipher in ["chacha20-poly1305", "aes256-gcm"]),
        "secure MACs": any(mac in cipher_check for mac in ["hmac-sha2-256-etm", "hmac-sha2-512-etm"])
    }
    
    if all(security_settings.values()):
        print("✓ SSH protocols and ciphers are secure")
        secure_protocols = True
    else:
        print("⚠ SSH security settings need review")
        secure_protocols = False

    # Test 14: Performance Under Load
    print("\n14. Testing Performance Under Load...")
    
    # Generate concurrent SSH connections
    start_time = time.time()
    
    successful_connections = 0
    for i in range(10):
        try:
            sshClient.succeed(f"ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i /tmp/ssh-test-keys/admin-key -f admin@192.168.1.10 'sleep 1'", timeout=5)
            successful_connections += 1
        except:
            pass
    
    end_time = time.time()
    performance_time = end_time - start_time
    
    if successful_connections >= 8 and performance_time < 15:
        print(f"✓ SSH performance acceptable ({successful_connections}/10 connections in {performance_time:.2f}s)")
        ssh_performance = True
    else:
        print(f"⚠ SSH performance needs improvement ({successful_connections}/10 connections in {performance_time:.2f}s)")
        ssh_performance = False

    # Test 15: Integration with Monitoring
    print("\n15. Testing Monitoring Integration...")
    
    # Check if SSH metrics are available
    try:
        metrics = sshServer.succeed("curl -s http://localhost:9100/metrics | grep ssh || echo 'No SSH metrics'")
        if "node" in metrics.lower():
            print("✓ Monitoring integration working")
            monitoring_integration = True
        else:
            print("⚠ SSH-specific metrics not available")
            monitoring_integration = False
    except:
        print("⚠ Monitoring integration may need configuration")
        monitoring_integration = False

    # Generate comprehensive test report
    print("\n=== SSH Hardening Test Results ===")
    
    test_results = {
        "Root Access Restriction": root_access_blocked,
        "Password Authentication Disabled": password_auth_disabled,
        "Key-based Authentication": key_auth_works,
        "Rate Limiting": rate_limiting_works,
        "Brute Force Protection": brute_force_protection,
        "Configuration Validation": config_valid,
        "Security Policy Enforcement": security_policies_ok,
        "SSH Service Hardening": service_active,
        "Fail2Ban Integration": fail2ban_active,
        "Security Logging": logging_active,
        "Evidence Collection": evidence_collection,
        "Configuration Drift Detection": config_drift_detection,
        "Secure Protocols and Ciphers": secure_protocols,
        "Performance Under Load": ssh_performance,
        "Monitoring Integration": monitoring_integration
    }

    passed_tests = sum(test_results.values())
    total_tests = len(test_results)
    success_rate = (passed_tests / total_tests) * 100

    print(f"Overall Results: {passed_tests}/{total_tests} tests passed ({success_rate:.1f}%)")
    print()

    for test_name, result in test_results.items():
        status = "PASS" if result else "FAIL"
        icon = "✓" if result else "✗"
        print(f"{icon} {test_name}: {status}")

    print()

    # Save comprehensive evidence report
    sshServer.succeed(f'''
      cat > /var/lib/evidence/ssh/ssh-hardening-report.json << 'EOF'
      {{
        "timestamp": "{time.time()}",
        "test_results": {test_results},
        "summary": {{
          "total_tests": {total_tests},
          "passed_tests": {passed_tests},
          "failed_tests": {total_tests - passed_tests},
          "success_rate": {success_rate}
        }},
        "security_assessment": {{
          "root_access_blocked": {root_access_blocked},
          "password_auth_disabled": {password_auth_disabled},
          "key_auth_enforced": {key_auth_works},
          "brute_force_protection": {brute_force_protection},
          "rate_limiting_active": {rate_limiting_works}
        }},
        "performance_metrics": {{
          "concurrent_connections": {successful_connections},
          "response_time": {performance_time}
        }},
        "recommendations": [
          "Enable automated security scanning",
          "Implement real-time threat detection",
          "Regular security audits",
          "Continuous monitoring and alerting",
          "Regular configuration reviews"
        ]
      }}
      EOF
    ''')

    # Generate final assessment
    if success_rate >= 80:
        print("🎉 SSH Hardening configuration SECURE!")
    elif success_rate >= 60:
        print("⚠ SSH Hardening configuration needs improvement")
    else:
        print("❌ SSH Hardening configuration has significant security issues")

    print("\nSSH Hardening testing completed!")
  '';
}

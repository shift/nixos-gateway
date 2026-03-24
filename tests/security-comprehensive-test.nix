{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "nixos-gateway-security-comprehensive";

  nodes = {
    gateway =
      { config, pkgs, ... }:
      {
        imports = [
          ../modules/security.nix
          ../modules/default.nix
        ];

        services.gateway = {
          enable = true;

          interfaces = {
            lan = "eth1";
            wan = "eth0";
          };

          domain = "test.local";

          security = {
            engine = "crowdsec";
          };

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

            firewall = {
              enable = true;
              defaultPolicy = "drop";
              rules = [
                {
                  name = "allow-ssh";
                  source = "10.0.0.0/24";
                  destinationPort = 22;
                  protocols = [ "tcp" ];
                  action = "accept";
                  rateLimit = {
                    burst = 5;
                    rate = "5/minute";
                  };
                }
                {
                  name = "allow-http";
                  destinationPort = 80;
                  protocols = [ "tcp" ];
                  action = "accept";
                  rateLimit = {
                    burst = 100;
                    rate = "100/minute";
                  };
                }
                {
                  name = "allow-https";
                  destinationPort = 443;
                  protocols = [ "tcp" ];
                  action = "accept";
                  rateLimit = {
                    burst = 100;
                    rate = "100/minute";
                  };
                }
                {
                  name = "block-suspicious";
                  source = "0.0.0.0/0";
                  destinationPort = [
                    22
                    80
                    443
                  ];
                  protocols = [ "tcp" ];
                  action = "drop";
                  condition = "recent";
                }
              ];
            };

            ids = {
              enable = true;
              engine = "suricata";
              rules = [
                {
                  name = "block-port-scan";
                  action = "alert";
                  signature = "alert tcp any any -> $HOME_NET any (msg:\"Port Scan Detected\"; flags:S; threshold:type both, track by_src, count 10, seconds 30; sid:1000001;)";
                }
                {
                  name = "block-sql-injection";
                  action = "drop";
                  signature = "alert tcp $HOME_NET any -> $EXTERNAL_NET 80 (msg:\"SQL Injection Attempt\"; content:\"' OR\"; nocase; sid:1000002;)";
                }
                {
                  name = "block-xss";
                  action = "drop";
                  signature = "alert tcp $HOME_NET any -> $EXTERNAL_NET 80 (msg:\"XSS Attempt\"; content:\"<script\"; nocase; sid:1000003;)";
                }
              ];
              config = {
                af-packet = {
                  interface = "eth0";
                  cluster-id = 99;
                  cluster-type = "cluster_flow";
                };
                detect = {
                  profile = "medium";
                  custom-rules = "/etc/suricata/rules/custom.rules";
                };
                logging = {
                  outputs = [
                    {
                      fast = {
                        enabled = true;
                        filename = "/var/log/suricata/fast.log";
                      };
                    }
                    {
                      eve-log = {
                        enabled = true;
                        type = "file";
                        filename = "/var/log/suricata/eve.json";
                      };
                    }
                  ];
                };
              };
            };

            waf = {
              enable = true;
              engine = "modsecurity";
              rules = [
                {
                  name = "sql-injection-protection";
                  rule = "SecRule ARGS \"@detectSQLi\" \"id:1001,phase:2,block,msg:'SQL Injection Attack Detected',tag:'application-multi',tag:'language-multi',tag:'platform-multi',tag:'attack-sqli'\"";
                }
                {
                  name = "xss-protection";
                  rule = "SecRule ARGS \"@detectXSS\" \"id:1002,phase:2,block,msg:'XSS Attack Detected',tag:'application-multi',tag:'language-multi',tag:'platform-multi',tag:'attack-xss'\"";
                }
                {
                  name = "lfi-protection";
                  rule = "SecRule REQUEST_FILENAME \"@detectFileInclusion\" \"id:1003,phase:1,block,msg:'Local File Inclusion Attack Detected',tag:'application-multi',tag:'language-multi',tag:'platform-multi',tag:'attack-lfi'\"";
                }
              ];
              config = {
                secRuleEngine = "On";
                secRequestBodyAccess = true;
                secResponseBodyAccess = false;
                secRequestBodyLimit = 13107200;
                secRequestBodyNoFilesLimit = 131072;
                secRequestBodyInMemoryLimit = 131072;
                secResponseBodyLimit = 524288;
                secResponseBodyMimeType = "text/plain text/html";
              };
            };

            ips = {
              enable = true;
              engine = "suricata";
              mode = "inline";
              rules = [
                {
                  name = "block-malicious-ips";
                  action = "drop";
                  signature = "drop ip any any -> any any (msg:\"Block Known Malicious IP\"; ip.src == 192.0.2.100; sid:2000001;)";
                }
                {
                  name = "block-torrent-traffic";
                  action = "drop";
                  signature = "drop tcp any any -> any any (msg:\"Block BitTorrent\"; content:\"|13 42 69 74 54 6f 72 72 65 6e 74 20 70 72 6f 74 6f 63 6f 6c|\"; depth:19; sid:2000002;)";
                }
              ];
            };

            threatIntel = {
              enable = true;
              sources = [
                {
                  name = "malware-domains";
                  type = "domain";
                  url = "https://example.com/malware-domains.txt";
                  updateInterval = "1h";
                }
                {
                  name = "malicious-ips";
                  type = "ip";
                  url = "https://example.com/malicious-ips.txt";
                  updateInterval = "30m";
                }
              ];
              action = "block";
            };

            certificateManager = {
              enable = true;
              default = {
                keySize = 4096;
                digest = "sha256";
                validity = 365;
              };
              certificates = [
                {
                  name = "gateway";
                  domains = [
                    "gateway.test.local"
                    "*.test.local"
                  ];
                  keySize = 4096;
                  validity = 365;
                }
                {
                  name = "vpn";
                  domains = [ "vpn.test.local" ];
                  keySize = 2048;
                  validity = 90;
                }
              ];
            };

            keyRotation = {
              enable = true;
              interval = "90d";
              warning = "7d";
              autoRotate = true;
            };
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
        networking.interfaces.eth1.ipv4.addresses = lib.mkForce [
          {
            address = "10.0.0.10";
            prefixLength = 24;
          }
        ];
        networking.defaultGateway = lib.mkForce {
          address = "10.0.0.1";
          interface = "eth1";
        };
        networking.nameservers = [ "10.0.0.1" ];
      };

    attacker =
      { config, pkgs, ... }:
      {
        virtualisation.vlans = [ 1 ];
        virtualisation.qemu.options = [ "-device virtio-net-pci,netdev=vlan1,mac=aa:bb:cc:dd:ff:01" ];

        networking.useDHCP = false;
        networking.interfaces.eth1.ipv4.addresses = lib.mkForce [
          {
            address = "10.0.0.99";
            prefixLength = 24;
          }
        ];
        networking.defaultGateway = lib.mkForce {
          address = "10.0.0.1";
          interface = "eth1";
        };

        environment.systemPackages = with pkgs; [
          nmap
          curl
          wget
          hydra
          sqlmap
        ];
      };
  };

  testScript = ''
    start_all()

    with subtest("Security services start"):
        gateway.wait_for_unit("crowdsec.service")
        gateway.wait_for_unit("suricata.service")
        gateway.wait_for_unit("ssh.service")

    with subtest("SSH hardening is applied"):
        gateway.wait_until_succeeds("grep -q 'PermitRootLogin no' /etc/ssh/sshd_config")
        gateway.wait_until_succeeds("grep -q 'PasswordAuthentication no' /etc/ssh/sshd_config")
        gateway.wait_until_succeeds("grep -q 'MaxAuthTries 3' /etc/ssh/sshd_config")
        gateway.wait_until_succeeds("grep -q 'ClientAliveInterval 300' /etc/ssh/sshd_config")

    with subtest("SSH rate limiting is configured"):
        gateway.wait_until_succeeds("grep -q 'MaxStartups 10:30:60' /etc/ssh/sshd_config")

    with subtest("CrowdSec is running and configured"):
        gateway.wait_for_open_port(8080)  # CrowdSec API
        gateway.wait_until_succeeds("cscli lapi status")

    with subtest("Suricata IDS is running"):
        gateway.wait_until_succeeds("suricata -T -c /etc/suricata/suricata.yaml")
        gateway.wait_until_succeeds("test -f /var/log/suricata/eve.json")

    with subtest("Custom IDS rules are loaded"):
        gateway.wait_until_succeeds("grep -q 'Port Scan Detected' /etc/suricata/rules/custom.rules")
        gateway.wait_until_succeeds("grep -q 'SQL Injection Attempt' /etc/suricata/rules/custom.rules")

    with subtest("Firewall rules are applied"):
        gateway.wait_until_succeeds("iptables -L | grep 'allow-ssh'")
        gateway.wait_until_succeeds("iptables -L | grep 'allow-http'")
        gateway.wait_until_succeeds("iptables -L | grep 'allow-https'")

    with subtest("Rate limiting rules are active"):
        gateway.wait_until_succeeds("iptables -L | grep 'limit'")

    with subtest("WAF is configured"):
        gateway.wait_until_succeeds("test -f /etc/modsecurity/modsecurity.conf")
        gateway.wait_until_succeeds("grep -q 'SecRuleEngine On' /etc/modsecurity/modsecurity.conf")

    with subtest("WAF rules are loaded"):
        gateway.wait_until_succeeds("grep -q 'SQL Injection Attack Detected' /etc/modsecurity/custom_rules.conf")
        gateway.wait_until_succeeds("grep -q 'XSS Attack Detected' /etc/modsecurity/custom_rules.conf")

    with subtest("Certificate manager is working"):
        gateway.wait_until_succeeds("test -f /etc/ssl/certs/gateway.crt")
        gateway.wait_until_succeeds("test -f /etc/ssl/private/gateway.key")
        gateway.wait_until_succeeds("openssl x509 -in /etc/ssl/certs/gateway.crt -text -noout | grep 'gateway.test.local'")

    with subtest("Key rotation is configured"):
        gateway.wait_until_succeeds("test -f /etc/cron.d/key-rotation")

    with subtest("Threat intelligence is configured"):
        gateway.wait_until_succeeds("test -f /etc/threat-intel/malware-domains.txt")
        gateway.wait_until_succeeds("test -f /etc/threat-intel/malicious-ips.txt")

    with subtest("Legitimate client can access services"):
        client.wait_until_succeeds("nc -zv 10.0.0.1 22")
        client.wait_until_succeeds("curl -s http://10.0.0.1 | head -1")

    with subtest("Port scan detection works"):
        attacker.succeed("nmap -sS -p 1-1000 10.0.0.1")
        gateway.wait_until_succeeds("grep -q 'Port Scan Detected' /var/log/suricata/eve.json", timeout=60)

    with subtest("SSH brute force protection works"):
        # Simulate multiple failed SSH attempts
        attacker.fail("for i in {1..10}; do ssh -o ConnectTimeout=5 -o BatchMode=yes root@10.0.0.1 'echo test' 2>&1 || true; done")
        gateway.wait_until_succeeds("cscli decisions list | grep '10.0.0.99'", timeout=60)

    with subtest("HTTP rate limiting works"):
        # Simulate rapid HTTP requests
        attacker.fail("for i in {1..150}; do curl -s http://10.0.0.1 || true; done")
        gateway.wait_until_succeeds("iptables -L | grep 'DROP' | grep '10.0.0.99'", timeout=30)

    with subtest("WAF blocks SQL injection attempts"):
        attacker.fail("curl -X POST -d 'id=1 OR 1=1' http://10.0.0.1/login")
        gateway.wait_until_succeeds("grep -q 'SQL Injection Attack Detected' /var/log/modsecurity/audit.log", timeout=30)

    with subtest("WAF blocks XSS attempts"):
        attacker.fail("curl -X POST -d 'comment=<script>alert(1)</script>' http://10.0.0.1/comment")
        gateway.wait_until_succeeds("grep -q 'XSS Attack Detected' /var/log/modsecurity/audit.log", timeout=30)

    with subtest("IPS blocks malicious traffic"):
        # Simulate traffic from known malicious IP
        attacker.succeed("iptables -t nat -A POSTROUTING -j SNAT --to-source 192.0.2.100")
        attacker.fail("curl -s http://10.0.0.1")
        gateway.wait_until_succeeds("grep -q 'Block Known Malicious IP' /var/log/suricata/eve.json", timeout=30)

    with subtest("Security logs are being collected"):
        gateway.wait_until_succeeds("test -f /var/log/auth.log")
        gateway.wait_until_succeeds("test -f /var/log/suricata/fast.log")
        gateway.wait_until_succeeds("test -f /var/log/crowdsec.log")

    with subtest("Security monitoring is active"):
        gateway.wait_until_succeeds("systemctl is-active crowdsec.service")
        gateway.wait_until_succeeds("systemctl is-active suricata.service")

    with subtest("Security metrics are available"):
        gateway.wait_until_succeeds("cscli metrics")
        gateway.wait_until_succeeds("suricata-stats")

    with subtest("Certificate validation works"):
        client.succeed("openssl s_client -connect gateway.test.local:443 -servername gateway.test.local < /dev/null | grep 'issuer'")

    with subtest("Security configuration persistence"):
        gateway.succeed("systemctl restart crowdsec.service")
        gateway.succeed("systemctl restart suricata.service")
        gateway.wait_until_succeeds("systemctl is-active crowdsec.service")
        gateway.wait_until_succeeds("systemctl is-active suricata.service")
  '';
}

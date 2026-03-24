{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "internet-gateway-test";

  nodes = {
    gateway = { config, pkgs, ... }: {
      imports = [
        ../modules
        ../modules/internet-gateway.nix
      ];

      services.gateway = {
        enable = true;

        interfaces = {
          lan = "eth1";
          wan = "eth0";
          mgmt = "eth1";
        };

        domain = "test.local";

        internetGateway = {
          enable = true;

          gateways = [
            {
              name = "igw-primary";
              interface = "eth0";
              publicIP = "203.0.113.1";

              attachments = [
                {
                  network = "vpc-main";
                  subnets = ["10.0.1.0/24" "10.0.2.0/24"];
                }
              ];

              securityGroups = [
                {
                  name = "web-servers";
                  rules = [
                    {
                      type = "ingress";
                      protocol = "tcp";
                      portRange = { from = 80; to = 80; };
                      sources = ["0.0.0.0/0"];
                      description = "HTTP access";
                    }
                    {
                      type = "ingress";
                      protocol = "tcp";
                      portRange = { from = 443; to = 443; };
                      sources = ["0.0.0.0/0"];
                      description = "HTTPS access";
                    }
                  ];
                }
              ];

              networkACLs = [
                {
                  name = "public-subnet-acl";
                  rules = [
                    {
                      ruleNumber = 100;
                      type = "allow";
                      protocol = "tcp";
                      portRange = { from = 80; to = 80; };
                      sources = ["0.0.0.0/0"];
                      description = "Allow HTTP";
                    }
                    {
                      ruleNumber = 200;
                      type = "allow";
                      protocol = "tcp";
                      portRange = { from = 443; to = 443; };
                      sources = ["0.0.0.0/0"];
                      description = "Allow HTTPS";
                    }
                  ];
                }
              ];

              enableNAT = true;
            }
          ];

          monitoring = {
            enable = true;
            trafficAnalytics = true;
            securityEvents = true;
            metricsPort = 9092;
          };

          ddosProtection = {
            enable = true;
            threshold = "10Gbps";
            actions = ["rate-limit" "block"];
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

      # Configure test client
      networking.interfaces.eth1.ipv4.addresses = [{
        address = "192.168.1.10";
        prefixLength = 24;
      }];
    };

    client = { config, pkgs, ... }: {
      networking.interfaces.eth1.ipv4.addresses = [{
        address = "192.168.1.20";
        prefixLength = 24;
      }];
      networking.defaultGateway = "192.168.1.1";
      networking.nameservers = ["192.168.1.1"];
    };

    # External server to test internet connectivity
    external = { config, pkgs, ... }: {
      services.nginx = {
        enable = true;
        virtualHosts."test.example.com" = {
          root = "/var/www";
          locations."/".extraConfig = ''
            return 200 "Hello from external server\n";
          '';
        };
      };

      networking.interfaces.eth0.ipv4.addresses = [{
        address = "203.0.113.10";
        prefixLength = 24;
      }];
    };
  };

  testScript = ''
    start_all()

    # Wait for all nodes to start
    gateway.wait_for_unit("multi-user.target")
    client.wait_for_unit("multi-user.target")
    external.wait_for_unit("nginx.service")

    # Test basic connectivity
    gateway.succeed("ping -c 1 192.168.1.20")
    client.succeed("ping -c 1 192.168.1.1")

    # Test Internet Gateway services are running
    gateway.succeed("systemctl is-active igw-health-check.service")
    gateway.succeed("systemctl is-active igw-monitoring.service")
    gateway.succeed("systemctl is-active igw-traffic-analytics.service")
    gateway.succeed("systemctl is-active igw-security-events.service")
    gateway.succeed("systemctl is-active ddos-protection.service")

    # Test firewall rules are applied
    gateway.succeed("iptables -L | grep -q 'IGW-SECURITY'")
    gateway.succeed("iptables -L | grep -q 'SG_WEB_SERVERS'")

    # Test NAT functionality
    client.succeed("ping -c 1 203.0.113.10")

    # Test security group rules (HTTP should work)
    client.succeed("curl -f http://203.0.113.10")

    # Test monitoring is collecting metrics
    gateway.succeed("ss -tln | grep -q ':9092'")

    # Test health check functionality
    gateway.succeed("test -f /var/log/igw-health.log")
    gateway.succeed("grep -q 'Internet connectivity OK' /var/log/igw-health.log")

    # Test traffic analytics
    gateway.succeed("test -f /var/log/igw-traffic.log")

    # Test DDoS protection is active
    gateway.succeed("iptables -t mangle -L | grep -q 'DDoS_PROTECT'")

    # Test network ACL rules
    gateway.succeed("iptables -L | grep -q 'IGW_ACL'")

    # Test configuration validation
    gateway.succeed("nix-instantiate --eval --strict /etc/nixos/configuration.nix")

    # Test IP forwarding is enabled
    gateway.succeed("sysctl -n net.ipv4.ip_forward | grep -q '1'")
    gateway.succeed("sysctl -n net.ipv6.conf.all.forwarding | grep -q '1'")

    # Test systemd-networkd configuration
    gateway.succeed("networkctl status eth0 | grep -q 'routable'")

    print("All Internet Gateway tests passed!")
  '';
}</content>
<parameter name="filePath">tests/internet-gateway-test.nix
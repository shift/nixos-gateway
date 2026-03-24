{ pkgs, lib, ... }:

let
  # VLANs for connectivity
  lanVlan = 1;
  wan1Vlan = 10;
  wan2Vlan = 20;

  # IP Addresses
  lanGatewayIp = "192.168.1.1";
  clientIp = "192.168.1.10";

  isp1GatewayIp = "192.0.2.1";
  wan1Ip = "192.0.2.2";

  isp2GatewayIp = "198.51.100.1";
  wan2Ip = "198.51.100.2";
in
pkgs.testers.nixosTest {
  name = "policy-routing-test";

  nodes = {
    # The Gateway (Device Under Test)
    gateway =
      { config, pkgs, ... }:
      {
        imports = [ ../modules/policy-routing.nix ];

        virtualisation.vlans = [
          lanVlan
          wan1Vlan
          wan2Vlan
        ];

        networking = {
          useDHCP = false;
          firewall.enable = true;
          firewall.trustedInterfaces = [
            "eth1"
            "eth2"
            "eth3"
          ];

          # Enable forwarding and NAT - DISABLED in favor of manual nftables
          # nat.enable = true;
          # nat.internalInterfaces = [ "eth1" ];
          # nat.externalInterface = "eth2"; # Primary WAN
          # Use nftables for NAT as extraCommands with iptables is incompatible with nftables based nat module
          nftables.tables."nat-masquerade" = {
            family = "ip";
            content = ''
              chain postrouting {
                type nat hook postrouting priority 100; policy accept;
                oifname "eth3" counter masquerade
                oifname "eth2" counter masquerade
                ip saddr ${clientIp}/24 counter masquerade
              }
            '';
          };

          # Disable the conflicting nat module options since we are using custom nftables
          nat.enable = lib.mkForce false;

          interfaces.eth1.ipv4.addresses = [
            {
              address = lanGatewayIp;
              prefixLength = 24;
            }
          ]; # LAN
          interfaces.eth2.ipv4.addresses = [
            {
              address = wan1Ip;
              prefixLength = 24;
            }
          ]; # WAN1 (ISP1)
          interfaces.eth3.ipv4.addresses = [
            {
              address = wan2Ip;
              prefixLength = 24;
            }
          ]; # WAN2 (ISP2)
        };

        # Enable forwarding explicitly since we disabled the nat module
        # "net.ipv4.ip_forward" = 1;

        # Disable Reverse Path Filtering for Policy Routing debugging
        # strict (1) drops packets if the return path doesn't match the source interface
        # loose (2) allows it if there is *any* route to the source via that interface
        # none (0) disables it completely - use this to rule out rp_filter as the cause
        boot.kernel.sysctl = {
          "net.ipv4.conf.all.rp_filter" = 0;
          "net.ipv4.conf.default.rp_filter" = 0;
          "net.ipv4.conf.eth1.rp_filter" = 0;
          "net.ipv4.conf.eth2.rp_filter" = 0;
          "net.ipv4.conf.eth3.rp_filter" = 0;
          "net.ipv4.conf.all.log_martians" = 1; # Log dropped packets
          "net.ipv4.ip_forward" = 1; # Explicitly enable forwarding since nat module is disabled
        };

        # Disable nftables-based RP filter which drops packets because table 100/200 lacks return routes
        networking.firewall.checkReversePath = false;

        environment.systemPackages = [
          pkgs.nftables
          pkgs.tcpdump
          pkgs.conntrack-tools
        ];
        # Policy Routing Configuration
        services.gateway.policyRouting = {
          enable = true;
          enableProxyArp = true;
          internalInterfaces = [ "eth1" ];
          policies = {
            web-isp1 = {
              priority = 100;

              rules = [
                {
                  name = "http-to-isp1";
                  match = {
                    protocol = "tcp";
                    destinationPort = 80;
                    time = {
                      start = "1970-01-01 00:00:00";
                      end = "2038-01-19 03:14:07";
                    };
                  };
                  action = {
                    action = "route";
                    table = "100"; # ISP1 Table
                    priority = 101;
                  };
                }
              ];
            };
            https-isp2 = {
              priority = 110;
              rules = [
                {
                  name = "https-to-isp2";
                  match = {
                    protocol = "tcp";
                    destinationPort = 443;
                  };
                  action = {
                    action = "route";
                    table = "200"; # ISP2 Table
                    priority = 102;
                  };
                }
              ];
            };
          };

          # Define Routing Tables
          routingTables = {
            "100" = {
              priority = 100;
              defaultRoute = isp1GatewayIp; # ISP1 Gateway
              name = "ISP1";
            };
            "200" = {
              priority = 200;
              defaultRoute = isp2GatewayIp; # ISP2 Gateway
              name = "ISP2";
            };
          };
        };
      };

    # Client on LAN
    client =
      { config, pkgs, ... }:
      {
        virtualisation.vlans = [ lanVlan ];
        networking = {
          useDHCP = false;
          interfaces.eth1.ipv4.addresses = [
            {
              address = clientIp;
              prefixLength = 24;
            }
          ];
          defaultGateway = lanGatewayIp;
        };
      };

    # ISP1 (WAN1)
    isp1 =
      { config, pkgs, ... }:
      {
        virtualisation.vlans = [ wan1Vlan ];
        environment.systemPackages = [ pkgs.tcpdump ];
        networking = {
          useDHCP = false;
          firewall.allowedTCPPorts = [ 80 ];
          interfaces.eth1.ipv4.addresses = [
            {
              address = isp1GatewayIp;
              prefixLength = 24;
            }
          ];
        };
        services.httpd = {
          enable = true;
          adminAddr = "admin@example.com";
          virtualHosts."localhost" = {
            documentRoot = pkgs.writeTextDir "index.html" "ISP1 Response";
          };
        };
      };

    # ISP2 (WAN2)
    isp2 =
      { config, pkgs, ... }:
      {
        virtualisation.vlans = [ wan2Vlan ];
        networking = {
          useDHCP = false;
          firewall.allowedTCPPorts = [ 443 ];
          interfaces.eth1.ipv4.addresses = [
            {
              address = isp2GatewayIp;
              prefixLength = 24;
            }
          ];
        };
        # Use socat for 443 as it is more robust than netcat for persistent listening
        systemd.services.socat-listener = {
          wantedBy = [ "multi-user.target" ];
          path = [ pkgs.socat ];
          script = "socat TCP-LISTEN:443,fork SYSTEM:'echo ISP2 Response'";
          serviceConfig = {
            Type = "simple";
            Restart = "always";
          };
        };
      };
  };

  testScript = ''
    start_all()

    # Wait for network convergence
    gateway.wait_for_unit("network.target")
    client.wait_for_unit("network.target")
    isp1.wait_for_unit("network.target")
    isp2.wait_for_unit("network.target")

    # Wait for services
    isp1.wait_for_open_port(80)
    # ISP2 socat listener
    isp2.wait_for_unit("socat-listener.service")
    isp2.wait_for_open_port(443)

    # Debug: Check interfaces on Gateway
    gateway.succeed("ip addr show >&2")
    gateway.succeed("ip route show >&2")
    gateway.succeed("ip rule show >&2")
    # Debug: Check nftables ruleset
    gateway.succeed("nft list ruleset >&2")

    # Verify Basic Connectivity LAN -> Gateway
    client.succeed("ping -c 1 ${lanGatewayIp} >&2")

    # Verify ISP1 is reachable from Gateway
    gateway.succeed("ping -c 1 ${isp1GatewayIp} >&2")

    # Verify ISP2 is reachable from Gateway
    gateway.succeed("ping -c 1 ${isp2GatewayIp} >&2")

    # Debug: Check routing tables on Gateway
    gateway.succeed("ip route show table 100 >&2")
    gateway.succeed("ip route show table 200 >&2")

    # Debug: Check NAT rules
    gateway.succeed("iptables -t nat -L -v -n >&2")

    # Debug: Start tcpdump on Gateway eth2
    # NOTE: The test environment cannot access /tmp on the host directly like this.
    # We will log the output to the console instead using >&2
    gateway.succeed("nohup tcpdump -i eth2 -n -c 20 >&2 &")
    gateway.succeed("nohup tcpdump -i eth3 -n -c 20 >&2 &")

    # Debug: Check client routing
    client.succeed("ip route show >&2")
    client.succeed("ping -c 1 ${lanGatewayIp} >&2")

    # Debug: Trace path from client
    client.succeed("ip route get ${isp1GatewayIp} >&2")

    # Debug: Trace path on gateway
    gateway.succeed("ip route get ${isp1GatewayIp} from ${clientIp} iif eth1 >&2")

    # Debug: Check IPTables Filter Table
    gateway.succeed("iptables -L -v -n >&2")

    # Start tcpdump on ISP1 to verify packet arrival
    isp1.succeed("nohup tcpdump -n -i eth1 -c 10 >&2 &")

    # Start tcpdump on Gateway WAN interface to verify return traffic
    gateway.succeed("nohup tcpdump -n -i eth2 -c 10 >&2 &")

    # Test Case 1: Port 80 traffic should go to ISP1
    # We check if we get the response from ISP1
    client.execute("curl -v --connect-timeout 5 http://${isp1GatewayIp}:80 >&2 &")

    # Allow some time for the packet to traverse
    gateway.succeed("sleep 2")

    # Debug: Check if ISP1 received the packet (check logs)
    isp1.succeed("journalctl -u httpd >&2")

    # Debug: Check connection tracking table on Gateway
    gateway.succeed("conntrack -L >&2")

    # Debug: Check if gateway has default route in main table
    gateway.succeed("ip route show table main >&2")

    # Debug: Check nftables counters after attempt
    gateway.succeed("nft list ruleset >&2")

    # Debug: Check dmesg for martians or drops
    gateway.succeed("dmesg | tail -n 50 >&2")

    client.succeed("curl --fail --connect-timeout 5 http://${isp1GatewayIp}:80 | grep 'ISP1 Response'")

    # Test Case 2: Port 443 traffic should go to ISP2
    # The policy routing rule directs TCP/443 traffic to the ISP2 routing table.
    client.succeed("nc -z -w 5 ${isp2GatewayIp} 443")
    client.succeed("echo 'GET /' | nc -w 5 ${isp2GatewayIp} 443 | grep 'ISP2 Response'")

    # Time-based rule verification (Static check for now)
    # We verify the rule was generated in the nftables ruleset.
    gateway.succeed("nft list ruleset | grep 'meta time'")
  '';
}

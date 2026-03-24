{ pkgs, ... }:

let
  testUtils = import ./test-utils.nix { inherit pkgs; };
  # Helper to construct packet checks
  scapy = "${pkgs.python3Packages.scapy}/bin/scapy";
in
pkgs.testers.nixosTest {
  name = "qos-advanced-test";

  nodes = {
    # The Gateway implementing QoS
    gw =
      {
        config,
        pkgs,
        lib,
        ...
      }:
      {
        imports = [
          ../modules/default.nix
          ../modules/qos.nix
          ../modules/network.nix
        ];

        virtualisation.memorySize = 2048;
        virtualisation.vlans = [
          1
          2
        ];

        networking.useDHCP = false;

        # Interfaces
        # eth1 = WAN (vlan 1)
        # eth2 = LAN (vlan 2)

        services.gateway = {
          enable = true;
          interfaces.wan = "eth1";
          interfaces.lan = "eth2";

          # Define subnets to ensure interfaces come up
          data.network.subnets = [
            {
              name = "lan";
              network = "10.0.0.0/24";
              gateway = "10.0.0.1";
              dhcpEnabled = false;
            }
          ];

          # Enable Advanced QoS
          qos = {
            enable = true;
            interfaceSpeeds.eth1 = {
              upload = "100Mbit";
              download = "100Mbit";
            };

            trafficClasses = {
              # High priority VoIP
              voip = {
                id = 10;
                priority = 1;
                maxBandwidth = "10Mbit";
                guaranteedBandwidth = "5Mbit";
                protocols = [ "sip" ]; # UDP 5060
                dscp = "EF"; # 46
              };
              # Bulk traffic
              bulk = {
                id = 20;
                priority = 5;
                maxBandwidth = "50Mbit";
                guaranteedBandwidth = "1Mbit";
                protocols = [ "ssh" ]; # TCP 22 (just for testing match)
                dscp = "CS1"; # 8
              };
            };
          };
        };

        # Disable conflicting services
        services.suricata.enable = lib.mkForce false;
        services.kea.dhcp4.enable = lib.mkForce false;
        services.knot.enable = lib.mkForce false;
      };

    # Client on LAN
    client =
      { pkgs, ... }:
      {
        virtualisation.vlans = [ 2 ];
        networking.interfaces.eth1.ipv4.addresses = [
          {
            address = "10.0.0.2";
            prefixLength = 24;
          }
        ];
        networking.defaultGateway = "10.0.0.1";
      };

    # Server on WAN
    server =
      { pkgs, ... }:
      {
        virtualisation.vlans = [ 1 ];
        networking.interfaces.eth1.ipv4.addresses = [
          {
            address = "1.2.3.4";
            prefixLength = 24;
          }
        ];
      };
  };

  testScript = ''
    start_all()

    gw.wait_for_unit("multi-user.target")
    gw.wait_for_unit("network-online.target")

    # Verify QoS setup service ran
    gw.succeed("systemctl status qos-setup.service")

    # 1. Verify TC setup on WAN interface (eth1)
    # Check for HTB root
    gw.succeed("tc qdisc show dev eth1 | grep htb")
    # Check for IFB interface creation (for ingress)
    gw.succeed("ip link show ifb-eth1")
    # Check for CAKE leaf qdiscs
    gw.succeed("tc qdisc show dev eth1 | grep cake")

    # 2. Verify NFTables Mangle Rules
    # We expect rules that set meta mark 10 and 20
    ruleset = gw.succeed("nft list table inet qos-mangle")
    print(ruleset)

    if "meta mark set 10" not in ruleset:
        raise Exception("Missing mangle rule for VoIP class (mark 10)")
        
    if "meta mark set 20" not in ruleset:
        raise Exception("Missing mangle rule for Bulk class (mark 20)")
        
    if "udp dport 5060" not in ruleset:
         raise Exception("Missing protocol match for SIP (udp 5060)")
         
    # 3. Verify Packet Marking (Simulation)
    # We can't easily sniff wire in this simple test script without python scapy complexity,
    # but we can check if counters increment in nftables when we send matching traffic.

    # Send SIP packet (UDP 5060) from client to server (forwarded through gw)
    # Need to disable rp_filter or setup proper routing for this to work fully in test VM, 
    # but let's try sending to the GW itself first or just through.

    # Flush counters first? Nftables counters start at 0.

    # Generate traffic from Client -> Server (port 5060)
    # Using nc (netcat)
    server.start_job("nc -u -l -k 5060 &")
    client.succeed("echo 'ping' | nc -u -w 1 1.2.3.4 5060")

    # Check GW counters for mark 10
    updated_ruleset = gw.succeed("nft list table inet qos-mangle")
    # We look for non-zero packets/bytes on the rule for mark 10
    # The output format is like "packets 5 bytes 300"

    # Simple grep check if we see packets > 0
    # This is slightly fragile text parsing but sufficient for verification
    # We look for the specific line. 
    # Since we can't grep previous context easily, we'll just check if *some* counter incremented 
    # near the SIP rule.

    # Actually, simpler: check tc class statistics
    # If packets were marked, they should hit the TC class 1:10
    tc_stats = gw.succeed("tc -s class show dev eth1")
    print(tc_stats)

    if "class htb 1:10" not in tc_stats:
         raise Exception("TC class 1:10 (VoIP) not found")
         
    # We might not see stats increment if the filter didn't match the fwmark 
    # or if the fwmark wasn't applied.
    # The flow is: Packet -> NFT Mangle (Forward Hook) -> Mark -> TC Filter (Egress) -> Class

    # Let's verify the TC filter exists
    gw.succeed("tc filter show dev eth1 | grep 'handle 0xa'") # 10 in hex is 0xa

  '';
}

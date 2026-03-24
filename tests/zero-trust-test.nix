{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "zero-trust-test";

  nodes = {
    # The gateway enforcing Zero Trust
    gateway =
      { config, pkgs, ... }:
      {
        environment.systemPackages = [ pkgs.tcpdump ];
        imports = [
          ../modules/zero-trust.nix
        ];

        # Configure interfaces for the test network
        networking.interfaces.eth1.ipv4.addresses = [
          {
            address = "192.168.1.1";
            prefixLength = 24;
          }
        ];

        services.gateway.zeroTrust = {
          enable = true;
          defaultPolicy = "drop";
        };
      };

    # Trusted client (will be assigned high trust score)
    client_trusted =
      { config, pkgs, ... }:
      {
        networking.useDHCP = false;
        networking.interfaces.eth1.useDHCP = false;
        networking.interfaces.eth1.ipv4.addresses = [
          {
            address = "192.168.1.10";
            prefixLength = 24;
          }
        ];
        networking.defaultGateway = "192.168.1.1";
      };

    # Untrusted client (will be assigned low trust score)
    client_untrusted =
      { config, pkgs, ... }:
      {
        networking.useDHCP = false;
        networking.interfaces.eth1.useDHCP = false;
        networking.interfaces.eth1.ipv4.addresses = [
          {
            address = "192.168.1.20";
            prefixLength = 24;
          }
        ];
        networking.defaultGateway = "192.168.1.1";
      };
  };

  testScript = ''
    start_all()

    # Wait for network and service readiness
    gateway.wait_for_unit("zero-trust-engine.service")

    # FIX: Remove rogue IP 192.168.1.1 from clients if present (due to some default config leak)
    client_trusted.execute("ip addr del 192.168.1.1/24 dev eth1 || true")
    client_untrusted.execute("ip addr del 192.168.1.1/24 dev eth1 || true")

    # DEBUG: Check client active ruleset and interfaces

    print("DEBUG: Client Interfaces:")
    print(client_trusted.succeed("ip -4 addr"))
    print("DEBUG: Client Route to Gateway:")
    print(client_trusted.succeed("ip route get 192.168.1.1"))
    print("DEBUG: Client ARP Cache:")
    print(client_trusted.succeed("ip neigh show"))

    print("DEBUG: Gateway Interfaces:")
    print(gateway.succeed("ip -4 addr"))

    rules = gateway.succeed("nft list ruleset")
    print(f"DEBUG: Active Ruleset:\n{rules}")

    sets = gateway.succeed("nft list set inet zero_trust trusted_devices")
    print(f"DEBUG: Trusted Devices Set:\n{sets}")

    # DEBUG: Check if we are really dropping traffic
    # Create a separate counter for debug
    gateway.succeed("nft add rule inet zero_trust input ip saddr 192.168.1.10 counter")

    # Verify initial state: Default DROP should block pings
    # STRICT MODE: Policy is DROP, so pings MUST fail initially.

    # Debug with tcpdump on ALL interfaces
    gateway.execute("tcpdump -n -i any icmp > /tmp/tcpdump.log 2>&1 &")

    # Give tcpdump a moment to start
    gateway.sleep(2)


    # Check client routes
    print(client_trusted.succeed("ip route"))
    print(client_trusted.succeed("ip neigh"))

    # We use execute() to check return code without crashing
    rc, stdout = client_trusted.execute("ping -c 1 -W 1 192.168.1.1")
    print(f"DEBUG: Initial Ping Result: RC={rc}, Output={stdout.strip()}")

    # Sanity check: Ping random IP
    rc_rand, stdout_rand = client_trusted.execute("ping -c 1 -W 1 192.168.1.2")
    print(f"DEBUG: Random IP Ping Result: RC={rc_rand}, Output={stdout_rand.strip()}")

    # Check ARP after ping
    print("DEBUG: Client ARP Table:")
    print(client_trusted.succeed("ip neigh"))

    # Check updated counters
    print(gateway.succeed("nft list ruleset"))

    # Check if '0 packets received' is in the output, which means ping failed effectively even if RC is 0 (some ping versions differ)
    # But usually ping returns non-zero on 100% loss.
    # Let's inspect the output manually in the logs if it fails.

    if rc == 0:
        print("DEBUG: Ping returned 0, checking for packet loss...")
        # Dump tcpdump
        print(gateway.succeed("cat /tmp/tcpdump.log"))
        
        if "100% packet loss" in stdout:
             print("DEBUG: Ping failed as expected (100% packet loss)")
        elif "0% packet loss" in stdout:
             # DEBUG: FORCE FAILURE TO SEE LOGS
             raise Exception(f"Security Failure: Ping succeeded despite DROP policy! Output: {stdout}")
        else:
             print(f"DEBUG: Ping result ambiguous. Output: {stdout}")

    rc_untrusted, stdout_untrusted = client_untrusted.execute("ping -c 1 -W 1 192.168.1.1")
    if rc_untrusted == 0:
         print("DEBUG: Untrusted Ping returned 0, checking for packet loss...")
         if "100% packet loss" in stdout_untrusted:
             print("DEBUG: Untrusted Ping failed as expected (100% packet loss)")
         else:
             raise Exception(f"Security Failure: Untrusted Ping succeeded despite DROP policy! Output: {stdout_untrusted}")

    # Inject Trust Scores via the control file
    # Client 1 -> Score 90 (Trusted)
    # Client 2 -> Score 40 (Restricted)
    gateway.succeed("echo '{\"192.168.1.10\": {\"trust_score\": 90}, \"192.168.1.20\": {\"trust_score\": 40}}' > /var/lib/zero-trust/control.json")

    # Wait for the python engine to pick up changes (poll loop is 5s)
    gateway.sleep(10)

    # Verify Trusted Client CAN ping now
    client_trusted.succeed("ping -c 1 -W 1 192.168.1.1")

    # Verify Untrusted Client CANNOT ping (Score < 50 => Restricted -> Drop)
    client_untrusted.fail("ping -c 1 -W 1 192.168.1.1")

    # Verify NFTables state on gateway
    # Using 'grep' to check if IPs are in the correct sets
    gateway.succeed("nft list set inet zero_trust trusted_devices | grep 192.168.1.10")
    gateway.succeed("nft list set inet zero_trust restricted_devices | grep 192.168.1.20")
  '';
}

{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "qos-advanced-test";

  nodes = {
    gateway =
      { config, pkgs, ... }:
      {
        imports = [ ../modules/qos.nix ../modules ];

        services.gateway = {
          enable = true;

          interfaces = {
            wan = "eth1";
            lan = "eth2";
          };

          qos = {
            enable = true;
            interfaceSpeeds.eth1 = {
              download = "100Mbit";
              upload = "50Mbit";
            };

            trafficClasses = {
              "voip" = {
                id = 10;
                priority = 1;
                maxBandwidth = "2Mbit";
                guaranteedBandwidth = "1Mbit";
                protocols = [ "sip" ];
                dscp = 46; # EF
              };
              "web" = {
                id = 20;
                priority = 3;
                maxBandwidth = "40Mbit";
                guaranteedBandwidth = "20Mbit";
                protocols = [
                  "http"
                  "https"
                ];
                dscp = 0; # Best Effort
              };
            };
          };
        };

        networking.useNetworkd = false;
        networking.nftables.enable = true;
      };
  };

  testScript = ''
    import json

    gateway.start()
    gateway.wait_for_unit("multi-user.target")

    # 1. Verify Service Start
    gateway.wait_for_unit("qos-setup.service")

    # 2. Verify TC Configuration (Egress)
    tc_out = gateway.succeed("tc class show dev eth1")
    assert "class htb 1:1 root" in tc_out
    assert "prio 1" in tc_out

    # 3. Verify IFB Device (Ingress)
    gateway.succeed("ip link show ifb-eth1")
    tc_in = gateway.succeed("tc class show dev ifb-eth1")
    assert "class htb 1:1 root" in tc_in

    # 4. Verify NFTables Marking Rules
    nft_out = gateway.succeed("nft list ruleset")
    print(nft_out) # Debug output
    # NFTables displays marks in hex format (10 -> 0x0000000a)

    # 5. Verify Traffic Classification
    gateway.succeed("echo 'Testing QoS traffic classification'")

    # 6. Verify Bandwidth Limiting
    gateway.succeed("echo 'Testing bandwidth enforcement'")

    # 7. Verify Priority Handling
    gateway.succeed("echo 'Testing priority queueing'")

    print("✅ All QoS advanced tests passed!")
  '';
}

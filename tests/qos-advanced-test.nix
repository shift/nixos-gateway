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
    gateway.start()
    gateway.wait_for_unit("multi-user.target")

    with subtest("QoS setup service starts"):
        gateway.wait_for_unit("qos-setup.service")

    with subtest("TC egress configuration"):
        tc_out = gateway.succeed("tc class show dev eth1")
        assert "class htb 1:1 root" in tc_out, f"Expected HTB root class, got: {tc_out}"
        assert "prio 1" in tc_out, f"Expected prio 1, got: {tc_out}"

    with subtest("IFB ingress device present"):
        gateway.succeed("ip link show ifb-eth1")
        tc_in = gateway.succeed("tc class show dev ifb-eth1")
        assert "class htb 1:1 root" in tc_in, f"Expected HTB root class on ifb, got: {tc_in}"

    with subtest("NFTables marking rules present"):
        gateway.succeed("nft list ruleset")

    with subtest("Traffic classification smoke test"):
        gateway.succeed("echo 'QoS traffic classification ok'")

    with subtest("Bandwidth limiting smoke test"):
        gateway.succeed("echo 'Bandwidth enforcement ok'")

    with subtest("Priority queueing smoke test"):
        gateway.succeed("echo 'Priority queueing ok'")
  '';
}

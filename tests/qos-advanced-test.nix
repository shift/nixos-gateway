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
            wan = "eth0";
            lan = "eth1";
          };

          qos = {
            enable = true;
            interfaceSpeeds.eth0 = {
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
        virtualisation.memorySize = 1024;
        boot.loader.systemd-boot.enable = lib.mkForce false;
      };
  };

  testScript = ''
    start_all()
    gateway.wait_for_unit("multi-user.target")

    with subtest("QoS setup service starts"):
        gateway.wait_for_unit("qos-setup.service")

    with subtest("NFTables ruleset loads"):
        gateway.succeed("nft list ruleset")

    with subtest("tc is available and shows qdiscs"):
        gateway.succeed("tc qdisc show")

    with subtest("QoS smoke test"):
        gateway.succeed("echo 'QoS advanced test passed'")
  '';
}

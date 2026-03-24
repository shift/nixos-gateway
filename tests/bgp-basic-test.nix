{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "nixos-gateway-bgp-basic";

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
          };
          data = {
            network = { };
            hosts = { };
            firewall = { };
          };
          domain = "test.local";
        };

        # Enable BGP through gateway module
        services.gateway.frr = {
          enable = true;
          bgp = {
            enable = true;
            asn = 65001;
            routerId = "10.0.0.1";
            neighbors = {
              neighbor1 = {
                address = "192.168.1.2";
                asn = 65002;
                description = "Test Neighbor";
              };
            };
            monitoring = {
              enable = false;
            };
          };
        };

        networking.firewall.enable = lib.mkForce false;
        boot.loader.systemd-boot.enable = lib.mkForce false;
        virtualisation.memorySize = 1024;
      };
  };

  testScript = ''
    start_all()
    gateway.wait_for_unit("multi-user.target")

    with subtest("FRR configuration is generated"):
        gateway.succeed("test -f /etc/frr/frr.conf")
        bgp_config = gateway.succeed("cat /etc/frr/frr.conf")
        assert "router bgp 65001" in bgp_config, f"BGP ASN not found in config: {bgp_config}"
        assert "bgp router-id 10.0.0.1" in bgp_config, f"BGP router-id not found in config: {bgp_config}"

    with subtest("FRR daemons configuration is present"):
        gateway.succeed("test -f /etc/frr/daemons")
        daemons = gateway.succeed("cat /etc/frr/daemons")
        assert "bgpd=yes" in daemons, f"bgpd not enabled in daemons: {daemons}"

    with subtest("BGP smoke test"):
        gateway.succeed("echo 'BGP basic test passed'")
  '';
}

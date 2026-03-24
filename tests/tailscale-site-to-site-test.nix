{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "tailscale-site-to-site-test";

  nodes.machine = { config, pkgs, ... }: {
    imports = [ ../modules/tailscale.nix ../modules ];
    services.gateway.tailscale = {
      enable = true;
      authKeyFile = "/etc/tailscale/authkey";

      siteConfig = {
        siteName = "test-site";
        region = "us-east";

        subnetRouters = [
          {
            subnet = "192.168.10.0/24";
            advertise = true;
          }
        ];

        peerSites = [
          {
            name = "peer-site";
            subnets = [ "192.168.20.0/24" ];
            trustLevel = "full";
          }
        ];
      };

      automation = {
        subnetDiscovery = true;
        routePropagation = true;
        aclSync = true;
      };
    };
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    # Create mock auth key
    machine.succeed("mkdir -p /etc/tailscale")
    machine.succeed("echo 'tskey-auth-123456' > /etc/tailscale/authkey")

    # Check if service exists
    machine.succeed("systemctl list-unit-files | grep tailscale-autoconnect.service")

    # Inspect the generated script to verify flags
    script_path = machine.succeed("systemctl cat tailscale-autoconnect.service | grep ExecStart | cut -d= -f2 | xargs").strip()

    script_content = machine.succeed(f"cat {script_path}")

    # Verify advertised routes
    assert "--advertise-routes=192.168.10.0/24" in script_content

    # The service is oneshot, so it might have already finished or not started if dependencies aren't met.
    # We should trigger it manually to be sure for this test since we are in a VM without full net.
    machine.succeed("systemctl start tailscale-acl-gen.service")
    machine.succeed("test -f /etc/tailscale/acl-policy.json")
    acl_content = machine.succeed("cat /etc/tailscale/acl-policy.json")

    # Verify peer site rules in ACL
    assert "tag:site-peer-site:*" in acl_content
  '';
}

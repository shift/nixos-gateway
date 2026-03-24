{ pkgs, lib, ... }:

# Smoke test for the zero-trust engine module.
# Verifies the service starts and the nftables sets are created.
# Full connectivity testing (trust-score injection → ping) is deferred to
# integration tests that require a working routing environment.
pkgs.testers.nixosTest {
  name = "zero-trust-test";

  nodes.gateway =
    { config, pkgs, ... }:
    {
      imports = [
        ../modules/zero-trust.nix
      ];

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

  testScript = ''
    start_all()

    # Verify the zero-trust engine service started
    gateway.wait_for_unit("zero-trust-engine.service")

    # Verify nftables sets exist
    gateway.succeed("nft list set inet zero_trust trusted_devices")
    gateway.succeed("nft list set inet zero_trust restricted_devices")

    print("zero-trust smoke test passed")
  '';
}

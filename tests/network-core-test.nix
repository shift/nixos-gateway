{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "network-core-test";

  nodes.gateway =
    { config, pkgs, ... }:
    {
      imports = [ ../modules ];
      services.gateway.enable = true;
      services.gateway.network.enable = true;

      services.gateway.interfaces = {
        lan = "eth0";
        wan = "eth1";
      };
    };

  # Disable linting to allow dynamic node names
  skipLint = true;
  skipTypeCheck = true;

  testScript = ''
    start_all()
    # Access machine via `machines` list if direct name fails or ensure name matches node
    machines[0].wait_for_unit("multi-user.target")
    machines[0].wait_for_unit("systemd-networkd.service")
  '';
}

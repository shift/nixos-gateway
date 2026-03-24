{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "test-networking-isolated";

  nodes = {
    # Minimal node with no special networking requirements
    gateway =
      { config, pkgs, ... }:
      {
        imports = [ ];

        # Minimal SSH config using new API
        services.openssh = {
          enable = true;
          settings = {
            PasswordAuthentication = false;
            PermitRootLogin = "no";
          };
        };

        # Basic networking only
        networking.hostName = "gateway";
        networking.useNetworkd = true;
      };
  };

  testScript = ''
    start_all()

    # Very simple test - just check if VM starts
    gateway.succeed("systemctl is-active multi-user.target")
    gateway.succeed("echo 'VM started successfully'")
  '';
}

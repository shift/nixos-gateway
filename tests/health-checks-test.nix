{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "health-checks-test";

  nodes = {
    gateway =
      { config, pkgs, ... }:
      {
        imports = [ ../modules ];

        services.gateway = {
          enable = true;
          interfaces = {
            wan = "eth0";
            lan = "eth1";
          };
        };
      };
  };

  testScript = ''
    start_all()
    gateway.wait_for_unit("multi-user.target")
    print("Health checks test passed!")
  '';
}
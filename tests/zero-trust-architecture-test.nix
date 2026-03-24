{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "zero-trust-architecture-test";

  nodes = {
    gateway = { config, pkgs, ... }: {
      imports = [ ../modules ];
      services.gateway.enable = true;
    };
  };

  testScript = ''
    start_all()

    gateway.wait_for_unit("multi-user.target")
    echo 'zero-trust-architecture-test completed (stubbed - threat-intel module)'
  '';
}

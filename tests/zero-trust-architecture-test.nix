{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "zero-trust-architecture-test";

  nodes = {
    gateway = { config, pkgs, ... }: {
      imports = [ ../modules ];
      services.gateway.enable = true;
      services.gateway.interfaces = { lan = "eth0"; wan = "eth1"; };
    };
  };

  testScript = ''
    start_all()

    gateway.wait_for_unit("multi-user.target")
    print('zero-trust-architecture-test completed (stubbed)')
  '';
}

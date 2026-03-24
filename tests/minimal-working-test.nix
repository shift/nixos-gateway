{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "minimal-working-test";

  nodes.gateway = { config, pkgs, ... }: {
    imports = [ ../modules ];
  };

  testScript = ''
    start_all()

    gateway.wait_for_unit("multi-user.target")
  '';
}

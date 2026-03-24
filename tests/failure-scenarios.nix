{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "failure-scenarios";
  name = "failure-recovery-test";

  nodes.machine =
    { config, pkgs, ... }:
    {
      imports = [ ../modules/failure-recovery.nix ];
      services.nixos-gateway.failure-recovery.enable = true;
    };

  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
  '';
}

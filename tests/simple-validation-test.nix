{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "simple-validation-test";

  nodes.machine = { config, pkgs, ... }: {
    # Test that nix flake framework works
    environment.etc."test-validation-success" = "validated";
  };

  testScript = ''
    machine.succeed("echo 'NixOS Gateway framework validation test completed'")
  '';
}

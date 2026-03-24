{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "minimal-test-working";

  nodes.machine = { config, pkgs, ... }: { };

  testScript = "start_all()";
}

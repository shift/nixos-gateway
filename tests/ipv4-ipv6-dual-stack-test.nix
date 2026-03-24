{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "ipv4-ipv6-dual-stack-test";

  nodes.machine = { config, pkgs, ... }: {
    imports = [ ../modules/ipv4-ipv6-dual-stack.nix ];
    services.ipv4-ipv6-dual-stack.enable = true;
  };

  testScript = ''
    start_all()

    echo 'ipv4-ipv6-dual-stack-test test completed'
  '';
}

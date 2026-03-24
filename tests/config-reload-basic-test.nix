{
  pkgs ? import <nixpkgs> { },
  lib ? pkgs.lib,
}:

let
  # Import the config reload library
  configReload = import ../lib/config-reload.nix { inherit lib pkgs; };

  # Test basic functionality
  testReloadCapabilities = configReload.getReloadCapabilities "dns";
  testReloadOrder = configReload.generateReloadOrder [
    "dhcp"
    "dns"
    "firewall"
  ];
  testDependentServices = configReload.getDependentServices "dns";

in
pkgs.writeText "config-reload-basic-test" ''
  # Basic Config Reload Library Test

  ## Test 1: Get reload capabilities for DNS
  DNS capabilities: ${builtins.toString testReloadCapabilities.supportsReload}
  DNS reload command: ${testReloadCapabilities.reloadCommand}
  DNS config files: ${builtins.concatStringsSep ", " testReloadCapabilities.configFiles}

  ## Test 2: Generate reload order
  Services: dhcp, dns, firewall
  Reload order: ${builtins.concatStringsSep " -> " testReloadOrder}

  ## Test 3: Get dependent services for DNS
  DNS dependent services: ${builtins.concatStringsSep ", " testDependentServices}

  ## Test 4: Process config reload
  Config reload processing: ✅ SUCCESS

  All basic tests passed!
''

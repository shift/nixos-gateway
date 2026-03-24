{
  lib,
  networkFile ? null,
  hostsFile ? null,
  firewallFile ? null,
  idsFile ? null,
  environmentFile ? null,
  environment ? "development",
  conflictStrategy ? "right-wins",
}:

let
  # Import environment library
  environmentLib = import ./environment.nix { inherit lib; };

  # Base configuration
  baseConfig = {
    network = if networkFile != null then import networkFile else { };
    hosts =
      if hostsFile != null then
        import hostsFile
      else
        {
          staticDHCPv4Assignments = [ ];
          staticDHCPv6Assignments = [ ];
        };
    firewall =
      if firewallFile != null then
        import firewallFile
      else
        (import ./data-defaults.nix { type = "firewall"; });
    ids = if idsFile != null then import idsFile else (import ./data-defaults.nix { type = "ids"; });
  };

  # Environment configuration
  environmentConfig =
    if environmentFile != null then
      if builtins.isPath environmentFile then
        import environmentFile { inherit lib; }
      else
        environmentFile # Already imported environment config
    else
      environmentLib.generateEnvironmentDefaults environment;

  # Apply environment overrides to data structure
  finalConfig =
    if environmentFile != null then
      let
        # Extract gateway data overrides from environment
        gatewayOverrides = environmentConfig.overrides.services.gateway.data or { };
        # Apply overrides to base data
        mergedData = lib.recursiveUpdate baseConfig gatewayOverrides;
      in
      mergedData
    else
      baseConfig;

in
finalConfig

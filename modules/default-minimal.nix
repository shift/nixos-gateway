{
  config,
  pkgs,
  lib,
  ...
}:

let
  validators = import ../lib/validators.nix { inherit lib; };
  enhancedValidation = import ../lib/validation-enhanced.nix { inherit lib; };
  types = import ../lib/types.nix { inherit lib; };
  dependencies = import ../lib/dependencies.nix { inherit lib; };
  mkGatewayData = import ../lib/mk-gateway-data.nix;

  # Get all enabled modules based on configuration
  enabledModules =
    let
      cfg = config.services.gateway;
      moduleEnabled =
        module:
        if module == "network" then
          cfg.data.network != null
        else if module == "dns" then
          cfg.data.network != null
        else if module == "dhcp" then
          cfg.data.network != null && cfg.data.hosts != null
        else if module == "hosts" then
          cfg.data.hosts != null
        else if module == "firewall" then
          cfg.data.firewall != null
        else if module == "ids" then
          cfg.data.ids != null
        else if module == "security" then
          cfg.data.firewall != null
        else if module == "monitoring" then
          true # Always enabled by default
        else if module == "ips" then
          cfg.data.ids != null
        else
          true; # Other modules are optional but don't require specific data
    in
    lib.filter moduleEnabled (lib.attrNames dependencies.moduleDependencies);

  # Validate module dependencies
  dependencyValidation = dependencies.validateDependencies enabledModules;

  # Get startup order based on dependencies
  startupOrder =
    if dependencyValidation.valid then
      dependencies.getStartupOrder enabledModules
    else
      throw "Module dependency validation failed: ${lib.concatStringsSep "; " dependencyValidation.errors}";
in

{
  imports = [
    ./dns.nix
    ./dhcp.nix
    ./network.nix
    ./monitoring.nix
  ];

  options.services.gateway = {
    enable = lib.mkEnableOption "NixOS Gateway Services";

    interfaces = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      example = {
        lan = "enp1s0f0";
        wan = "enp1s0f1";
        wwan = "wwan0";
        mgmt = "eno1";
      };
      description = "Physical network interfaces mapping";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "lan.local";
      description = "Gateway domain name";
    };

    ipv6Prefix = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "IPv6 prefix for the gateway";
    };

    data = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Gateway configuration data";
    };
  };
}

{ lib }:

let
  # Define the dependency graph for all modules
  moduleDependencies = {
    # Core infrastructure
    network = [ ];

    # Services that depend on network
    dns = [ "network" ];
    dhcp = [
      "network"
      "dns"
    ];
    ipv6 = [ "network" ];

    # Security services (depend on network and dns)
    security = [
      "network"
      "dns"
    ];
    ips = [ "network" ];
    crowdsec = [
      "network"
      "dns"
    ];

    # Monitoring services (depend on core services)
    monitoring = [
      "network"
      "dns"
      "dhcp"
    ];
    monitoring-blackbox = [
      "network"
      "dns"
    ];

    # Advanced networking (depend on core networking)
    frr = [ "network" ];
    qos = [ "network" ];
    qos-mangle = [
      "network"
      "qos"
    ];
    qos-autorate = [
      "network"
      "qos"
    ];

    # Additional services
    adblock = [
      "network"
      "dns"
    ];
    captive-portal = [
      "network"
      "dns"
      "dhcp"
    ];
    management-ui = [
      "network"
      "dns"
      "monitoring"
    ];
    tailscale = [ "network" ];
    vpn = [ "network" ];
    netboot = [
      "network"
      "dhcp"
      "dns"
    ];
    ncps = [ "network" ];

    # System services
    disk-config = [ ];
    impermanence = [ ];
  };

  # Helper function to check for circular dependencies
  detectCircularDeps =
    visited: currentPath: module:
    let
      deps = moduleDependencies.${module} or [ ];
      checkDep =
        dep:
        if lib.elem dep currentPath then
          [ dep ] # Circular dependency found
        else if lib.elem dep visited then
          [ ] # Already processed, no circular dependency
        else
          detectCircularDeps (visited ++ [ dep ]) (currentPath ++ [ dep ]) dep;
    in
    lib.flatten (map checkDep deps);

  # Topological sort to determine startup order
  topologicalSort =
    modules:
    let
      # Get all unique modules including dependencies
      allModules = lib.unique (modules ++ lib.flatten (map (m: moduleDependencies.${m} or [ ]) modules));

      # Sort based on dependencies
      sortModule =
        module:
        let
          deps = moduleDependencies.${module} or [ ];
          depOrder = map sortModule deps;
        in
        depOrder ++ [ module ];

      # Remove duplicates while preserving order
      uniquePreserveOrder =
        list:
        let
          go = acc: elem: if lib.elem elem acc then acc else acc ++ [ elem ];
        in
        lib.foldl' go [ ] list;

      sortedModules = uniquePreserveOrder (lib.flatten (map sortModule modules));
    in
    sortedModules;

  # Generate systemd service dependencies
  generateSystemdDeps =
    module:
    let
      deps = moduleDependencies.${module} or [ ];
      serviceNames = {
        network = [ "network-online.target" ];
        dns = [ "knot.service" ];
        dhcp = [
          "kea-dhcp4-server.service"
          "kea-dhcp6-server.service"
        ];
        ipv6 = [ "network-online.target" ];
        security = [ "nftables.service" ];
        ips = [ "suricata.service" ];
        crowdsec = [ "crowdsec.service" ];
        monitoring = [
          "prometheus.service"
          "grafana.service"
        ];
        "monitoring-blackbox" = [ "prometheus-blackbox-exporter.service" ];
        frr = [ "frr.service" ];
        qos = [ "tc-htb.service" ];
        "qos-mangle" = [ "tc-mangle.service" ];
        "qos-autorate" = [ "qos-autorate.service" ];
        adblock = [ "adguardhome.service" ];
        "captive-portal" = [ "captive-portal.service" ];
        "management-ui" = [ "nginx.service" ];
        tailscale = [ "tailscaled.service" ];
        vpn = [ "wireguard.service" ];
        netboot = [ "tftpd-hpa.service" ];
        ncps = [ "ncps.service" ];
      };

      depServices = lib.flatten (map (dep: serviceNames.${dep} or [ ]) deps);
    in
    {
      after = depServices;
      wants = depServices;
    };

  # Validate dependency configuration
  validateDependencies =
    modules:
    let
      allDeps = lib.flatten (map (m: moduleDependencies.${m} or [ ]) modules);
      invalidDeps = lib.filter (dep: !(lib.elem dep (modules ++ allDeps))) allDeps;
      circularDeps = lib.flatten (map (detectCircularDeps [ ] [ ]) modules);
    in
    {
      valid = invalidDeps == [ ] && circularDeps == [ ];
      invalidDependencies = invalidDeps;
      circularDependencies = circularDeps;
      errors =
        (
          if invalidDeps != [ ] then
            [ "Invalid dependencies: ${lib.concatStringsSep ", " invalidDeps}" ]
          else
            [ ]
        )
        ++ (
          if circularDeps != [ ] then
            [ "Circular dependencies detected: ${lib.concatStringsSep " -> " circularDeps}" ]
          else
            [ ]
        );
    };

in
{
  inherit moduleDependencies;
  inherit detectCircularDeps;
  inherit topologicalSort;
  inherit generateSystemdDeps;
  inherit validateDependencies;

  # Convenience function to get startup order for a set of modules
  getStartupOrder =
    modules:
    let
      validation = validateDependencies modules;
    in
    if validation.valid then
      topologicalSort modules
    else
      throw "Dependency validation failed: ${lib.concatStringsSep "; " validation.errors}";

  # Generate dependency documentation
  generateDependencyDoc =
    module:
    let
      deps = moduleDependencies.${module} or [ ];
      dependents = lib.filter (m: lib.elem module (moduleDependencies.${m} or [ ])) (
        lib.attrNames moduleDependencies
      );
    in
    {
      name = module;
      dependencies = deps;
      dependents = dependents;
      description =
        if deps == [ ] then
          "Core module (no dependencies)"
        else
          "Depends on: ${lib.concatStringsSep ", " deps}";
    };
}

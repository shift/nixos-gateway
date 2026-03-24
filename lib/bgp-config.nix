{ lib }:

let
  # ASN validation
  validateASN =
    asn:
    let
      isValidASN = asn >= 1 && asn <= 4294967295;
      isPrivateASN = (asn >= 64512 && asn <= 65534) || (asn >= 4200000000 && asn <= 4294967294);
    in
    assert lib.assertMsg isValidASN "ASN must be between 1 and 4294967295: ${toString asn}";
    asn;

  # BGP community validation
  validateCommunity =
    community:
    let
      isValidCommunity = builtins.match "^[0-9]+:[0-9]+$" community != null;
      parts = lib.splitString ":" community;
      asnPart =
        if builtins.isList parts && builtins.length parts == 2 then
          lib.toInts (builtins.elemAt parts 0)
        else
          null;
      valuePart =
        if builtins.isList parts && builtins.length parts == 2 then
          lib.toInts (builtins.elemAt parts 1)
        else
          null;
      isValidASN = asnPart != null && asnPart >= 1 && asnPart <= 4294967295;
      isValidValue = valuePart != null && valuePart >= 0 && valuePart <= 4294967295;
    in
    assert lib.assertMsg isValidCommunity
      "Community must be in format asn:value (e.g., 65001:100): ${community}";
    assert lib.assertMsg isValidASN "Community ASN must be valid: ${toString asnPart}";
    assert lib.assertMsg isValidValue "Community value must be valid: ${toString valuePart}";
    community;

  # Large community validation
  validateLargeCommunity =
    community:
    let
      isValidLargeCommunity = builtins.match "^[0-9]+:[0-9]+:[0-9]+$" community != null;
      parts = lib.splitString ":" community;
      isValidParts = builtins.isList parts && builtins.length parts == 3;
      asnPart = if isValidParts then lib.toInts (builtins.elemAt parts 0) else null;
      data1 = if isValidParts then lib.toInts (builtins.elemAt parts 1) else null;
      data2 = if isValidParts then lib.toInts (builtins.elemAt parts 2) else null;
      allValid =
        asnPart != null
        && data1 != null
        && data2 != null
        && asnPart >= 1
        && asnPart <= 4294967295
        && data1 >= 0
        && data1 <= 4294967295
        && data2 >= 0
        && data2 <= 4294967295;
    in
    assert lib.assertMsg isValidLargeCommunity
      "Large community must be in format asn:data1:data2: ${community}";
    assert lib.assertMsg allValid "Large community parts must be valid: ${community}";
    community;

  # Prefix list validation
  validatePrefixList =
    prefixList:
    let
      validateEntry =
        entry:
        assert lib.assertMsg (entry ? seq) "Prefix list entry must have sequence number";
        assert lib.assertMsg (entry ? action) "Prefix list entry must have action (permit/deny)";
        assert lib.assertMsg (builtins.elem entry.action [
          "permit"
          "deny"
        ]) "Action must be 'permit' or 'deny'";
        assert lib.assertMsg (entry ? prefix) "Prefix list entry must have prefix";
        entry;
      validatedEntries = map validateEntry prefixList;
    in
    prefixList // { entries = validatedEntries; };

  # Route map validation
  validateRouteMap =
    routeMap:
    let
      validateEntry =
        entry:
        assert lib.assertMsg (entry ? seq) "Route map entry must have sequence number";
        assert lib.assertMsg (entry ? action) "Route map entry must have action (permit/deny)";
        assert lib.assertMsg (builtins.elem entry.action [
          "permit"
          "deny"
        ]) "Action must be 'permit' or 'deny'";
        entry;
      validatedEntries = map validateEntry routeMap;
    in
    routeMap // { entries = validatedEntries; };

  # BGP neighbor validation
  validateNeighbor =
    neighbor:
    let
      hasValidASN = neighbor ? asn && validateASN neighbor.asn;
      hasValidAddress =
        neighbor ? address
        && (builtins.match "^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}$" neighbor.address != null);
      hasValidDescription = neighbor ? description -> builtins.isString neighbor.description;
      hasValidCapabilities =
        neighbor ? capabilities
        -> (
          let
            caps = neighbor.capabilities;
          in
          (caps ? multipath -> builtins.isBool caps.multipath)
          && (caps ? refresh -> builtins.isBool caps.refresh)
          && (caps ? gracefulRestart -> builtins.isBool caps.gracefulRestart)
          && (caps ? routeRefresh -> builtins.isBool caps.routeRefresh)
        );
      hasValidPolicies =
        neighbor ? policies
        -> (
          let
            policies = neighbor.policies;
          in
          (policies ? import -> builtins.isList policies.import)
          && (policies ? export -> builtins.isList policies.export)
        );
    in
    assert lib.assertMsg hasValidASN "Neighbor must have valid ASN: ${toString neighbor}";
    assert lib.assertMsg hasValidAddress "Neighbor must have valid IP address: ${toString neighbor}";
    assert lib.assertMsg hasValidDescription
      "Neighbor description must be string: ${toString neighbor}";
    assert lib.assertMsg hasValidCapabilities
      "Neighbor capabilities must be valid: ${toString neighbor}";
    assert lib.assertMsg hasValidPolicies "Neighbor policies must be valid: ${toString neighbor}";
    neighbor;

  # Generate BGP neighbor configuration
  generateNeighborConfig =
    name: neighbor:
    let
      capabilities = neighbor.capabilities or { };
      policies = neighbor.policies or { };
      passwordConfig = lib.optionalString (neighbor ? password && neighbor.password != null) ''
        password ${neighbor.password}
      '';
      capabilitiesConfig =
        lib.optionalString (capabilities ? multipath && capabilities.multipath) ''
          capability multipath
        ''
        + lib.optionalString (capabilities ? refresh && capabilities.refresh) ''
          capability refresh
        ''
        + lib.optionalString (capabilities ? gracefulRestart && capabilities.gracefulRestart) ''
          bgp graceful-restart
        ''
        + lib.optionalString (capabilities ? routeRefresh && capabilities.routeRefresh) ''
          capability route-refresh
        '';
      importPoliciesConfig =
        lib.optionalString (policies ? import && builtins.length policies.import > 0)
          ''
            route-map ${lib.concatStringsSep "," policies.import} in
          '';
      exportPoliciesConfig =
        lib.optionalString (policies ? export && builtins.length policies.export > 0)
          ''
            route-map ${lib.concatStringsSep "," policies.export} out
          '';
      descriptionConfig = lib.optionalString (neighbor ? description && neighbor.description != "") ''
        description "${neighbor.description}"
      '';
    in
    ''
      neighbor ${neighbor.address} remote-as ${toString neighbor.asn}
      ${descriptionConfig}
      ${passwordConfig}
      ${capabilitiesConfig}
      ${importPoliciesConfig}
      ${exportPoliciesConfig}
    '';

  # Generate prefix list configuration
  generatePrefixListConfig =
    name: prefixList:
    let
      entries = builtins.attrValues prefixList;
      generateEntry = entry: ''seq ${toString entry.seq} ${entry.action} ${entry.prefix}'';
    in
    ''
      ip prefix-list ${name}
      ${lib.concatStringsSep "\n      " (map generateEntry entries)}
    '';

  # Generate route map configuration
  generateRouteMapConfig =
    name: routeMap:
    let
      entries = builtins.attrValues routeMap;
      generateEntry =
        entry:
        let
          matchConfig = lib.optionalString (entry ? match) ''
            match ${entry.match}
          '';
          setConfig = lib.optionalString (entry ? set) ''
            ${lib.concatStringsSep "\n            " (
              lib.mapAttrsToList (k: v: "set ${k} ${toString v}") entry.set
            )}
          '';
        in
        ''
          seq ${toString entry.seq} ${entry.action}
          ${matchConfig}
          ${setConfig}
        '';
    in
    ''
      route-map ${name}
      ${lib.concatStringsSep "\n      " (map generateEntry entries)}
    '';

  # Generate community list configuration
  generateCommunityConfig =
    communities:
    let
      generateStandardCommunity =
        name: value: ''ip community-list standard ${name} seq 5 permit ${value}'';
      generateExpandedCommunity =
        name: value: ''ip community-list expanded ${name} seq 5 permit ${value}'';
      generateLargeCommunity =
        name: value: ''bgp large-community-list standard ${name} seq 5 permit ${value}'';
    in
    lib.optionalAttrs (communities ? standard) (
      lib.mapAttrsToList generateStandardCommunity communities.standard
    )
    ++ lib.optionalAttrs (communities ? expanded) (
      lib.mapAttrsToList generateExpandedCommunity communities.expanded
    )
    ++ lib.optionalAttrs (communities ? large) (
      lib.mapAttrsToList generateLargeCommunity communities.large
    );

  # Generate AS path access list configuration
  generateASPathConfig =
    aspaths:
    let
      generateASPath = name: pattern: ''ip as-path access-list ${name} permit ${pattern}'';
    in
    lib.mapAttrsToList generateASPath aspaths;

  # Generate BGP configuration
  generateBGPConfig =
    bgpConfig:
    let
      hasNeighbors =
        bgpConfig ? neighbors
        && bgpConfig.neighbors != { }
        && (builtins.attrNames bgpConfig.neighbors) != [ ];
      hasPrefixLists =
        bgpConfig ? policies
        && bgpConfig.policies ? prefixLists
        && bgpConfig.policies.prefixLists != { }
        && (builtins.attrNames bgpConfig.policies.prefixLists) != [ ];
      hasRouteMaps =
        bgpConfig ? policies
        && bgpConfig.policies ? routeMaps
        && bgpConfig.policies.routeMaps != { }
        && (builtins.attrNames bgpConfig.policies.routeMaps) != [ ];
      hasCommunities = bgpConfig ? policies && bgpConfig.policies ? communities;
      hasASPaths =
        bgpConfig ? policies
        && bgpConfig.policies ? aspaths
        && bgpConfig.policies.aspaths != { }
        && (builtins.attrNames bgpConfig.policies.aspaths) != [ ];

      neighborsConfig = lib.optionalString hasNeighbors (
        "\n    "
        + lib.concatStringsSep "\n    " (lib.mapAttrsToList generateNeighborConfig bgpConfig.neighbors)
      );
      prefixListsConfig = lib.optionalString hasPrefixLists (
        "\n    "
        + lib.concatStringsSep "\n    " (
          lib.mapAttrsToList generatePrefixListConfig bgpConfig.policies.prefixLists
        )
      );
      routeMapsConfig = lib.optionalString hasRouteMaps (
        "\n    "
        + lib.concatStringsSep "\n    " (
          lib.mapAttrsToList generateRouteMapConfig bgpConfig.policies.routeMaps
        )
      );
      communitiesConfig = lib.optionalString hasCommunities (
        "\n    " + lib.concatStringsSep "\n    " (generateCommunityConfig bgpConfig.policies.communities)
      );
      aspathsConfig = lib.optionalString hasASPaths (
        "\n    " + lib.concatStringsSep "\n    " (generateASPathConfig bgpConfig.policies.aspaths)
      );
      multipathConfig = lib.optionalString (bgpConfig ? multipath && bgpConfig.multipath) ''
        bgp bestpath as-path multipath-relax
        bgp bestpath med missing-as-worst
      '';
      flowspecConfig = lib.optionalString (bgpConfig ? flowspec && bgpConfig.flowspec) ''
        bgp flowspec
      '';
      largeCommunitiesConfig =
        lib.optionalString (bgpConfig ? largeCommunities && bgpConfig.largeCommunities)
          ''
            bgp large-community receive
            bgp large-community send
          '';
    in
    ''
      router bgp ${toString bgpConfig.asn}
      ${lib.optionalString ((bgpConfig.routerId or null) != null) ''bgp router-id ${bgpConfig.routerId}''}
      ${lib.optionalString hasNeighbors "\n  " + neighborsConfig}
      ${lib.optionalString hasPrefixLists "\n  " + prefixListsConfig}
      ${lib.optionalString hasRouteMaps "\n  " + routeMapsConfig}
      ${lib.optionalString hasCommunities "\n  " + communitiesConfig}
      ${lib.optionalString hasASPaths "\n  " + aspathsConfig}
      ${lib.optionalString (bgpConfig ? multipath && bgpConfig.multipath) multipathConfig}
      ${lib.optionalString (bgpConfig ? flowspec && bgpConfig.flowspec) flowspecConfig}
      ${lib.optionalString (
        bgpConfig ? largeCommunities && bgpConfig.largeCommunities
      ) largeCommunitiesConfig}
    '';
in
{
  inherit
    validateASN
    validateCommunity
    validateLargeCommunity
    validatePrefixList
    validateRouteMap
    validateNeighbor
    generateNeighborConfig
    generatePrefixListConfig
    generateRouteMapConfig
    generateCommunityConfig
    generateASPathConfig
    generateBGPConfig
    ;
}

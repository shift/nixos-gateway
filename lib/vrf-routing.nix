{ lib, pkgs, ... }:

let
  # Generate ip route commands for static routes in a VRF
  mkStaticRoutes =
    vrf: routes:
    map (
      route:
      "ip route add ${route.destination} via ${route.gateway} dev ${vrf} table ${toString route.table} metric ${toString route.metric}"
    ) routes;

  # Helper to generate BGP configuration for FRR
  mkBgpConfig = vrf: bgpConfig: ''
    router bgp ${toString bgpConfig.asn} vrf ${vrf}
      bgp router-id ${bgpConfig.routerId}
      ${lib.concatStringsSep "\n  " (
        lib.mapAttrsToList (
          neighbor: cfg: "neighbor ${neighbor} remote-as ${toString cfg.remoteAs}"
        ) bgpConfig.neighbors
      )}
  '';

  # Generate firewall rules for VRF isolation
  mkIsolationRules = vrf: ''
    # Isolate VRF ${vrf}
    ip rule add iif ${vrf} table ${vrf}
    ip rule add oif ${vrf} table ${vrf}
  '';

  # Generate route leaking configuration
  mkRouteLeak = fromVrf: toVrf: prefix: ''
    # Leak route ${prefix} from ${fromVrf} to ${toVrf}
    ip route add ${prefix} vrf ${toVrf} nexthop dev ${fromVrf}
  '';
in
{
  inherit
    mkStaticRoutes
    mkBgpConfig
    mkIsolationRules
    mkRouteLeak
    ;
}

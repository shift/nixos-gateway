{ lib, pkgs, ... }:

let
  inherit (lib) mkOption types;

  # Generate FRR BGP configuration for Transit Gateway
  mkBgpConfig = gatewayName: asn: attachments: ''
    router bgp ${toString asn} vrf ${gatewayName}
      bgp router-id 1.1.1.1
      bgp log-neighbor-changes

      # Enable route reflection for hub-and-spoke topology
      bgp cluster-id ${toString asn}

      # Configure attachments as BGP neighbors
      ${lib.concatStringsSep "\n  " (
        map (
          attachment:
          if attachment.type == "vpc" then
            "neighbor ${attachment.vpcId} remote-as ${toString asn}"
          else if attachment.type == "vpn" then
            "neighbor ${attachment.customerGatewayId} remote-as external"
          else
            ""
        ) attachments
      )}

      # Route advertisement policies
      address-family ipv4 unicast
        ${lib.concatStringsSep "\n    " (
          map (
            attachment:
            if attachment.type == "vpc" then
              "neighbor ${attachment.vpcId} activate\n    neighbor ${attachment.vpcId} route-reflector-client"
            else if attachment.type == "vpn" then
              "neighbor ${attachment.customerGatewayId} activate"
            else
              ""
          ) attachments
        )}
      exit-address-family
  '';

  # Generate static routes for Transit Gateway
  mkStaticRoutes =
    gatewayName: routes:
    lib.concatStringsSep "\n" (
      map (
        route:
        if route.type == "static" && route.nextHop != null then
          "ip route add ${route.destination} via ${route.nextHop} table ${gatewayName}"
        else
          ""
      ) routes
    );

  # Generate route propagation rules
  mkPropagationRules =
    gatewayName: routeTable: attachments:
    let
      propagatedRoutes = lib.filter (r: r.type == "propagated") routeTable.routes;
    in
    lib.concatStringsSep "\n" (
      lib.flatten (
        map (
          route:
          map (attachment: "ip route add ${route.destination} dev ${attachment.name} table ${gatewayName}") (
            lib.filter (a: lib.elem a.name route.attachments) attachments
          )
        ) propagatedRoutes
      )
    );

  # Generate VRF route leaking for Transit Gateway isolation
  mkRouteLeaking =
    gatewayName: attachments:
    lib.concatStringsSep "\n" (
      map (
        attachment:
        if attachment.type == "vpc" then
          "ip rule add from ${attachment.vpcId} table ${gatewayName}\n"
          + "ip rule add to ${attachment.vpcId} table ${gatewayName}"
        else
          ""
      ) attachments
    );

  # Generate firewall rules for attachment isolation
  mkIsolationRules = gatewayName: attachments: ''
    # Create isolation chains for ${gatewayName}
    iptables -t filter -N TGW-${gatewayName}-INPUT 2>/dev/null || true
    iptables -t filter -N TGW-${gatewayName}-FORWARD 2>/dev/null || true
    iptables -t filter -N TGW-${gatewayName}-OUTPUT 2>/dev/null || true

    # Apply isolation rules
    ${lib.concatStringsSep "\n" (
      map (
        attachment:
        if attachment.type == "vpc" then
          "iptables -A TGW-${gatewayName}-FORWARD -i ${attachment.name} -o ${attachment.name} -j ACCEPT\n"
          + "iptables -A TGW-${gatewayName}-FORWARD -i ${attachment.name} ! -o ${attachment.name} -j DROP"
        else
          ""
      ) attachments
    )}
  '';

  # Generate monitoring configuration
  mkMonitoringConfig = gatewayName: monitoring: ''
    # Transit Gateway ${gatewayName} monitoring
    ${
      if monitoring.routeAnalytics or false then
        ''
          # Route analytics collection
          echo "Route analytics enabled for ${gatewayName}"
        ''
      else
        ""
    }

    ${
      if monitoring.attachmentHealth or false then
        ''
          # Attachment health monitoring
          echo "Attachment health monitoring enabled for ${gatewayName}"
        ''
      else
        ""
    }

    ${
      if monitoring.flowLogs or false then
        ''
          # Flow logging
          echo "Flow logging enabled for ${gatewayName}"
        ''
      else
        ""
    }
  '';

  # Generate route table synchronization
  mkRouteTableSync =
    gatewayName: routeTables:
    lib.concatStringsSep "\n" (
      map (
        rt:
        "# Synchronize route table ${rt.name} for ${gatewayName}\n"
        + lib.concatStringsSep "\n" (
          map (
            route:
            if route.type == "static" then
              "ip route add ${route.destination} ${
                if route.nextHop != null then "via ${route.nextHop}" else ""
              } table ${rt.name}"
            else
              "# Propagated route ${route.destination} from ${lib.concatStringsSep "," route.attachments}"
          ) rt.routes
        )
      ) routeTables
    );

in
{
  inherit
    mkBgpConfig
    mkStaticRoutes
    mkPropagationRules
    mkRouteLeaking
    mkIsolationRules
    mkMonitoringConfig
    mkRouteTableSync
    ;
}

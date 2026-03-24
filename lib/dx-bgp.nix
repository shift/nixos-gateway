{ lib }:

let
  # Import base BGP config utilities
  bgpLib = import ./bgp-config.nix { inherit lib; };

  # Direct Connect BGP session management
  generateDirectConnectBGPSession =
    name: connection:
    let
      bgp = connection.bgp;
      interfaceName = "dx-${name}";
      routerId = bgp.routerId or "1.1.1.1";

      # Generate IPv4 BGP session
      generateIPv4Session =
        ipv4Cfg:
        let
          localIP = ipv4Cfg.localIP;
          peerIP = ipv4Cfg.peerIP;
          advertisePrefixes = ipv4Cfg.advertisePrefixes or [ ];
        in
        ''
          # IPv4 BGP session for ${name}
          neighbor ${peerIP} remote-as ${toString bgp.peerASN}
          neighbor ${peerIP} description "Direct Connect ${name} IPv4"
          neighbor ${peerIP} update-source ${localIP}
          neighbor ${peerIP} activate
          neighbor ${peerIP} capability extended-nexthop
          ${lib.optionalString (bgp ? timers) ''
            neighbor ${peerIP} timers ${toString bgp.timers.keepalive} ${toString bgp.timers.hold}
          ''}
          ${lib.optionalString (bgp ? authentication && bgp.authentication == "tcp-ao") ''
            neighbor ${peerIP} password tcp-ao ${bgp.tcpAOPassword or ""}
          ''}
          ${lib.optionalString (bgp ? authentication && bgp.authentication == "tcp-md5") ''
            neighbor ${peerIP} password ${bgp.md5Password or ""}
          ''}
          ${lib.concatStringsSep "\n  " (map (prefix: "network ${prefix}") advertisePrefixes)}
        '';

      # Generate IPv6 BGP session
      generateIPv6Session =
        ipv6Cfg:
        let
          localIP = ipv6Cfg.localIP;
          peerIP = ipv6Cfg.peerIP;
          advertisePrefixes = ipv6Cfg.advertisePrefixes or [ ];
        in
        ''
          # IPv6 BGP session for ${name}
          address-family ipv6 unicast
            neighbor ${peerIP} remote-as ${toString bgp.peerASN}
            neighbor ${peerIP} description "Direct Connect ${name} IPv6"
            neighbor ${peerIP} update-source ${localIP}
            neighbor ${peerIP} activate
            neighbor ${peerIP} capability extended-nexthop
            ${lib.optionalString (bgp ? timers) ''
              neighbor ${peerIP} timers ${toString bgp.timers.keepalive} ${toString bgp.timers.hold}
            ''}
            ${lib.concatStringsSep "\n            " (map (prefix: "network ${prefix}") advertisePrefixes)}
          exit-address-family
        '';

      # Generate route policies
      generateRoutePolicies =
        policies:
        let
          inbound = policies.inbound or { };
          outbound = policies.outbound or { };

          # Inbound policies
          inboundCommunities = inbound.allowCommunities or [ ];
          maxPrefixLength = inbound.maxPrefixLength or 24;
          inboundPolicies = ''
            # Inbound route policies for ${name}
            ${lib.optionalString (inboundCommunities != [ ]) ''
              ip community-list standard dx-${name}-in permit ${lib.concatStringsSep " " inboundCommunities}
              route-map dx-${name}-in permit 10
                match community dx-${name}-in
                set local-preference 100
              route-map dx-${name}-in deny 20
            ''}
            ${lib.optionalString (maxPrefixLength > 0) ''
              ip prefix-list dx-${name}-maxlen deny 0.0.0.0/0 ge ${toString (maxPrefixLength + 1)}
              ip prefix-list dx-${name}-maxlen permit 0.0.0.0/0 le ${toString maxPrefixLength}
              route-map dx-${name}-in permit 30
                match ip address prefix-list dx-${name}-maxlen
              route-map dx-${name}-in deny 40
            ''}
          '';

          # Outbound policies
          prependAS = outbound.prependAS or 0;
          setCommunities = outbound.setCommunities or [ ];
          outboundPolicies = ''
            # Outbound route policies for ${name}
            ${lib.optionalString (prependAS > 0) ''
              route-map dx-${name}-out permit 10
                set as-path prepend ${lib.concatStringsSep " " (lib.replicate prependAS (toString bgp.localASN))}
            ''}
            ${lib.optionalString (setCommunities != [ ]) ''
              ip community-list standard dx-${name}-out permit ${lib.concatStringsSep " " setCommunities}
              route-map dx-${name}-out permit 20
                set community ${lib.concatStringsSep " " setCommunities}
            ''}
          '';
        in
        inboundPolicies + outboundPolicies;

      # Apply policies to neighbors
      applyPoliciesToNeighbors =
        let
          ipv4Peer = if bgp ? ipv4 then bgp.ipv4.peerIP else null;
          ipv6Peer = if bgp ? ipv6 && bgp.ipv6.enable then bgp.ipv6.peerIP else null;
        in
        ''
          ${lib.optionalString (ipv4Peer != null) ''
            neighbor ${ipv4Peer} route-map dx-${name}-in in
            neighbor ${ipv4Peer} route-map dx-${name}-out out
          ''}
          ${lib.optionalString (ipv6Peer != null) ''
            address-family ipv6 unicast
              neighbor ${ipv6Peer} route-map dx-${name}-in in
              neighbor ${ipv6Peer} route-map dx-${name}-out out
            exit-address-family
          ''}
        '';

      ipv4Session = lib.optionalString (bgp ? ipv4) (generateIPv4Session bgp.ipv4);
      ipv6Session = lib.optionalString (bgp ? ipv6 && bgp.ipv6.enable) (generateIPv6Session bgp.ipv6);
      policies = lib.optionalString (bgp ? policies) (generateRoutePolicies bgp.policies);
    in
    ''
      # Direct Connect BGP Configuration for ${name}
      router bgp ${toString bgp.localASN}
        bgp router-id ${routerId}
        bgp log-neighbor-changes
        bgp bestpath as-path multipath-relax
        bgp bestpath med missing-as-worst
        bgp large-community receive
        bgp large-community send

        ${ipv4Session}
        ${ipv6Session}

        ${policies}
        ${applyPoliciesToNeighbors}

      exit
    '';

  # Generate BGP multipath configuration for redundancy
  generateDirectConnectMultipath =
    connections:
    let
      # Group connections by provider for multipath
      providerGroups = lib.groupBy (conn: conn.provider) (lib.attrValues connections);
      multipathConfig = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (provider: conns: ''
          # Multipath configuration for ${provider}
          ${lib.optionalString (builtins.length conns > 1) ''
            bgp bestpath as-path multipath-relax
            maximum-paths ${toString (builtins.length conns)}
            maximum-paths ibgp ${toString (builtins.length conns)}
          ''}
        '') providerGroups
      );
    in
    multipathConfig;

  # Generate BGP monitoring and metrics
  generateDirectConnectBGPMetrics =
    name: connection: pkgs:
    let
      bgp = connection.bgp;
      interfaceName = "dx-${name}";
      provider = connection.provider;

      # IPv4 metrics
      ipv4Metrics = lib.optionalString (bgp ? ipv4) (
        let
          peerIP = bgp.ipv4.peerIP;
        in
        ''
          # IPv4 BGP metrics for ${name}
          SESSION_STATE=$(${pkgs.frr}/bin/vtysh -c "show bgp summary json" | ${pkgs.jq}/bin/jq -r ".ipv4Unicast.peers.\"${peerIP}\".state // \"unknown\"")
          UPTIME=$(${pkgs.frr}/bin/vtysh -c "show bgp summary json" | ${pkgs.jq}/bin/jq -r ".ipv4Unicast.peers.\"${peerIP}\".uptime // 0")
          RECEIVED=$(${pkgs.frr}/bin/vtysh -c "show bgp summary json" | ${pkgs.jq}/bin/jq -r ".ipv4Unicast.peers.\"${peerIP}\".received // 0")
          ADVERTISED=$(${pkgs.frr}/bin/vtysh -c "show bgp summary json" | ${pkgs.jq}/bin/jq -r ".ipv4Unicast.peers.\"${peerIP}\".advertised // 0")

          case $SESSION_STATE in
            "Established") STATE_CODE=1 ;;
            "Active") STATE_CODE=2 ;;
            "Connect") STATE_CODE=3 ;;
            "OpenSent") STATE_CODE=4 ;;
            "OpenConfirm") STATE_CODE_V6=5 ;;
            "Idle") STATE_CODE=6 ;;
            *) STATE_CODE=0 ;;
          esac

          echo "direct_connect_bgp_session_state{connection=\"${name}\",provider=\"${provider}\",peer=\"${peerIP}\",family=\"ipv4\"} $STATE_CODE" >> "$METRICS_FILE"
          echo "direct_connect_bgp_session_uptime{connection=\"${name}\",provider=\"${provider}\",peer=\"${peerIP}\",family=\"ipv4\"} $UPTIME" >> "$METRICS_FILE"
          echo "direct_connect_bgp_routes_received{connection=\"${name}\",provider=\"${provider}\",peer=\"${peerIP}\",family=\"ipv4\"} $RECEIVED" >> "$METRICS_FILE"
          echo "direct_connect_bgp_routes_advertised{connection=\"${name}\",provider=\"${provider}\",peer=\"${peerIP}\",family=\"ipv4\"} $ADVERTISED" >> "$METRICS_FILE"
        ''
      );

      # IPv6 metrics
      ipv6Metrics = lib.optionalString (bgp ? ipv6 && bgp.ipv6.enable) (
        let
          peerIP = bgp.ipv6.peerIP;
        in
        ''
          # IPv6 BGP metrics for ${name}
          SESSION_STATE_V6=$(${pkgs.frr}/bin/vtysh -c "show bgp summary json" | ${pkgs.jq}/bin/jq -r ".ipv6Unicast.peers.\"${peerIP}\".state // \"unknown\"")
          UPTIME_V6=$(${pkgs.frr}/bin/vtysh -c "show bgp summary json" | ${pkgs.jq}/bin/jq -r ".ipv6Unicast.peers.\"${peerIP}\".uptime // 0")
          RECEIVED_V6=$(${pkgs.frr}/bin/vtysh -c "show bgp summary json" | ${pkgs.jq}/bin/jq -r ".ipv6Unicast.peers.\"${peerIP}\".received // 0")
          ADVERTISED_V6=$(${pkgs.frr}/bin/vtysh -c "show bgp summary json" | ${pkgs.jq}/bin/jq -r ".ipv6Unicast.peers.\"${peerIP}\".advertised // 0")

          case $SESSION_STATE_V6 in
            "Established") STATE_CODE_V6=1 ;;
            "Active") STATE_CODE_V6=2 ;;
            "Connect") STATE_CODE_V6=3 ;;
            "OpenSent") STATE_CODE_V6=4 ;;
            "OpenConfirm") STATE_CODE_V6=5 ;;
            "Idle") STATE_CODE_V6=6 ;;
            *) STATE_CODE_V6=0 ;;
          esac

          echo "direct_connect_bgp_session_state{connection=\"${name}\",provider=\"${provider}\",peer=\"${peerIP}\",family=\"ipv6\"} $STATE_CODE_V6" >> "$METRICS_FILE"
          echo "direct_connect_bgp_session_uptime{connection=\"${name}\",provider=\"${provider}\",peer=\"${peerIP}\",family=\"ipv6\"} $UPTIME_V6" >> "$METRICS_FILE"
          echo "direct_connect_bgp_routes_received{connection=\"${name}\",provider=\"${provider}\",peer=\"${peerIP}\",family=\"ipv6\"} $RECEIVED_V6" >> "$METRICS_FILE"
          echo "direct_connect_bgp_routes_advertised{connection=\"${name}\",provider=\"${provider}\",peer=\"${peerIP}\",family=\"ipv6\"} $ADVERTISED_V6" >> "$METRICS_FILE"
        ''
      );
    in
    ipv4Metrics + ipv6Metrics;

  # Generate BGP health check script
  generateDirectConnectBGPHealthCheck =
    name: connection: pkgs:
    let
      bgp = connection.bgp;
      interfaceName = "dx-${name}";
      provider = connection.provider;
    in
    ''
      #!/bin/bash
      # Direct Connect BGP Health Check for ${name}

      METRICS_FILE="/run/prometheus/direct-connect-${name}.prom"
      mkdir -p /run/prometheus
      echo "# Direct Connect BGP metrics for ${name}" > "$METRICS_FILE"

      ${generateDirectConnectBGPMetrics name connection pkgs}

      # Route leak detection
      ROUTE_LEAKS=$(${pkgs.frr}/bin/vtysh -c "show bgp" | grep -c "inaccessible" || echo "0")
      echo "direct_connect_route_leaks{connection=\"${name}\",provider=\"${provider}\"} $ROUTE_LEAKS" >> "$METRICS_FILE"

      # Prefix hijacking detection (simplified)
      HIJACKED_PREFIXES=$(${pkgs.frr}/bin/vtysh -c "show bgp" | grep -c "best" | awk '{print $1}' | sort | uniq -c | grep -v " 1 " | wc -l || echo "0")
      echo "direct_connect_prefix_hijacking{connection=\"${name}\",provider=\"${provider}\"} $HIJACKED_PREFIXES" >> "$METRICS_FILE"
    '';

  # Generate BGP alert rules
  generateDirectConnectBGPAlerts =
    name: connection: pkgs:
    let
      monitoring = connection.monitoring or { };
      alerts = monitoring.alerts or { };
    in
    lib.optionalAttrs (monitoring.enable or false) {
      services.prometheus.ruleFiles = [
        (pkgs.writeText "direct-connect-bgp-${name}-alerts.yml" ''
          groups:
          - name: direct_connect_bgp_${name}
            rules:
            ${lib.optionalString (alerts.bgpSessionDown or false) ''
              - alert: DirectConnectBGPSessionDown
                expr: direct_connect_bgp_session_state{connection="${name}"} != 1
                for: 2m
                labels:
                  severity: critical
                  connection: ${name}
                  provider: ${connection.provider}
                annotations:
                  summary: "Direct Connect BGP session ${name} is down"
                  description: "BGP session for Direct Connect connection ${name} to ${connection.provider} is not established"
            ''}
            - alert: DirectConnectRouteLeakDetected
              expr: direct_connect_route_leaks{connection="${name}"} > 0
              for: 1m
              labels:
                severity: warning
                connection: ${name}
                provider: ${connection.provider}
              annotations:
                summary: "Route leak detected on Direct Connect ${name}"
                description: "Potential route leak detected on Direct Connect connection ${name}"
            - alert: DirectConnectPrefixHijackingDetected
              expr: direct_connect_prefix_hijacking{connection="${name}"} > 0
              for: 1m
              labels:
                severity: critical
                connection: ${name}
                provider: ${connection.provider}
              annotations:
                summary: "Prefix hijacking detected on Direct Connect ${name}"
                description: "Potential prefix hijacking detected on Direct Connect connection ${name}"
        '')
      ];
    };
in
{
  inherit
    generateDirectConnectBGPSession
    generateDirectConnectMultipath
    generateDirectConnectBGPMetrics
    generateDirectConnectBGPHealthCheck
    generateDirectConnectBGPAlerts
    ;
}

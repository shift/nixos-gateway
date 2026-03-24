{ lib }:

let
  # Direct Connect connection validation
  validateDirectConnectConnection =
    name: connection:
    let
      hasValidProvider = connection ? provider && builtins.isString connection.provider;
      hasValidLocation = connection ? location && builtins.isString connection.location;
      hasValidBandwidth = connection ? bandwidth && builtins.isString connection.bandwidth;
      validBandwidths = [
        "50Mbps"
        "100Mbps"
        "200Mbps"
        "300Mbps"
        "400Mbps"
        "500Mbps"
        "1Gbps"
        "2Gbps"
        "5Gbps"
        "10Gbps"
        "100Gbps"
      ];
      isValidBandwidth = builtins.elem connection.bandwidth validBandwidths;
      hasValidConnectionType =
        connection ? connectionType
        && builtins.elem connection.connectionType [
          "dedicated"
          "hosted"
          "transit-vif"
          "private-vif"
          "public-vif"
        ];
    in
    assert lib.assertMsg hasValidProvider "Direct Connect connection ${name} must have a provider";
    assert lib.assertMsg hasValidLocation "Direct Connect connection ${name} must have a location";
    assert lib.assertMsg hasValidBandwidth "Direct Connect connection ${name} must have bandwidth";
    assert lib.assertMsg isValidBandwidth
      "Direct Connect connection ${name} bandwidth must be one of: ${lib.concatStringsSep ", " validBandwidths}";
    assert lib.assertMsg hasValidConnectionType
      "Direct Connect connection ${name} must have valid connection type";
    connection;

  # BGP peering validation for Direct Connect
  validateDirectConnectBGP =
    name: bgp:
    let
      hasValidLocalASN =
        bgp ? localASN && lib.isInt bgp.localASN && bgp.localASN >= 1 && bgp.localASN <= 4294967295;
      hasValidPeerASN =
        bgp ? peerASN && lib.isInt bgp.peerASN && bgp.peerASN >= 1 && bgp.peerASN <= 4294967295;
      validateIPConfig =
        ipCfg:
        let
          hasValidLocalIP = ipCfg ? localIP && builtins.isString ipCfg.localIP;
          hasValidPeerIP = ipCfg ? peerIP && builtins.isString ipCfg.peerIP;
          hasValidPrefixes = ipCfg ? advertisePrefixes && builtins.isList ipCfg.advertisePrefixes;
        in
        assert lib.assertMsg hasValidLocalIP "Direct Connect BGP IPv4 config for ${name} must have localIP";
        assert lib.assertMsg hasValidPeerIP "Direct Connect BGP IPv4 config for ${name} must have peerIP";
        assert lib.assertMsg hasValidPrefixes
          "Direct Connect BGP IPv4 config for ${name} must have advertisePrefixes";
        ipCfg;
      ipv4Valid = bgp ? ipv4 && validateIPConfig bgp.ipv4;
      ipv6Valid = !(bgp ? ipv6 && bgp.ipv6.enable) || validateIPConfig bgp.ipv6;
    in
    assert lib.assertMsg hasValidLocalASN "Direct Connect BGP for ${name} must have valid localASN";
    assert lib.assertMsg hasValidPeerASN "Direct Connect BGP for ${name} must have valid peerASN";
    assert lib.assertMsg ipv4Valid "Direct Connect BGP IPv4 config for ${name} is invalid";
    assert lib.assertMsg ipv6Valid "Direct Connect BGP IPv6 config for ${name} is invalid";
    bgp;

  # Generate interface configuration for Direct Connect
  generateDirectConnectInterface =
    name: connection:
    let
      interfaceName = "dx-${name}";
      provider = connection.provider;
      bandwidth = connection.bandwidth;
      location = connection.location;
    in
    {
      ${interfaceName} = {
        enable = true;
        type = "direct-connect";
        provider = provider;
        bandwidth = bandwidth;
        location = location;
        mtu = 9001; # Jumbo frames for Direct Connect
        description = "Direct Connect to ${provider} at ${location}";
      };
    };

  # Generate BGP configuration for Direct Connect
  generateDirectConnectBGP =
    name: connection:
    let
      bgp = connection.bgp;
      interfaceName = "dx-${name}";
      generateNeighbor =
        ipVersion: ipCfg:
        let
          family = if ipVersion == "ipv4" then "ipv4 unicast" else "ipv6 unicast";
          localIP = ipCfg.localIP;
          peerIP = ipCfg.peerIP;
          advertisePrefixes = ipCfg.advertisePrefixes or [ ];
          networkConfigs = lib.concatStringsSep "\n      " (
            map (prefix: "network ${prefix}") advertisePrefixes
          );
        in
        ''
          neighbor ${peerIP} remote-as ${toString bgp.peerASN}
          neighbor ${peerIP} description "Direct Connect ${name} ${ipVersion}"
          neighbor ${peerIP} update-source ${localIP}
          neighbor ${peerIP} activate
          ${lib.optionalString (bgp ? authentication && bgp.authentication == "tcp-ao") ''
            neighbor ${peerIP} password tcp-ao
          ''}
          ${lib.optionalString (bgp ? authentication && bgp.authentication == "tcp-md5") ''
            neighbor ${peerIP} password ${bgp.md5Password or ""}
          ''}
          ${networkConfigs}
        '';

      ipv4Config = lib.optionalString (bgp ? ipv4) (generateNeighbor "ipv4" bgp.ipv4);
      ipv6Config = lib.optionalString (bgp ? ipv6 && bgp.ipv6.enable) (generateNeighbor "ipv6" bgp.ipv6);

      policiesConfig = lib.optionalString (bgp ? policies) (
        let
          inbound = bgp.policies.inbound or { };
          outbound = bgp.policies.outbound or { };
          inboundCommunities = inbound.allowCommunities or [ ];
          maxPrefixLength = inbound.maxPrefixLength or 24;
          prependAS = outbound.prependAS or 1;
          setCommunities = outbound.setCommunities or [ ];
        in
        ''
          # Route policies for ${name}
          ${lib.optionalString (inboundCommunities != [ ]) ''
            ip community-list standard dx-${name}-in seq 5 permit ${lib.concatStringsSep " " inboundCommunities}
            route-map dx-${name}-in permit 10
              match community dx-${name}-in
              set local-preference 100
          ''}
          ${lib.optionalString (maxPrefixLength > 0) ''
            ip prefix-list dx-${name}-maxlen seq 10 deny 0.0.0.0/0 ge ${toString (maxPrefixLength + 1)}
            ip prefix-list dx-${name}-maxlen seq 20 permit 0.0.0.0/0 le ${toString maxPrefixLength}
            route-map dx-${name}-in permit 20
              match ip address prefix-list dx-${name}-maxlen
          ''}
          ${lib.optionalString (prependAS > 0) ''
            route-map dx-${name}-out permit 10
              set as-path prepend ${lib.concatStringsSep " " (lib.replicate prependAS (toString bgp.localASN))}
          ''}
          ${lib.optionalString (setCommunities != [ ]) ''
            ip community-list standard dx-${name}-out seq 5 permit ${lib.concatStringsSep " " setCommunities}
            route-map dx-${name}-out permit 10
              set community ${lib.concatStringsSep " " setCommunities}
          ''}
        ''
      );
    in
    ''
      # Direct Connect BGP Configuration for ${name}
      router bgp ${toString bgp.localASN} vrf dx-${name}
        bgp router-id ${connection.bgp.routerId or "1.1.1.1"}
        bgp log-neighbor-changes

        ${ipv4Config}
        ${ipv6Config}

      ${policiesConfig}
    '';

  # Generate monitoring configuration
  generateDirectConnectMonitoring =
    name: connection: pkgs:
    let
      monitoring = connection.monitoring or { };
      bgp = connection.bgp;
      interfaceName = "dx-${name}";
      healthChecks = monitoring.healthChecks or { };
    in
    {
      services.prometheus.exporters.blackbox = {
        enable = monitoring.enable or false;
        configFile = pkgs.writeText "blackbox.yml" ''
          modules:
            icmp:
              prober: icmp
              timeout: 5s
            tcp_connect:
              prober: tcp
              timeout: 5s
            bgp:
              prober: bgp
              timeout: 5s
        '';
      };

      services.prometheus.scrapeConfigs = lib.optional (monitoring.enable or false) {
        job_name = "direct-connect-${name}";
        static_configs = [
          {
            targets = [
              "${interfaceName}:9115"
            ];
          }
        ];
        metrics_path = "/probe";
        params = {
          module = [ "icmp" ];
          target = [ connection.provider ];
        };
      };

      # Health check script
      systemd.services."direct-connect-${name}-health-check" = lib.mkIf (monitoring.enable or false) {
        description = "Direct Connect ${name} Health Check";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];

        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.bash}/bin/bash ${pkgs.writeScript "dx-health-check-${name}" ''
            #!/bin/bash
            set -e

            INTERFACE="${interfaceName}"
            PROVIDER="${connection.provider}"
            BGP_PEER="${
              if bgp ? ipv4 then
                bgp.ipv4.peerIP
              else if bgp ? ipv6 && bgp.ipv6.enable then
                bgp.ipv6.peerIP
              else
                ""
            }"

            # ICMP health check
            ${lib.optionalString (healthChecks.icmp or false) ''
              if ping -c 3 -I "$INTERFACE" 8.8.8.8 >/dev/null 2>&1; then
                echo "icmp_check{interface=\"$INTERFACE\",provider=\"$PROVIDER\"} 1" >> /run/prometheus/dx-${name}.prom
              else
                echo "icmp_check{interface=\"$INTERFACE\",provider=\"$PROVIDER\"} 0" >> /run/prometheus/dx-${name}.prom
              fi
            ''}

            # BGP session check
            ${lib.optionalString (healthChecks.bgp or false) ''
              if ${pkgs.frr}/bin/vtysh -c "show bgp summary" | grep -q "$BGP_PEER"; then
                BGP_STATE=$(${pkgs.frr}/bin/vtysh -c "show bgp summary json" | ${pkgs.jq}/bin/jq -r ".ipv4Unicast.peers.\"$BGP_PEER\".state // \"unknown\"")
                if [ "$BGP_STATE" = "Established" ]; then
                  echo "bgp_session{interface=\"$INTERFACE\",provider=\"$PROVIDER\",peer=\"$BGP_PEER\"} 1" >> /run/prometheus/dx-${name}.prom
                else
                  echo "bgp_session{interface=\"$INTERFACE\",provider=\"$PROVIDER\",peer=\"$BGP_PEER\"} 0" >> /run/prometheus/dx-${name}.prom
                fi
              fi
            ''}

            # Latency check
            ${lib.optionalString (healthChecks.latency or false) ''
              LATENCY=$(${pkgs.iputils}/bin/ping -c 3 -I "$INTERFACE" 8.8.8.8 2>/dev/null | tail -1 | awk '{print $4}' | cut -d'/' -f2)
              if [ -n "$LATENCY" ]; then
                echo "latency_ms{interface=\"$INTERFACE\",provider=\"$PROVIDER\"} $LATENCY" >> /run/prometheus/dx-${name}.prom
              fi
            ''}
          ''}";
          Restart = "always";
          RestartSec = "30s";
        };
      };
    };

  # Generate alert rules
  generateDirectConnectAlerts =
    name: connection: pkgs:
    let
      monitoring = connection.monitoring or { };
      alerts = monitoring.alerts or { };
    in
    lib.optionalAttrs (monitoring.enable or false) {
      services.prometheus.ruleFiles = [
        (pkgs.writeText "direct-connect-${name}-alerts.yml" ''
          groups:
          - name: direct_connect_${name}
            rules:
            ${lib.optionalString (alerts.connectionDown or false) ''
              - alert: DirectConnectConnectionDown
                expr: icmp_check{interface="dx-${name}"} == 0
                for: 5m
                labels:
                  severity: critical
                  connection: ${name}
                  provider: ${connection.provider}
                annotations:
                  summary: "Direct Connect connection ${name} is down"
                  description: "Direct Connect connection to ${connection.provider} at ${connection.location} is not responding to ICMP"
            ''}
            ${lib.optionalString (alerts.bgpSessionDown or false) ''
              - alert: DirectConnectBGPSessionDown
                expr: bgp_session{interface="dx-${name}"} == 0
                for: 2m
                labels:
                  severity: critical
                  connection: ${name}
                  provider: ${connection.provider}
                annotations:
                  summary: "Direct Connect BGP session ${name} is down"
                  description: "BGP session for Direct Connect connection ${name} to ${connection.provider} is not established"
            ''}
            ${lib.optionalString (alerts.highLatency or false) ''
              - alert: DirectConnectHighLatency
                expr: latency_ms{interface="dx-${name}"} > ${
                  toString (lib.toInt (builtins.replaceStrings [ "ms" ] [ "" ] alerts.highLatency))
                }
                for: 5m
                labels:
                  severity: warning
                  connection: ${name}
                  provider: ${connection.provider}
                annotations:
                  summary: "Direct Connect ${name} high latency"
                  description: "Direct Connect connection ${name} latency is above ${alerts.highLatency}"
            ''}
        '')
      ];
    };
in
{
  inherit
    validateDirectConnectConnection
    validateDirectConnectBGP
    generateDirectConnectInterface
    generateDirectConnectBGP
    generateDirectConnectMonitoring
    generateDirectConnectAlerts
    ;
}

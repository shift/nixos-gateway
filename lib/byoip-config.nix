{ lib }:

let
  # BYOIP prefix validation
  validateBYOIPPrefix =
    prefix:
    let
      isValidPrefix =
        builtins.match "^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}/[0-9]{1,2}$" prefix != null;
      parts = lib.splitString "/" prefix;
      prefixLength = lib.toInt (builtins.elemAt parts 1);
      isValidLength = prefixLength >= 16 && prefixLength <= 24;
    in
    assert lib.assertMsg isValidPrefix
      "BYOIP prefix must be in CIDR notation (e.g., 203.0.113.0/24): ${prefix}";
    assert lib.assertMsg isValidLength "BYOIP prefix length must be between /16 and /24: ${prefix}";
    prefix;

  # Cloud provider validation
  validateProvider =
    provider:
    let
      validProviders = [
        "aws"
        "azure"
        "gcp"
        "cloudflare"
        "akamai"
        "fastly"
        "linode"
        "digitalocean"
        "vultr"
        "hetzner"
      ];
      isValidProvider = builtins.elem provider validProviders;
    in
    assert lib.assertMsg isValidProvider
      "Provider must be one of: ${lib.concatStringsSep ", " validProviders}: ${provider}";
    provider;

  # Provider-specific configurations
  providerConfigs = {
    aws = {
      asn = 16509;
      name = "Amazon Web Services";
      peeringIPs = [
        "169.254.0.1"
        "169.254.0.2"
      ];
      maxPrefixLength = 24;
      communities = {
        prepend1 = "16509:1";
        prepend2 = "16509:2";
        prepend3 = "16509:3";
        noExport = "16509:4";
        noAdvertise = "16509:5";
      };
      routeFilters = {
        inbound = {
          allowCommunities = [ "16509:*" ];
          maxPrefixLength = 24;
        };
        outbound = {
          prependAS = 1;
          noExport = false;
        };
      };
    };

    azure = {
      asn = 12076;
      name = "Microsoft Azure";
      peeringIPs = [
        "169.254.1.1"
        "169.254.1.2"
      ];
      maxPrefixLength = 24;
      communities = {
        prepend1 = "12076:1";
        prepend2 = "12076:2";
        prepend3 = "12076:3";
        noExport = "12076:4";
        noAdvertise = "12076:5";
      };
      routeFilters = {
        inbound = {
          allowCommunities = [ "12076:*" ];
          maxPrefixLength = 24;
        };
        outbound = {
          prependAS = 1;
          noExport = false;
        };
      };
    };

    gcp = {
      asn = 15169;
      name = "Google Cloud Platform";
      peeringIPs = [
        "169.254.2.1"
        "169.254.2.2"
      ];
      maxPrefixLength = 24;
      communities = {
        prepend1 = "15169:1";
        prepend2 = "15169:2";
        prepend3 = "15169:3";
        noExport = "15169:4";
        noAdvertise = "15169:5";
      };
      routeFilters = {
        inbound = {
          allowCommunities = [ "15169:*" ];
          maxPrefixLength = 24;
        };
        outbound = {
          prependAS = 1;
          noExport = false;
        };
      };
    };

    cloudflare = {
      asn = 13335;
      name = "Cloudflare";
      peeringIPs = [
        "169.254.3.1"
        "169.254.3.2"
      ];
      maxPrefixLength = 24;
      communities = {
        prepend1 = "13335:1";
        prepend2 = "13335:2";
        prepend3 = "13335:3";
        noExport = "13335:4";
        noAdvertise = "13335:5";
      };
      routeFilters = {
        inbound = {
          allowCommunities = [ "13335:*" ];
          maxPrefixLength = 24;
        };
        outbound = {
          prependAS = 1;
          noExport = false;
        };
      };
    };
  };

  # Generate provider-specific BGP configuration
  generateProviderBGPConfig =
    provider: config:
    let
      providerInfo = providerConfigs.${provider};
      localASN = config.localASN;
      neighborIP = config.neighborIP or (builtins.head providerInfo.peeringIPs);
      description = "${providerInfo.name} BYOIP Peering";

      # Generate prefix advertisements
      prefixAds = lib.concatStringsSep "\n    " (
        map (prefix: ''
          network ${prefix.prefix}
          ${lib.optionalString (prefix ? communities && builtins.length prefix.communities > 0)
            "route-map ${provider}-out permit 10 set community ${lib.concatStringsSep " " prefix.communities}"
          }
          ${lib.optionalString (
            prefix ? asPath
          ) "route-map ${provider}-out permit 10 set as-path prepend ${prefix.asPath}"}
          ${lib.optionalString (
            prefix ? localPref
          ) "route-map ${provider}-out permit 10 set local-preference ${toString prefix.localPref}"}
        '') config.prefixes
      );

      # Generate route filters
      inboundFilters = config.filters.inbound or providerInfo.routeFilters.inbound;
      outboundFilters = config.filters.outbound or providerInfo.routeFilters.outbound;

      inboundFilterConfig = ''
        ip prefix-list ${provider}-in seq 10 permit 0.0.0.0/0 le ${toString inboundFilters.maxPrefixLength}
        ${lib.optionalString (inboundFilters ? allowCommunities)
          "ip community-list standard ${provider}-communities seq 10 permit ${lib.concatStringsSep " " inboundFilters.allowCommunities}"
        }
        route-map ${provider}-in permit 10
          match ip address prefix-list ${provider}-in
          ${lib.optionalString (
            inboundFilters ? allowCommunities
          ) "match community ${provider}-communities"}
      '';

      outboundFilterConfig = ''
        route-map ${provider}-out permit 10
          ${lib.optionalString (outboundFilters ? prependAS && outboundFilters.prependAS > 0)
            "set as-path prepend ${lib.concatStringsSep " " (lib.replicate outboundFilters.prependAS (toString localASN))}"
          }
          ${lib.optionalString (
            outboundFilters ? noExport && outboundFilters.noExport
          ) "set community additive no-export"}
      '';

      # Neighbor configuration
      neighborConfig = ''
        neighbor ${neighborIP} remote-as ${toString providerInfo.asn}
        neighbor ${neighborIP} description "${description}"
        neighbor ${neighborIP} route-map ${provider}-in in
        neighbor ${neighborIP} route-map ${provider}-out out
        neighbor ${neighborIP} timers 30 90
        neighbor ${neighborIP} capability extended-nexthop
      '';
    in
    {
      inherit
        prefixAds
        inboundFilterConfig
        outboundFilterConfig
        neighborConfig
        ;
      providerInfo = providerInfo;
    };

  # Generate RPKI/ROV configuration
  generateROVConfig =
    rovConfig:
    let
      strictMode = rovConfig.strict or false;
      rovConfigText = ''
        rpki
        rpki polling_period 3600
        rpki expire_interval 7200
        rpki retry_interval 600
        exit
      '';

      routeMapConfig = lib.optionalString (!strictMode) ''
        route-map rov-filter permit 10
          set community additive 65001:666
        route-map rov-filter permit 20
      '';
    in
    {
      inherit rovConfigText routeMapConfig;
    };

  # Generate monitoring configuration
  generateMonitoringConfig =
    monitoringConfig:
    let
      checkInterval = monitoringConfig.checkInterval or "30s";
      alertThreshold = monitoringConfig.alertThreshold or 300;
      prometheusPort = monitoringConfig.prometheusPort or 9093;

      monitoringScript = ''
        #!/bin/sh
        set -euo pipefail

        PROVIDER="$1"
        NEIGHBOR_IP="$2"

        # Check BGP session state
        SESSION_STATE=$(vtysh -c "show bgp summary json" | jq -r ".ipv4Unicast.peers.\"$NEIGHBOR_IP\".state // \"unknown\"")

        if [ "$SESSION_STATE" != "Established" ]; then
          echo "CRITICAL: BGP session with $PROVIDER ($NEIGHBOR_IP) is $SESSION_STATE"
          exit 2
        fi

        # Check route advertisement
        ADVERTISED_ROUTES=$(vtysh -c "show bgp neighbors $NEIGHBOR_IP advertised-routes" | grep -c "Network" || echo "0")

        if [ "$ADVERTISED_ROUTES" -eq 0 ]; then
          echo "WARNING: No routes advertised to $PROVIDER ($NEIGHBOR_IP)"
          exit 1
        fi

        # Check received routes
        RECEIVED_ROUTES=$(vtysh -c "show bgp summary json" | jq -r ".ipv4Unicast.peers.\"$NEIGHBOR_IP\".received // 0")

        echo "OK: BGP session with $PROVIDER established, $ADVERTISED_ROUTES routes advertised, $RECEIVED_ROUTES routes received"
        exit 0
      '';

      prometheusConfig = ''
        global:
          scrape_interval: 30s
          evaluation_interval: 30s

        rule_files:
          - /etc/prometheus/byoip-alerts.yml

        alerting:
          alertmanagers:
            - static_configs:
                - targets:
                  - localhost:9093

        scrape_configs:
          - job_name: 'byoip-bgp'
            static_configs:
              - targets: ['localhost:9090']
            metrics_path: /metrics
      '';

      alertRules = ''
        groups:
        - name: byoip-bgp
          rules:
          - alert: BGPSessionDown
            expr: gateway_bgp_neighbor_state{state!="Established"} > 0
            for: 5m
            labels:
              severity: critical
            annotations:
              summary: "BGP session with {{ $labels.provider }} is down"
              description: "BGP session with provider {{ $labels.provider }} ({{ $labels.neighbor }}) has been down for more than 5 minutes"

          - alert: BYOIPPrefixHijacking
            expr: gateway_bgp_prefix_hijacking_detected > 0
            for: 1m
            labels:
              severity: critical
            annotations:
              summary: "BYOIP prefix hijacking detected"
              description: "Potential prefix hijacking detected for BYOIP prefix {{ $labels.prefix }}"

          - alert: BYOIPRouteLeak
            expr: gateway_bgp_route_leak_detected > 0
            for: 1m
            labels:
              severity: warning
            annotations:
              summary: "BYOIP route leak detected"
              description: "Route leak detected for BYOIP prefix {{ $labels.prefix }} to unauthorized AS"
      '';
    in
    {
      inherit
        monitoringScript
        prometheusConfig
        alertRules
        checkInterval
        alertThreshold
        prometheusPort
        ;
    };

in
{
  inherit
    validateBYOIPPrefix
    validateProvider
    providerConfigs
    generateProviderBGPConfig
    generateROVConfig
    generateMonitoringConfig
    ;
}

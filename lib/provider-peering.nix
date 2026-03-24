{ lib }:

let
  # Cloud provider peering templates
  providerTemplates = {
    # AWS Direct Connect BGP Peering Template
    aws = {
      description = "AWS Direct Connect BYOIP BGP Peering";
      asn = 16509;
      peeringTypes = {
        publicVIF = {
          description = "Public Virtual Interface";
          neighborIPs = [
            "169.254.255.1"
            "169.254.255.2"
          ];
          capabilities = {
            multipath = true;
            extendedNexthop = true;
            addPath = "receive";
          };
          timers = {
            keepalive = 30;
            hold = 90;
          };
        };
        transitVIF = {
          description = "Transit Virtual Interface";
          neighborIPs = [
            "169.254.254.1"
            "169.254.254.2"
          ];
          capabilities = {
            multipath = true;
            extendedNexthop = true;
            addPath = "both";
          };
          timers = {
            keepalive = 60;
            hold = 180;
          };
        };
      };
      communities = {
        prepend1 = "16509:1";
        prepend2 = "16509:2";
        prepend3 = "16509:3";
        noExport = "16509:4";
        noAdvertise = "16509:5";
        localPref = {
          high = "16509:100";
          medium = "16509:200";
          low = "16509:300";
        };
      };
      routeFilters = {
        inbound = {
          maxPrefixLength = 24;
          allowCommunities = [ "16509:*" ];
          rejectLongerPrefixes = true;
        };
        outbound = {
          prependAS = 1;
          noExport = false;
          aggregateOnly = false;
        };
      };
      monitoring = {
        checkInterval = "30s";
        alertThreshold = 300;
        healthChecks = [
          "bgp_session_state"
          "route_advertisement"
          "prefix_hijacking_detection"
        ];
      };
    };

    # Azure ExpressRoute BGP Peering Template
    azure = {
      description = "Azure ExpressRoute BYOIP BGP Peering";
      asn = 12076;
      peeringTypes = {
        microsoft = {
          description = "Microsoft Peering";
          neighborIPs = [
            "169.254.0.1"
            "169.254.0.2"
          ];
          capabilities = {
            multipath = true;
            extendedNexthop = true;
            addPath = "receive";
          };
          timers = {
            keepalive = 30;
            hold = 90;
          };
        };
        private = {
          description = "Private Peering";
          neighborIPs = [
            "169.254.1.1"
            "169.254.1.2"
          ];
          capabilities = {
            multipath = true;
            extendedNexthop = true;
            addPath = "both";
          };
          timers = {
            keepalive = 60;
            hold = 180;
          };
        };
      };
      communities = {
        prepend1 = "12076:1";
        prepend2 = "12076:2";
        prepend3 = "12076:3";
        noExport = "12076:4";
        noAdvertise = "12076:5";
        localPref = {
          high = "12076:100";
          medium = "12076:200";
          low = "12076:300";
        };
      };
      routeFilters = {
        inbound = {
          maxPrefixLength = 24;
          allowCommunities = [ "12076:*" ];
          rejectLongerPrefixes = true;
        };
        outbound = {
          prependAS = 1;
          noExport = false;
          aggregateOnly = false;
        };
      };
      monitoring = {
        checkInterval = "30s";
        alertThreshold = 300;
        healthChecks = [
          "bgp_session_state"
          "route_advertisement"
          "prefix_hijacking_detection"
        ];
      };
    };

    # Google Cloud Interconnect BGP Peering Template
    gcp = {
      description = "Google Cloud Interconnect BYOIP BGP Peering";
      asn = 15169;
      peeringTypes = {
        partner = {
          description = "Partner Interconnect";
          neighborIPs = [
            "169.254.0.1"
            "169.254.0.2"
          ];
          capabilities = {
            multipath = true;
            extendedNexthop = true;
            addPath = "receive";
          };
          timers = {
            keepalive = 30;
            hold = 90;
          };
        };
        dedicated = {
          description = "Dedicated Interconnect";
          neighborIPs = [
            "169.254.1.1"
            "169.254.1.2"
          ];
          capabilities = {
            multipath = true;
            extendedNexthop = true;
            addPath = "both";
          };
          timers = {
            keepalive = 60;
            hold = 180;
          };
        };
      };
      communities = {
        prepend1 = "15169:1";
        prepend2 = "15169:2";
        prepend3 = "15169:3";
        noExport = "15169:4";
        noAdvertise = "15169:5";
        localPref = {
          high = "15169:100";
          medium = "15169:200";
          low = "15169:300";
        };
      };
      routeFilters = {
        inbound = {
          maxPrefixLength = 24;
          allowCommunities = [ "15169:*" ];
          rejectLongerPrefixes = true;
        };
        outbound = {
          prependAS = 1;
          noExport = false;
          aggregateOnly = false;
        };
      };
      monitoring = {
        checkInterval = "30s";
        alertThreshold = 300;
        healthChecks = [
          "bgp_session_state"
          "route_advertisement"
          "prefix_hijacking_detection"
        ];
      };
    };

    # Cloudflare Magic Transit BGP Peering Template
    cloudflare = {
      description = "Cloudflare Magic Transit BYOIP BGP Peering";
      asn = 13335;
      peeringTypes = {
        magicTransit = {
          description = "Magic Transit";
          neighborIPs = [
            "169.254.0.1"
            "169.254.0.2"
          ];
          capabilities = {
            multipath = true;
            extendedNexthop = true;
            addPath = "receive";
          };
          timers = {
            keepalive = 30;
            hold = 90;
          };
        };
      };
      communities = {
        prepend1 = "13335:1";
        prepend2 = "13335:2";
        prepend3 = "13335:3";
        noExport = "13335:4";
        noAdvertise = "13335:5";
        localPref = {
          high = "13335:100";
          medium = "13335:200";
          low = "13335:300";
        };
      };
      routeFilters = {
        inbound = {
          maxPrefixLength = 24;
          allowCommunities = [ "13335:*" ];
          rejectLongerPrefixes = true;
        };
        outbound = {
          prependAS = 1;
          noExport = false;
          aggregateOnly = false;
        };
      };
      monitoring = {
        checkInterval = "30s";
        alertThreshold = 300;
        healthChecks = [
          "bgp_session_state"
          "route_advertisement"
          "prefix_hijacking_detection"
        ];
      };
    };
  };

  # Generate provider-specific configuration
  generateProviderTemplate =
    provider: peeringType: customConfig:
    let
      template = providerTemplates.${provider};
      peeringConfig = template.peeringTypes.${peeringType};

      # Merge custom config with template
      mergedConfig = lib.recursiveUpdate template customConfig;
      mergedPeering = lib.recursiveUpdate peeringConfig (customConfig.peeringConfig or { });

      # Generate BGP neighbor configuration
      generateNeighborConfig = neighborIP: ''
        neighbor ${neighborIP} remote-as ${toString template.asn}
        neighbor ${neighborIP} description "${template.description} - ${peeringConfig.description}"
        neighbor ${neighborIP} timers ${toString mergedPeering.timers.keepalive} ${toString mergedPeering.timers.hold}
        ${lib.optionalString mergedPeering.capabilities.multipath "neighbor ${neighborIP} capability multipath"}
        ${lib.optionalString mergedPeering.capabilities.extendedNexthop "neighbor ${neighborIP} capability extended-nexthop"}
        ${lib.optionalString (
          mergedPeering.capabilities ? addPath
        ) "neighbor ${neighborIP} addpath ${mergedPeering.capabilities.addPath}"}
        neighbor ${neighborIP} route-map ${provider}-${peeringType}-in in
        neighbor ${neighborIP} route-map ${provider}-${peeringType}-out out
      '';

      # Generate route filtering
      generateRouteFilters = ''
        # Inbound filters
        ip prefix-list ${provider}-${peeringType}-in seq 10 permit 0.0.0.0/0 le ${toString mergedConfig.routeFilters.inbound.maxPrefixLength}
        ${lib.optionalString mergedConfig.routeFilters.inbound.rejectLongerPrefixes "ip prefix-list ${provider}-${peeringType}-in seq 20 deny 0.0.0.0/0 ge ${
          toString (mergedConfig.routeFilters.inbound.maxPrefixLength + 1)
        }"}

        ${lib.optionalString (mergedConfig.routeFilters.inbound ? allowCommunities)
          "ip community-list standard ${provider}-${peeringType}-communities seq 10 permit ${lib.concatStringsSep " " mergedConfig.routeFilters.inbound.allowCommunities}"
        }

        route-map ${provider}-${peeringType}-in permit 10
          match ip address prefix-list ${provider}-${peeringType}-in
          ${lib.optionalString (
            mergedConfig.routeFilters.inbound ? allowCommunities
          ) "match community ${provider}-${peeringType}-communities"}

        # Outbound filters
        route-map ${provider}-${peeringType}-out permit 10
          ${lib.optionalString (mergedConfig.routeFilters.outbound.prependAS > 0)
            "set as-path prepend ${
              lib.concatStringsSep " " (
                lib.replicate mergedConfig.routeFilters.outbound.prependAS (
                  toString customConfig.localASN or "65000"
                )
              )
            }"
          }
          ${lib.optionalString mergedConfig.routeFilters.outbound.noExport "set community additive no-export"}
          ${lib.optionalString mergedConfig.routeFilters.outbound.aggregateOnly "match ip address prefix-list ${provider}-${peeringType}-aggregate-only"}
      '';

      # Generate monitoring configuration
      generateMonitoring = ''
        # ${provider} ${peeringType} monitoring
        check_bgp_session_${provider}_${peeringType}() {
          local neighbor_ip="$1"
          local session_state

          session_state=$(vtysh -c "show bgp summary json" | jq -r ".ipv4Unicast.peers.\"$neighbor_ip\".state // \"unknown\"")

          if [ "$session_state" != "Established" ]; then
            echo "CRITICAL: BGP session with ${provider} ${peeringType} ($neighbor_ip) is $session_state"
            return 2
          fi

          echo "OK: BGP session with ${provider} ${peeringType} established"
          return 0
        }

        check_route_advertisement_${provider}_${peeringType}() {
          local advertised_routes

          advertised_routes=$(vtysh -c "show bgp neighbors ${lib.head mergedPeering.neighborIPs} advertised-routes" | grep -c "Network" || echo "0")

          if [ "$advertised_routes" -eq 0 ]; then
            echo "WARNING: No routes advertised to ${provider} ${peeringType}"
            return 1
          fi

          echo "OK: $advertised_routes routes advertised to ${provider} ${peeringType}"
          return 0
        }
      '';
    in
    {
      inherit template mergedConfig mergedPeering;
      neighborConfig = lib.concatStringsSep "\n" (map generateNeighborConfig mergedPeering.neighborIPs);
      routeFilters = generateRouteFilters;
      monitoring = generateMonitoring;
    };

  # Validate provider template configuration
  validateProviderTemplate =
    provider: peeringType: config:
    let
      hasValidProvider = builtins.hasAttr provider providerTemplates;
      hasValidPeeringType =
        hasValidProvider && builtins.hasAttr peeringType providerTemplates.${provider}.peeringTypes;
      hasRequiredFields = config ? localASN && config ? prefixes;
    in
    assert lib.assertMsg hasValidProvider "Unknown provider: ${provider}";
    assert lib.assertMsg hasValidPeeringType
      "Unknown peering type ${peeringType} for provider ${provider}";
    assert lib.assertMsg hasRequiredFields
      "Provider template config must include localASN and prefixes";
    config;

in
{
  inherit
    providerTemplates
    generateProviderTemplate
    validateProviderTemplate
    ;
}

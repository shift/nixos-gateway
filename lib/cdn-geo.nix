# CDN Geo-Distribution Library
# Provides utilities for geographic routing, edge node management, and location-based optimizations

{ lib, ... }:

let
  inherit (lib) types mkOption;

  # Geographic regions and their properties
  regions = {
    "us-east" = {
      name = "US East";
      continent = "North America";
      latency = 20; # milliseconds to reference point
      capacity = 100; # default GB
    };
    "us-west" = {
      name = "US West";
      continent = "North America";
      latency = 30;
      capacity = 100;
    };
    "eu-west" = {
      name = "EU West";
      continent = "Europe";
      latency = 15;
      capacity = 80;
    };
    "eu-central" = {
      name = "EU Central";
      continent = "Europe";
      latency = 10;
      capacity = 80;
    };
    "ap-southeast" = {
      name = "Asia Pacific Southeast";
      continent = "Asia";
      latency = 150;
      capacity = 60;
    };
    "ap-northeast" = {
      name = "Asia Pacific Northeast";
      continent = "Asia";
      latency = 200;
      capacity = 60;
    };
  };

  # Country to region mapping
  countryToRegion = {
    "US" = "us-east";
    "CA" = "us-east";
    "GB" = "eu-west";
    "DE" = "eu-central";
    "FR" = "eu-west";
    "IT" = "eu-central";
    "ES" = "eu-west";
    "NL" = "eu-west";
    "SE" = "eu-central";
    "NO" = "eu-central";
    "DK" = "eu-central";
    "FI" = "eu-central";
    "PL" = "eu-central";
    "AT" = "eu-central";
    "CH" = "eu-central";
    "BE" = "eu-west";
    "PT" = "eu-west";
    "IE" = "eu-west";
    "SG" = "ap-southeast";
    "JP" = "ap-northeast";
    "KR" = "ap-northeast";
    "AU" = "ap-southeast";
    "NZ" = "ap-southeast";
    "HK" = "ap-southeast";
    "TW" = "ap-northeast";
    "IN" = "ap-southeast";
    "TH" = "ap-southeast";
    "MY" = "ap-southeast";
    "ID" = "ap-southeast";
    "PH" = "ap-southeast";
    "VN" = "ap-southeast";
  };

  # Get region for a country code
  getRegionForCountry = countryCode: countryToRegion.${countryCode} or "us-east"; # Default fallback

  # Calculate geographic distance (simplified)
  calculateGeoDistance =
    loc1: loc2:
    let
      # Simplified distance calculation using latitude/longitude
      lat1 = loc1.lat or 0;
      lon1 = loc1.lon or 0;
      lat2 = loc2.lat or 0;
      lon2 = loc2.lon or 0;

      dlat = (lat2 - lat1) * 3.14159 / 180;
      dlon = (lon2 - lon1) * 3.14159 / 180;

      a =
        (lib.sin (dlat/2)) * (lib.sin (dlat/2))
        +
          (lib.cos (lat1 * 3.14159 / 180))
          * (lib.cos (lat2 * 3.14159 / 180))
          * (lib.sin (dlon/2))
          * (lib.sin (dlon/2));
      c = 2 * lib.atan (lib.sqrt a / lib.sqrt (1 - a));

      # Earth's radius in kilometers
      earthRadius = 6371;
    in
    c * earthRadius;

  # Find nearest edge node
  findNearestEdgeNode =
    clientLocation: edgeNodes:
    let
      nodesWithDistance = map (node: {
        inherit node;
        distance = calculateGeoDistance clientLocation node.location;
      }) edgeNodes;

      sortedNodes = lib.sort (a: b: a.distance < b.distance) nodesWithDistance;
    in
    if sortedNodes == [ ] then null else (lib.head sortedNodes).node;

  # Generate geographic routing configuration
  generateGeoRoutingConfig = edgeNodes: ''
    # Geographic routing configuration
    geo $nearest_edge {
      default "us-east";

      ${lib.concatStringsSep "\n  " (
        map (node: ''
          ${node.region} ${node.region};
        '') edgeNodes
      )}
    }

    # Map client location to nearest edge
    map $geoip2_data_country_code $client_region {
      default "us-east";
      ${lib.concatStringsSep "\n  " (
        lib.mapAttrsToList (country: region: ''
          ${country} ${region};
        '') countryToRegion
      )}
    }

    # Route to nearest edge node
    upstream edge_nodes {
      ${lib.concatStringsSep "\n  " (
        map (node: ''
          server ${lib.head node.publicIPs}:80;
        '') edgeNodes
      )}
    }
  '';

  # Generate anycast configuration (placeholder)
  generateAnycastConfig = edgeNodes: ''
    # Anycast configuration
    # This would configure BGP anycast routing
    # Implementation depends on specific network setup

    ${lib.concatStringsSep "\n" (
      map (node: ''
        # Edge node: ${node.region} (${node.location})
        # Public IPs: ${lib.concatStringsSep ", " node.publicIPs}
        # Capacity: ${toString node.capacity}GB
      '') edgeNodes
    )}
  '';

  # Calculate optimal cache distribution
  calculateOptimalCacheDistribution =
    edgeNodes: totalContent:
    let
      totalCapacity = lib.foldl (acc: node: acc + node.capacity) 0 edgeNodes;
      contentPerGB = totalContent / totalCapacity;
    in
    map (node: {
      inherit node;
      optimalContent = node.capacity * contentPerGB;
      utilization = (node.capacity * 100) / totalCapacity;
    }) edgeNodes;

  # Generate edge node health check configuration
  generateHealthCheckConfig = edgeNodes: ''
    # Edge node health checks
    ${lib.concatStringsSep "\n" (
      map (node: ''
        upstream ${node.region}_health {
          ${lib.concatStringsSep "\n    " (map (ip: "server ${ip}:80;") node.publicIPs)}
          keepalive 16;
        }

        server {
          listen 127.0.0.1:8080;
          location /health {
            proxy_pass http://${node.region}_health;
            proxy_connect_timeout 5s;
            proxy_send_timeout 5s;
            proxy_read_timeout 5s;
          }
        }
      '') edgeNodes
    )}
  '';

  # Monitor edge node performance
  monitorEdgePerformance = edgeNodes: ''
    # Performance monitoring for edge nodes
    # This would integrate with monitoring systems

    ${lib.concatStringsSep "\n" (
      map (node: ''
        # Monitor ${node.region} (${node.location})
        # Capacity: ${toString node.capacity}GB
        # IPs: ${lib.concatStringsSep ", " node.publicIPs}
      '') edgeNodes
    )}
  '';

  # Generate DNS configuration for geo-routing
  generateGeoDNSConfig = domain: edgeNodes: ''
    # Geographic DNS configuration
    # This would generate DNS records for geo-based routing

    ${domain}. IN A ${
      lib.concatStringsSep "\n${domain}. IN A " (lib.flatten (map (node: node.publicIPs) edgeNodes))
    }

    # Geo-specific subdomains
    ${lib.concatStringsSep "\n" (
      map (node: ''
        ${node.region}.${domain}. IN A ${lib.concatStringsSep "\n${node.region}.${domain}. IN A " node.publicIPs}
      '') edgeNodes
    )}
  '';

  # Calculate edge node capacity utilization
  calculateCapacityUtilization =
    edgeNodes:
    let
      totalCapacity = lib.foldl (acc: node: acc + node.capacity) 0 edgeNodes;
      utilizationByRegion = lib.mapAttrs (
        region: info:
        let
          regionNodes = lib.filter (node: node.region == region) edgeNodes;
          regionCapacity = lib.foldl (acc: node: acc + node.capacity) 0 regionNodes;
        in
        (regionCapacity * 100) / totalCapacity
      ) regions;
    in
    utilizationByRegion;

  # Optimize edge node placement
  optimizeEdgePlacement =
    trafficPatterns: existingNodes:
    let
      # Analyze traffic patterns and suggest new edge locations
      highTrafficRegions = lib.filter (pattern: pattern.requestsPerSecond > 1000) trafficPatterns;

      suggestedLocations = lib.subtractLists (map (node: node.region) existingNodes) (
        map (pattern: getRegionForCountry pattern.country) highTrafficRegions
      );
    in
    {
      suggestions = suggestedLocations;
      reasoning = "High traffic detected in regions not covered by existing edge nodes";
    };

in
{
  # Public API
  regions = regions;
  countryToRegion = countryToRegion;

  inherit
    getRegionForCountry
    calculateGeoDistance
    findNearestEdgeNode
    generateGeoRoutingConfig
    generateAnycastConfig
    calculateOptimalCacheDistribution
    generateHealthCheckConfig
    monitorEdgePerformance
    generateGeoDNSConfig
    calculateCapacityUtilization
    optimizeEdgePlacement
    ;
}

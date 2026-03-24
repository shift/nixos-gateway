{ lib, ... }:

let
  inherit (lib) concatStringsSep optionalString;
in
{
  generateArpDiscoveryScript =
    { discovery, pkgs }:
    ''
      echo "Running ARP Discovery..."
      ${
        if discovery.methods.arp.enable then
          ''
            # Capture ARP table
            ${pkgs.iproute2}/bin/ip -j neigh show > "$TOPOLOGY_DIR/arp_raw.json"

            # Process ARP data
            cat "$TOPOLOGY_DIR/arp_raw.json" | ${pkgs.jq}/bin/jq 'map({
              type: "device",
              ip: .dst,
              mac: .lladdr,
              interface: .dev,
              state: .state,
              method: "arp"
            }) | map(select(.state != "FAILED"))' > "$TOPOLOGY_DIR/arp_processed.json"
          ''
        else
          ''
            echo "ARP discovery disabled."
            echo "[]" > "$TOPOLOGY_DIR/arp_processed.json"
          ''
      }
    '';

  generateLldpDiscoveryScript =
    { discovery, pkgs }:
    ''
      echo "Running LLDP Discovery..."
      ${
        if discovery.methods.lldp.enable then
          ''
            # Capture LLDP neighbors (assuming lldpcli json output)
            if command -v lldpcli >/dev/null 2>&1; then
               # This might fail if lldpd is not running or no permissions, handle gracefully
               ${pkgs.lldpd}/bin/lldpcli show neighbors -f json > "$TOPOLOGY_DIR/lldp_raw.json" || echo "{}" > "$TOPOLOGY_DIR/lldp_raw.json"
               
               # Process LLDP data (simplified extraction)
               cat "$TOPOLOGY_DIR/lldp_raw.json" | ${pkgs.jq}/bin/jq 'if .lldp then [.lldp[].interface[] | {
                 type: "switch", 
                 name: .chassis[].name[].value, 
                 interface: .name,
                 remote_port: .port[].id[].value,
                 method: "lldp"
               }] else [] end' > "$TOPOLOGY_DIR/lldp_processed.json"
            else
               echo "lldpcli not found."
               echo "[]" > "$TOPOLOGY_DIR/lldp_processed.json"
            fi
          ''
        else
          ''
            echo "LLDP discovery disabled."
            echo "[]" > "$TOPOLOGY_DIR/lldp_processed.json"
          ''
      }
    '';

  generateTopologyMergeScript = ''
    echo "Merging Topology Data..."
    # Merge all processed files
    # Using slurp to read file contents into an array and flatten/merge
    jq -s 'flatten' "$TOPOLOGY_DIR"/arp_processed.json "$TOPOLOGY_DIR"/lldp_processed.json > "$TOPOLOGY_DIR/topology_nodes.json"

    # Create final topology structure
    jq -n --slurpfile nodes "$TOPOLOGY_DIR/topology_nodes.json" '{
      timestamp: now,
      nodes: $nodes,
      links: [] # Link inference logic would go here
    }' > "$TOPOLOGY_DIR/topology.json"

    echo "Topology data merged to $TOPOLOGY_DIR/topology.json"
  '';
}

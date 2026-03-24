{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.gateway.topologyGenerator;

  # Python script to generate the topology visualization
  # This uses graphviz to generate the actual image
  topologyGeneratorScript = ''
    import argparse
    import json
    import sys
    import os

    # Check if graphviz is available
    try:
        import graphviz
    except ImportError:
        print("Error: graphviz python module is not installed.", file=sys.stderr)
        sys.exit(1)

    def generate_topology(config_path, output_path, format='svg'):
        try:
            with open(config_path, 'r') as f:
                config = json.load(f)
        except Exception as e:
            print(f"Error loading config: {e}", file=sys.stderr)
            sys.exit(1)

        dot = graphviz.Digraph(comment='NixOS Gateway Topology', format=format)
        dot.attr(rankdir='LR')
        dot.attr('node', shape='rectangle', style='filled', color='lightblue')

        # Add Gateway Node
        hostname = config.get('networking', {}).get('hostName', 'gateway')
        domain = config.get('networking', {}).get('domain', "")
        fqdn = f"{hostname}.{domain}" if domain else hostname
        
        dot.node('gateway', fqdn, shape='diamond', color='#ff6b6b')

        # Add Interfaces
        interfaces = config.get('networking', {}).get('interfaces', {})
        for name, iface in interfaces.items():
            node_id = f"iface_{name}"
            label = f"{name}"
            
            ipv4 = iface.get('ipv4', {}).get('addresses', [])
            if ipv4:
                addr = ipv4[0].get('address', 'unknown')
                label += f"\n{addr}"
            
            dot.node(node_id, label, shape='ellipse', color='#4ecdc4')
            dot.edge('gateway', node_id, label='owns')

        # Add Services (if we had more info about connected peers, we'd add them here)
        # For now, let's visualize active services
        services = config.get('services', {})
        active_services = []
        
        if services.get('openssh', {}).get('enable'):
            active_services.append('SSH')
        
        # Add a node for services
        if active_services:
            services_label = "Active Services:\n" + "\n".join(active_services)
            dot.node('services', services_label, shape='note', color='#ffeaa7')
            dot.edge('gateway', 'services', style='dashed')

        try:
            dot.render(output_path, view=False)
            print(f"Topology generated at {output_path}.{format}")
        except Exception as e:
            print(f"Error rendering topology: {e}", file=sys.stderr)
            sys.exit(1)

    if __name__ == "__main__":
        parser = argparse.ArgumentParser(description="Generate network topology visualization")
        parser.add_argument("--config", required=True, help="Path to JSON configuration")
        parser.add_argument("--output", required=True, help="Output file path (without extension)")
        parser.add_argument("--format", default="svg", choices=['svg', 'png', 'pdf'], help="Output format")
        
        args = parser.parse_args()
        generate_topology(args.config, args.output, args.format)
  '';

  topologyGeneratorBin = pkgs.writeScriptBin "gateway-topology" ''
    #!${pkgs.python3.withPackages (ps: [ ps.graphviz ])}/bin/python3
    ${topologyGeneratorScript}
  '';

in
{
  options.services.gateway.topologyGenerator = {
    enable = mkEnableOption "Visual Topology Generator";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      topologyGeneratorBin
      pkgs.graphviz # Runtime dependency for the python module
    ];

    # Shell alias for quick generation using current system config
    environment.shellAliases = {
      "generate-topology" = "gateway-topology --config ${
        pkgs.writeText "system-config.json" (
          builtins.toJSON {
            networking = {
              hostName = config.networking.hostName;
              domain = config.networking.domain;
              interfaces = lib.mapAttrs (name: iface: {
                ipv4 = iface.ipv4;
                ipv6 = iface.ipv6;
              }) config.networking.interfaces;
            };
            services = {
              openssh = config.services.openssh or { };
            };
          }
        )
      } --output topology";
    };
  };
}

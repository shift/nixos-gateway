{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    mkOption
    types
    mkIf
    mkEnableOption
    ;
  cfg = config.services.gateway.topologyGenerator;

  visualizerLib = import ../lib/visualizer.nix { inherit pkgs; };

  # Script to run the topology generator
  topologyGeneratorScript = pkgs.writeScriptBin "gateway-topology-generator" ''
    #!${pkgs.python3}/bin/python3
    import argparse
    import json
    import os
    import sys

    def generate_json(config_path, output_path):
        print(f"Generating JSON topology from {config_path} to {output_path}")
        # Mock generation logic
        topology = {
            "nodes": [
                {"id": "gateway", "type": "gateway", "label": "NixOS Gateway"},
                {"id": "lan", "type": "network", "label": "LAN"},
                {"id": "wan", "type": "network", "label": "WAN"}
            ],
            "links": [
                {"source": "gateway", "target": "lan"},
                {"source": "gateway", "target": "wan"}
            ]
        }
        
        with open(output_path, 'w') as f:
            json.dump(topology, f, indent=2)
        print("JSON topology generated successfully.")

    def generate_dot(config_path, output_path):
        print(f"Generating Graphviz DOT topology from {config_path} to {output_path}")
        # Mock DOT generation
        dot_content = """graph network {
            gateway [label="NixOS Gateway", shape=box];
            lan [label="LAN", shape=oval];
            wan [label="WAN", shape=oval];
            gateway -- lan;
            gateway -- wan;
        }"""
        
        with open(output_path, 'w') as f:
            f.write(dot_content)
        print("DOT topology generated successfully.")

    def main():
        parser = argparse.ArgumentParser(description="Visual Topology Generator")
        parser.add_argument("command", choices=["generate"], help="Command to execute")
        parser.add_argument("--format", choices=["json", "dot"], default="json", help="Output format")
        parser.add_argument("--output", required=True, help="Output file path")
        parser.add_argument("--config", default="/etc/nixos", help="Configuration source path")
        
        args = parser.parse_args()
        
        if args.command == "generate":
            if args.format == "json":
                generate_json(args.config, args.output)
            elif args.format == "dot":
                generate_dot(args.config, args.output)

    if __name__ == "__main__":
        main()
  '';

in
{
  options.services.gateway.topologyGenerator = {
    enable = mkEnableOption "Visual Topology Generator";

    outputDir = mkOption {
      type = types.path;
      default = "/var/lib/gateway/topology";
      description = "Directory to store generated topology files";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ topologyGeneratorScript ];

    systemd.tmpfiles.rules = [
      "d ${cfg.outputDir} 0755 root root -"
    ];
  };
}

{ pkgs }:

let
  topologyGenerator = pkgs.writeScriptBin "gateway-topology-generator" ''
    #!${pkgs.python3}/bin/python3
    import json
    import sys
    import os
    import argparse
    from dataclasses import dataclass, asdict
    from typing import List, Dict, Optional, Any

    @dataclass
    class Node:
        id: str
        label: str
        type: str
        group: str = "default"
        data: Dict[str, Any] = None

    @dataclass
    class Edge:
        id: str
        source: str
        target: str
        type: str
        label: str = ""
        data: Dict[str, Any] = None

    @dataclass
    class Graph:
        nodes: List[Node]
        edges: List[Edge]

    class TopologyGenerator:
        def __init__(self):
            self.nodes: Dict[str, Node] = {}
            self.edges: List[Edge] = []

        def add_node(self, id: str, label: str, type: str, group: str = "default", data: Dict = None):
            self.nodes[id] = Node(id, label, type, group, data or {})

        def add_edge(self, source: str, target: str, type: str, label: str = "", data: Dict = None):
            edge_id = f"{source}-{target}-{type}"
            self.edges.append(Edge(edge_id, source, target, type, label, data or {}))

        def load_from_config(self, config_file: str):
            try:
                with open(config_file, 'r') as f:
                    config = json.load(f)
                
                # Create root gateway node
                self.add_node("gateway", "Gateway", "gateway", "infrastructure")

                # Parse Interfaces
                if "networking" in config and "interfaces" in config["networking"]:
                    for iface, data in config["networking"]["interfaces"].items():
                        node_id = f"iface_{iface}"
                        self.add_node(node_id, iface, "interface", "network", data)
                        self.add_edge("gateway", node_id, "contains")

                        # If interface has networks attached (simplified)
                        if "ipv4" in data and "addresses" in data["ipv4"]:
                             for addr in data["ipv4"]["addresses"]:
                                 net_id = f"net_{addr['address']}"
                                 self.add_node(net_id, addr['address'], "network", "subnet")
                                 self.add_edge(node_id, net_id, "connected")

                # Parse Services (e.g. DHCP leases if static)
                if "services" in config and "dhcpd4" in config["services"]:
                    # Placeholder for DHCP logic
                    pass

            except Exception as e:
                print(f"Error loading config: {e}")
                sys.exit(1)

        def export_json(self) -> str:
            graph = Graph(list(self.nodes.values()), self.edges)
            return json.dumps(asdict(graph), indent=2)

        def export_dot(self) -> str:
            output = ["digraph NetworkTopology {"]
            output.append("  node [shape=box style=filled];")
            
            for node in self.nodes.values():
                color = "lightgrey"
                if node.type == "gateway": color = "lightblue"
                elif node.type == "interface": color = "lightgreen"
                elif node.type == "network": color = "lightyellow"
                
                output.append(f'  "{node.id}" [label="{node.label}\\n({node.type})" fillcolor="{color}"];')

            for edge in self.edges:
                style = "solid"
                if edge.type == "contains": style = "bold"
                output.append(f'  "{edge.source}" -> "{edge.target}" [label="{edge.label}" style={style}];')

            output.append("}")
            return "\n".join(output)
        
        def export_html(self) -> str:
            # Simple Vis.js embedded template
            data = self.export_json()
            return f"""
            <!DOCTYPE html>
            <html>
            <head>
                <title>Network Topology</title>
                <script type="text/javascript" src="https://unpkg.com/vis-network/standalone/umd/vis-network.min.js"></script>
                <style type="text/css">
                    #mynetwork {{ width: 100%; height: 800px; border: 1px solid lightgray; }}
                </style>
            </head>
            <body>
                <div id="mynetwork"></div>
                <script type="text/javascript">
                    var data = {data};
                    var nodes = new vis.DataSet(data.nodes);
                    var edges = new vis.DataSet(data.edges);
                    var container = document.getElementById('mynetwork');
                    var network = new vis.Network(container, {{nodes: nodes, edges: edges}}, {{}});
                </script>
            </body>
            </html>
            """

    def main():
        parser = argparse.ArgumentParser(description="Network Topology Generator")
        parser.add_argument("config", help="Path to config file (JSON)")
        parser.add_argument("--format", choices=["json", "dot", "html"], default="json", help="Output format")
        
        args = parser.parse_args()

        generator = TopologyGenerator()
        generator.load_from_config(args.config)

        if args.format == "json":
            print(generator.export_json())
        elif args.format == "dot":
            print(generator.export_dot())
        elif args.format == "html":
            print(generator.export_html())

    if __name__ == "__main__":
        main()
  '';
in
{
  inherit topologyGenerator;
}

{ pkgs }:

let
  trafficManager = pkgs.writeScriptBin "gateway-traffic-manager" ''
    #!${pkgs.python3}/bin/python3
    import json
    import sys
    import random
    import hashlib
    import time
    from dataclasses import dataclass
    from typing import List, Dict, Optional, Any

    @dataclass
    class RealServer:
        address: str
        port: int
        weight: int
        max_connections: int
        current_connections: int = 0
        healthy: bool = True
        response_time_ms: float = 0.0

    class LoadBalancer:
        def __init__(self, config_file: str):
            self.config_file = config_file
            self.load_config()

        def load_config(self):
            try:
                with open(self.config_file, 'r') as f:
                    self.config = json.load(f)
            except FileNotFoundError:
                print(f"Error: Config file {self.config_file} not found")
                sys.exit(1)
            except json.JSONDecodeError:
                print(f"Error: Invalid JSON in {self.config_file}")
                sys.exit(1)

        def validate_config(self) -> bool:
            # Basic validation
            if "virtualServices" not in self.config:
                print("Error: No virtualServices defined")
                return False
            
            for vs in self.config["virtualServices"]:
                required = ["name", "virtualIp", "port", "protocol", "algorithm", "realServers"]
                if not all(k in vs for k in required):
                    print(f"Error: Missing required fields in virtual service {vs.get('name', 'unknown')}")
                    return False
                
                # Validate Algorithm
                algo = vs["algorithm"]
                valid_algos = ["round-robin", "weighted-round-robin", "least-connections", "ip-hash", "response-time"]
                if algo not in valid_algos:
                    print(f"Error: Invalid algorithm {algo} in {vs['name']}")
                    return False

            return True

        def select_server(self, service_name: str, client_ip: str = "127.0.0.1") -> Optional[Dict[str, Any]]:
            service = next((s for s in self.config["virtualServices"] if s["name"] == service_name), None)
            if not service:
                print(f"Service {service_name} not found")
                return None

            servers = service["realServers"]
            # Filter healthy servers (mocking health status as always true for basic logic unless strictly defined)
            # In a real scenario, this would check a dynamic state file
            available_servers = servers # Assume all healthy for logic demo

            if not available_servers:
                return None

            algo = service["algorithm"]

            if algo == "round-robin":
                # Stateless round robin for demo (random pick effectively if stateless)
                # In stateful, we'd cycle. Here we'll just pick random to simulate distribution over time
                # actually, let's just pick index 0 for deterministic unit testing if singular call,
                # or use a counter file in real implementation.
                # For this task, let's emulate "random" as a simple distribution
                return random.choice(available_servers)

            elif algo == "weighted-round-robin":
                total_weight = sum(s.get("weight", 1) for s in available_servers)
                r = random.uniform(0, total_weight)
                upto = 0
                for s in available_servers:
                    if upto + s.get("weight", 1) >= r:
                        return s
                    upto += s.get("weight", 1)
                return available_servers[0]

            elif algo == "least-connections":
                # Mock current connections
                return min(available_servers, key=lambda s: s.get("currentConnections", 0))

            elif algo == "ip-hash":
                hash_val = int(hashlib.md5(client_ip.encode()).hexdigest(), 16)
                return available_servers[hash_val % len(available_servers)]
            
            elif algo == "response-time":
                # Mock response time - lowest is best
                # If not present, assume 0
                return min(available_servers, key=lambda s: s.get("responseTime", 0))

            return available_servers[0]

        def generate_haproxy_config(self) -> str:
            # Simulate generating an HAProxy config fragment
            output = []
            output.append("global")
            output.append("    log /dev/log local0")
            output.append("")
            output.append("defaults")
            output.append("    mode http")
            output.append("    timeout connect 5000ms")
            output.append("    timeout client 50000ms")
            output.append("    timeout server 50000ms")
            output.append("")

            for vs in self.config.get("virtualServices", []):
                output.append(f"frontend {vs['name']}_front")
                output.append(f"    bind {vs['virtualIp']}:{vs['port']}")
                output.append(f"    default_backend {vs['name']}_back")
                output.append("")
                output.append(f"backend {vs['name']}_back")
                
                algo_map = {
                    "round-robin": "roundrobin",
                    "weighted-round-robin": "roundrobin", # Handled by weight param
                    "least-connections": "leastconn",
                    "ip-hash": "source",
                    "response-time": "roundrobin" # HAProxy doesn't have native "response-time" exactly like this without modules, fallback to RR
                }
                output.append(f"    balance {algo_map.get(vs['algorithm'], 'roundrobin')}")
                
                for idx, rs in enumerate(vs["realServers"]):
                    weight = rs.get("weight", 1)
                    max_conn = rs.get("maxConnections", 100)
                    output.append(f"    server srv{idx} {rs['address']}:{rs['port']} weight {weight} maxconn {max_conn} check")
                output.append("")
            
            return "\n".join(output)

    def main():
        if len(sys.argv) < 2:
            print("Usage: gateway-traffic-manager <command> [args]")
            print("Commands: validate, simulate-route <service> <ip>, generate-config")
            sys.exit(1)

        command = sys.argv[1]
        
        # In a real NixOS module this would be passed via a wrapper or environment variable
        config_path = "/etc/gateway/load-balancing/config.json"
        if len(sys.argv) > 2 and command == "validate":
             config_path = sys.argv[2]
        
        lb = LoadBalancer(config_path)

        if command == "validate":
            if lb.validate_config():
                print("Configuration is valid")
                sys.exit(0)
            else:
                sys.exit(1)

        elif command == "simulate-route":
            if len(sys.argv) < 4:
                print("Usage: gateway-traffic-manager simulate-route <service_name> <client_ip>")
                sys.exit(1)
            service = sys.argv[2]
            ip = sys.argv[3]
            server = lb.select_server(service, ip)
            if server:
                print(json.dumps(server))
            else:
                print("No server available")
                sys.exit(1)

        elif command == "generate-config":
            print(lb.generate_haproxy_config())

        else:
            print(f"Unknown command: {command}")
            sys.exit(1)

    if __name__ == "__main__":
        main()
  '';
in
{
  inherit trafficManager;
}

{ pkgs }:

let
  syncManager = pkgs.writeScriptBin "gateway-sync-manager" ''
    #!${pkgs.python3}/bin/python3
    import json
    import sys
    import os
    import time
    import hashlib
    import socket
    import shutil
    from dataclasses import dataclass, asdict
    from typing import List, Dict, Optional, Any
    from datetime import datetime

    @dataclass
    class Node:
        name: str
        address: str
        role: str
        last_seen: float = 0.0

    @dataclass
    class StateUpdate:
        type: str
        key: str
        value: Any
        timestamp: float
        source_node: str
        version: int = 1

    class StateStore:
        def __init__(self, storage_dir: str):
            self.storage_dir = storage_dir
            self.state: Dict[str, Dict[str, Any]] = {
                "configuration": {},
                "database": {},
                "connection": {},
                "session": {}
            }
            self.vector_clocks: Dict[str, Dict[str, int]] = {}
            os.makedirs(storage_dir, exist_ok=True)
            self.load_state()

        def load_state(self):
            state_file = os.path.join(self.storage_dir, "state.json")
            if os.path.exists(state_file):
                try:
                    with open(state_file, 'r') as f:
                        data = json.load(f)
                        self.state = data.get("state", self.state)
                        self.vector_clocks = data.get("vector_clocks", {})
                except Exception as e:
                    print(f"Error loading state: {e}")

        def save_state(self):
            state_file = os.path.join(self.storage_dir, "state.json")
            with open(state_file, 'w') as f:
                json.dump({
                    "state": self.state,
                    "vector_clocks": self.vector_clocks,
                    "last_updated": time.time()
                }, f, indent=2)

        def update(self, category: str, key: str, value: Any, source: str, timestamp: float):
            if category not in self.state:
                self.state[category] = {}
            
            current_clock = self.vector_clocks.get(category, {}).get(key, 0)
            
            # Simple conflict resolution: Last Writer Wins based on timestamp
            # In a real implementation, this would use vector clocks more robustly
            current_val = self.state[category].get(key)
            if current_val:
                # If we have existing data, check timestamp or value hash
                pass

            self.state[category][key] = value
            if category not in self.vector_clocks:
                self.vector_clocks[category] = {}
            self.vector_clocks[category][key] = current_clock + 1
            self.save_state()
            return True

        def get(self, category: str, key: str) -> Optional[Any]:
            return self.state.get(category, {}).get(key)

        def get_all(self, category: str) -> Dict[str, Any]:
            return self.state.get(category, {})

    class SyncManager:
        def __init__(self, config_file: str):
            self.config_file = config_file
            self.load_config()
            self.store = StateStore("/var/lib/gateway/state-sync")
            self.node_name = socket.gethostname()

        def load_config(self):
            try:
                with open(self.config_file, 'r') as f:
                    self.config = json.load(f)
            except Exception as e:
                print(f"Error loading config: {e}")
                sys.exit(1)

        def validate_config(self) -> bool:
            required_fields = ["cluster", "stateTypes"]
            if not all(k in self.config for k in required_fields):
                print("Missing required config fields")
                return False
            return True

        def simulate_sync(self, category: str, data: Dict[str, Any], target_node: str):
            # Simulate sending data to another node
            # In production this would use TCP/UDP sockets
            update = StateUpdate(
                type=category,
                key="batch_update",
                value=data,
                timestamp=time.time(),
                source_node=self.node_name
            )
            print(f"Syncing {category} to {target_node}: {len(data)} items")
            return True

        def handle_update(self, update_json: str):
            try:
                data = json.loads(update_json)
                self.store.update(
                    data["type"],
                    data["key"],
                    data["value"],
                    data["source_node"],
                    data["timestamp"]
                )
                print(f"Processed update for {data['key']}")
            except Exception as e:
                print(f"Error handling update: {e}")

    def main():
        if len(sys.argv) < 2:
            print("Usage: gateway-sync-manager <command> [args]")
            sys.exit(1)

        command = sys.argv[1]
        config_path = "/etc/gateway/state-sync/config.json"
        
        if len(sys.argv) > 2 and command == "validate":
             config_path = sys.argv[2]
        
        manager = SyncManager(config_path)

        if command == "validate":
            if manager.validate_config():
                print("Configuration is valid")
                sys.exit(0)
            else:
                sys.exit(1)
                
        elif command == "update-state":
            if len(sys.argv) < 5:
                print("Usage: update-state <category> <key> <value>")
                sys.exit(1)
            category = sys.argv[2]
            key = sys.argv[3]
            value = sys.argv[4]
            manager.store.update(category, key, value, "local", time.time())
            print(f"State updated: {category}/{key}")
            
        elif command == "get-state":
            if len(sys.argv) < 4:
                print("Usage: get-state <category> <key>")
                sys.exit(1)
            val = manager.store.get(sys.argv[2], sys.argv[3])
            print(json.dumps(val))

        elif command == "simulate-sync":
            # Simulate syncing current state to a peer
            category = sys.argv[2] if len(sys.argv) > 2 else "configuration"
            data = manager.store.get_all(category)
            manager.simulate_sync(category, data, "peer-01")

    if __name__ == "__main__":
        main()
  '';
in
{
  inherit syncManager;
}

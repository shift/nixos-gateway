{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.gateway.configDiff;

  # Configuration dumper script (reusing the safe-dumping logic from Task 34/35)
  # We export a focused subset of the configuration to avoid infinite recursion.
  dumpConfigScript = pkgs.writeScriptBin "gateway-config-dump" ''
    #!${pkgs.stdenv.shell}

    # Create a temporary file for the config
    tmp_file=$(mktemp)

    ${pkgs.nix}/bin/nix-instantiate --eval --strict --json -E '
      let
        pkgs = import ${pkgs.path} {};
        lib = pkgs.lib;
        
        # We need to construct a "safe" version of the config
        # similar to what we did for the validator and topology generator
        
        # Helper to safely get attributes
        safeGet = path: default: 
          let parts = lib.splitString "." path;
          in lib.attrByPath parts default config;

        # Construct the exportable configuration
        exportable = {
          networking = {
            hostName = safeGet "networking.hostName" "";
            domain = safeGet "networking.domain" "";
            interfaces = safeGet "networking.interfaces" {};
            firewall = {
              allowedTCPPorts = safeGet "networking.firewall.allowedTCPPorts" [];
              allowedUDPPorts = safeGet "networking.firewall.allowedUDPPorts" [];
              enable = safeGet "networking.firewall.enable" false;
            };
            useDHCP = safeGet "networking.useDHCP" false;
          };
          
          services = {
             gateway = safeGet "services.gateway" {};
             openssh = {
               enable = safeGet "services.openssh.enable" false;
               ports = safeGet "services.openssh.ports" [22];
             };
          };
          
          system = {
            stateVersion = safeGet "system.stateVersion" "";
          };
          
          users = safeGet "users" {};
        };
      in
        exportable
    ' > "$tmp_file"

    cat "$tmp_file"
    rm "$tmp_file"
  '';

  # Python script for Diffing and Impact Analysis
  diffToolScript = pkgs.writeScriptBin "gateway-diff" ''
    #!${pkgs.python3}/bin/python3
    import sys
    import json
    import argparse
    import os
    import subprocess
    from difflib import unified_diff
    from typing import Dict, Any, List

    # ANSI Colors
    class Colors:
        HEADER = '\033[95m'
        BLUE = '\033[94m'
        GREEN = '\033[92m'
        YELLOW = '\033[93m'
        RED = '\033[91m'
        ENDC = '\033[0m'
        BOLD = '\033[1m'

    def load_json(path: str) -> Dict[str, Any]:
        with open(path, 'r') as f:
            return json.load(f)

    def get_nested(data: Dict, path: List[str]) -> Any:
        curr = data
        for key in path:
            if isinstance(curr, dict) and key in curr:
                curr = curr[key]
            else:
                return None
        return curr

    def compare_dicts(d1: Dict, d2: Dict, path="") -> List[str]:
        changes = []
        all_keys = set(d1.keys()) | set(d2.keys())
        
        for key in all_keys:
            new_path = f"{path}.{key}" if path else key
            val1 = d1.get(key)
            val2 = d2.get(key)
            
            if isinstance(val1, dict) and isinstance(val2, dict):
                changes.extend(compare_dicts(val1, val2, new_path))
            elif val1 != val2:
                # Format change
                if val1 is None:
                    changes.append(f"ADDED: {new_path} = {val2}")
                elif val2 is None:
                    changes.append(f"REMOVED: {new_path} (was {val1})")
                else:
                    changes.append(f"CHANGED: {new_path} | {val1} -> {val2}")
                    
        return changes

    def analyze_impact(changes: List[str]) -> List[str]:
        impacts = []
        for change in changes:
            if "networking.firewall" in change:
                impacts.append(f"{Colors.RED}[SECURITY] Firewall configuration changed: {change}{Colors.ENDC}")
            elif "services.openssh" in change:
                impacts.append(f"{Colors.RED}[SECURITY] SSH configuration changed: {change}{Colors.ENDC}")
            elif "networking.interfaces" in change:
                impacts.append(f"{Colors.YELLOW}[NETWORK] Interface configuration changed: {change}{Colors.ENDC}")
            elif "users" in change:
                impacts.append(f"{Colors.RED}[SECURITY] User configuration changed: {change}{Colors.ENDC}")
            elif "services.gateway" in change:
                impacts.append(f"{Colors.BLUE}[SERVICE] Gateway service changed: {change}{Colors.ENDC}")
        return impacts

    def main():
        parser = argparse.ArgumentParser(description="NixOS Gateway Config Diff Tool")
        subparsers = parser.add_subparsers(dest="command", help="Command to run")

        # Snapshot command
        snap_parser = subparsers.add_parser("snapshot", help="Snapshot current configuration to a file")
        snap_parser.add_argument("output", help="Output JSON file path")

        # Compare command
        comp_parser = subparsers.add_parser("compare", help="Compare two configuration files")
        comp_parser.add_argument("old", help="Old configuration JSON file")
        comp_parser.add_argument("new", help="New configuration JSON file (or 'current' to scan system)")

        args = parser.parse_args()

        # Helper to get current config
        def get_current_config():
            # Call the shell script wrapper to get JSON
            try:
                # We assume the dumper script is in the path or we call it directly if we knew the store path
                # But since this python script is wrapped, we can rely on PATH or just replicate the logic?
                # Replicating logic is hard. Let's assume the user pipes it or we call the companion binary.
                # For this implementation, let's assume 'gateway-config-dump' is in PATH.
                result = subprocess.run(["gateway-config-dump"], capture_output=True, text=True, check=True)
                return json.loads(result.stdout)
            except Exception as e:
                print(f"Error getting current config: {e}")
                sys.exit(1)

        if args.command == "snapshot":
            config = get_current_config()
            with open(args.output, 'w') as f:
                json.dump(config, f, indent=2)
            print(f"Snapshot saved to {args.output}")

        elif args.command == "compare":
            try:
                old_config = load_json(args.old)
                
                if args.new == "current":
                    new_config = get_current_config()
                else:
                    new_config = load_json(args.new)

                print(f"{Colors.HEADER}--- Configuration Diff Report ---{Colors.ENDC}")
                changes = compare_dicts(old_config, new_config)
                
                if not changes:
                    print(f"{Colors.GREEN}No changes detected.{Colors.ENDC}")
                    return

                # Print raw changes
                print(f"\n{Colors.BOLD}Detailed Changes:{Colors.ENDC}")
                for c in changes:
                    if c.startswith("ADDED"):
                        print(f"{Colors.GREEN}{c}{Colors.ENDC}")
                    elif c.startswith("REMOVED"):
                        print(f"{Colors.RED}{c}{Colors.ENDC}")
                    else:
                        print(f"{Colors.YELLOW}{c}{Colors.ENDC}")

                # Impact Analysis
                print(f"\n{Colors.BOLD}Impact Analysis:{Colors.ENDC}")
                impacts = analyze_impact(changes)
                if impacts:
                    for i in impacts:
                        print(i)
                else:
                    print("No critical impacts detected.")

            except Exception as e:
                print(f"Error during comparison: {e}")
                sys.exit(1)
        
        else:
            parser.print_help()

    if __name__ == "__main__":
        main()
  '';

in
{
  options.services.gateway.configDiff = {
    enable = mkEnableOption "Configuration Diff and Preview Tool";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      dumpConfigScript
      diffToolScript
    ];
  };
}

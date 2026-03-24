{ pkgs }:

let
  changeAnalyzer = pkgs.writeScriptBin "gateway-change-analyzer" ''
    #!${pkgs.python3}/bin/python3
    import json
    import sys
    import os
    from typing import Dict, Any, List, Optional
    from dataclasses import dataclass, asdict

    @dataclass
    class DiffEntry:
        path: str
        old_value: Any
        new_value: Any
        type: str  # modified, added, removed
        severity: str = "info"
        category: str = "general"

    class ConfigDiffer:
        def __init__(self, old_config: Dict, new_config: Dict):
            self.old = old_config
            self.new = new_config
            self.diffs: List[DiffEntry] = []
            
        def compare(self):
            self._compare_recursive(self.old, self.new, "")

        def _compare_recursive(self, old: Any, new: Any, path: str):
            if isinstance(old, dict) and isinstance(new, dict):
                all_keys = set(old.keys()) | set(new.keys())
                for key in all_keys:
                    current_path = f"{path}.{key}" if path else key
                    if key not in old:
                        self._add_diff(current_path, None, new[key], "added")
                    elif key not in new:
                        self._add_diff(current_path, old[key], None, "removed")
                    else:
                        self._compare_recursive(old[key], new[key], current_path)
            elif isinstance(old, list) and isinstance(new, list):
                if old != new:
                    self._add_diff(path, old, new, "modified")
            else:
                if old != new:
                    self._add_diff(path, old, new, "modified")

        def _add_diff(self, path: str, old: Any, new: Any, type: str):
            severity = self._assess_severity(path)
            category = self._categorize(path)
            self.diffs.append(DiffEntry(path, old, new, type, severity, category))

        def _assess_severity(self, path: str) -> str:
            path_lower = path.lower()
            if any(k in path_lower for k in ["firewall", "security", "users", "secret", "key"]):
                return "critical"
            if any(k in path_lower for k in ["interface", "enable", "ip", "port", "network"]):
                return "major"
            return "minor"
            
        def _categorize(self, path: str) -> str:
            path_lower = path.lower()
            if "networking" in path_lower or "interface" in path_lower:
                return "network"
            if "security" in path_lower or "firewall" in path_lower or "users" in path_lower:
                return "security"
            if "service" in path_lower or "systemd" in path_lower:
                return "service"
            if "monitor" in path_lower or "log" in path_lower:
                return "monitoring"
            return "general"

    def print_text_report(diffs: List[DiffEntry]):
        if not diffs:
            print("No changes detected.")
            return

        print(f"Found {len(diffs)} configuration changes:\n")
        
        categories = {}
        for d in diffs:
            if d.category not in categories:
                categories[d.category] = []
            categories[d.category].append(d)
            
        for cat, entries in categories.items():
            print(f"[{cat.upper()}]")
            for entry in entries:
                symbol = "+" if entry.type == "added" else "-" if entry.type == "removed" else "~"
                sev_marker = "!!!" if entry.severity == "critical" else "!" if entry.severity == "major" else " "
                
                old_val = str(entry.old_value) if entry.old_value is not None else "(none)"
                new_val = str(entry.new_value) if entry.new_value is not None else "(none)"
                
                # Truncate long values
                if len(old_val) > 50: old_val = old_val[:47] + "..."
                if len(new_val) > 50: new_val = new_val[:47] + "..."
                
                print(f" {sev_marker} {symbol} {entry.path}")
                if entry.type == "modified":
                    print(f"      From: {old_val}")
                    print(f"      To:   {new_val}")
                elif entry.type == "added":
                    print(f"      Value: {new_val}")
                elif entry.type == "removed":
                    print(f"      Removed: {old_val}")
            print("")

    def main():
        if len(sys.argv) < 3:
            print("Usage: gateway-change-analyzer <old_config.json> <new_config.json> [--json]")
            sys.exit(1)

        try:
            with open(sys.argv[1], 'r') as f:
                old_config = json.load(f)
            with open(sys.argv[2], 'r') as f:
                new_config = json.load(f)
        except Exception as e:
            print(f"Error loading configs: {e}")
            sys.exit(1)

        differ = ConfigDiffer(old_config, new_config)
        differ.compare()
        
        output_json = "--json" in sys.argv
        
        if output_json:
            report = [asdict(d) for d in differ.diffs]
            print(json.dumps(report, indent=2))
        else:
            print_text_report(differ.diffs)

    if __name__ == "__main__":
        main()
  '';
in
{
  inherit changeAnalyzer;
}

{ lib, pkgs }:

with lib;

let
  # Diagnostic Engine Logic in Python
  diagnosticEngineScript = pkgs.writeScriptBin "gateway-diagnostic-engine" ''
    #!${pkgs.python3}/bin/python3
    import sys
    import json
    import argparse
    import time

    class DiagnosticEngine:
        def __init__(self, config_file):
            self.config = self.load_config(config_file)
            self.history = []

        def load_config(self, path):
            try:
                with open(path, 'r') as f:
                    return json.load(f)
            except FileNotFoundError:
                print(f"Error: Config file {path} not found")
                sys.exit(1)

        def list_problems(self):
            print("Available Troubleshooting Trees:")
            for problem in self.config.get('problems', []):
                print(f" - [{problem['id']}] {problem['title']}: {problem['description']}")

        def diagnose(self, problem_id):
            problem = next((p for p in self.config.get('problems', []) if p['id'] == problem_id), None)
            if not problem:
                print(f"Error: Problem ID '{problem_id}' not found.")
                return

            print(f"\n--- Starting Diagnosis: {problem['title']} ---")
            tree = problem['decisionTree']
            current_node_id = tree['start']
            
            while True:
                node = next((n for n in tree['nodes'] if n['id'] == current_node_id), None)
                if not node:
                    print("Error: Decision tree broken (node not found).")
                    break

                answer = self.ask_question(node)
                
                if answer == 'yes':
                    next_step = node['yes']
                else:
                    next_step = node['no']

                if isinstance(next_step, dict): # It's a solution or action
                    print(f"\n[Action Required] {next_step.get('action')}")
                    print(f"Solution: {next_step.get('solution')}")
                    if next_step.get('automated'):
                         print("(Automated fix available)")
                    if next_step.get('escalation'):
                         print("(ESCALATION REQUIRED)")
                    break
                else:
                    current_node_id = next_step

        def ask_question(self, node):
            # Interactive mode simulation
            print(f"\nQ: {node['question']} (yes/no)")
            # In a real tool we would read input()
            # For automation/test we might have a mock input provider
            # Here we just default to 'no' to traverse failure paths for demo, or take arg
            return "no" 

    def main():
        parser = argparse.ArgumentParser(description="Gateway Diagnostic Engine")
        parser.add_argument("command", choices=["list", "diagnose"])
        parser.add_argument("--problem", help="Problem ID to diagnose")
        parser.add_argument("--config", default="/etc/gateway/troubleshooting/config.json", help="Config file path")
        
        args = parser.parse_args()
        
        engine = DiagnosticEngine(args.config)
        
        if args.command == "list":
            engine.list_problems()
        elif args.command == "diagnose":
            if not args.problem:
                print("Error: --problem required for diagnose command")
                return
            engine.diagnose(args.problem)

    if __name__ == "__main__":
        main()
  '';

in
{
  inherit diagnosticEngineScript;
}

{ pkgs, ... }:

let
  pythonScript = ''
    import json
    import time
    import subprocess
    import sys
    import os
    import random
    from pathlib import Path

    CONFIG_FILE = "/etc/zero-trust/config.json"
    CONTROL_FILE = "/var/lib/zero-trust/control.json"
    STATE_FILE = "/var/lib/zero-trust/state.json"

    # NFTables sets
    SET_TRUSTED = "trusted_devices"
    SET_RESTRICTED = "restricted_devices"
    TABLE_NAME = "zero_trust"
    FAMILY = "inet"

    def log(msg):
        print(f"[TrustEngine] {msg}", flush=True)

    def run_nft_cmd(cmd):
        try:
            full_cmd = ["nft"] + cmd
            subprocess.run(full_cmd, check=True, capture_output=True, text=True)
            return True
        except subprocess.CalledProcessError as e:
            log(f"NFT Error: {e.stderr}")
            return False

    def ensure_sets_exist():
        # Ideally managed by Nix, but good for robustness
        pass

    def update_nft_set(set_name, ip_list):
        # Flush set first (simple approach for this MVP)
        if not run_nft_cmd(["flush", "set", FAMILY, TABLE_NAME, set_name]):
            log(f"Failed to flush {set_name}")
        
        for ip in ip_list:
            # nftables requires elements to be wrapped in braces: { IP }
            cmd = ["add", "element", FAMILY, TABLE_NAME, set_name, "{", ip, "}"]
            log(f"Adding {ip} to {set_name} with command: nft {' '.join(cmd)}")
            if not run_nft_cmd(cmd):
                log(f"Failed to add {ip} to {set_name}")
            else:
                log(f"Successfully added {ip} to {set_name}")

    def load_control_data():
        if not os.path.exists(CONTROL_FILE):
            return {}
        try:
            with open(CONTROL_FILE, 'r') as f:
                return json.load(f)
        except Exception as e:
            log(f"Error loading control file: {e}")
            return {}

    def main():
        log("Starting Zero Trust Engine...")
        
        # Ensure data directory exists
        os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
        
        # Initial dummy state
        devices = {}

        while True:
            # 1. Read Control Inputs (Simulation of Trust Signals)
            control_data = load_control_data()
            
            # 2. Process Devices
            # Merges control data into internal state
            for ip, info in control_data.items():
                devices[ip] = info

            # 3. Classify
            trusted_ips = []
            restricted_ips = []

            for ip, info in devices.items():
                score = info.get("trust_score", 0)
                if score >= 80:
                    trusted_ips.append(ip)
                    log(f"Device {ip} score {score} -> TRUSTED")
                elif score >= 60:
                    restricted_ips.append(ip)
                    log(f"Device {ip} score {score} -> RESTRICTED")
                else:
                    restricted_ips.append(ip)
                    log(f"Device {ip} score {score} -> BLOCKED")

            # 4. Enforce
            update_nft_set(SET_TRUSTED, trusted_ips)
            update_nft_set(SET_RESTRICTED, restricted_ips)

            # 5. Export State
            try:
                with open(STATE_FILE, 'w') as f:
                    json.dump(devices, f, indent=2)
            except Exception as e:
                log(f"Error saving state: {e}")

            time.sleep(5)

    if __name__ == "__main__":
        main()
  '';
in
pkgs.writeScriptBin "zero-trust-engine" ''
  #!${pkgs.python3}/bin/python3
  ${pythonScript}
''

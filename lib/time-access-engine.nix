{ pkgs, ... }:

let
  pythonScript = ''
    import json
    import time
    import sys
    import os
    import datetime
    import subprocess
    from datetime import datetime, time as dt_time
    import pytz # Requires pytz package

    CONFIG_FILE = "/etc/time-access/config.json"
    STATE_FILE = "/var/lib/time-access/state.json"
    NFT_TABLE = "zero_trust" # Integrate with existing Zero Trust table
    NFT_SET = "time_restricted"

    def log(msg):
        print(f"[TimeAccess] {msg}", flush=True)

    def load_config():
        try:
            with open(CONFIG_FILE, 'r') as f:
                return json.load(f)
        except Exception as e:
            log(f"Error loading config: {e}")
            return {}

    def is_time_match(schedule_def, now_dt):
        # schedule_def: { days: ["Monday", ...], time: { start: "08:00", end: "18:00" }, timezone: "..." }
        
        tz_name = schedule_def.get("pattern", {}).get("timezone", "UTC")
        try:
            tz = pytz.timezone(tz_name)
        except:
            tz = pytz.UTC
            
        local_now = now_dt.astimezone(tz)
        current_day = local_now.strftime("%A")
        
        pattern = schedule_def.get("pattern", {})
        allowed_days = pattern.get("days", [])
        
        if current_day not in allowed_days:
            return False
            
        start_str = pattern.get("time", {}).get("start", "00:00")
        end_str = pattern.get("time", {}).get("end", "23:59")
        
        start_time = datetime.strptime(start_str, "%H:%M").time()
        end_time = datetime.strptime(end_str, "%H:%M").time()
        
        current_time = local_now.time()
        
        # Handle overnight schedules (e.g. 22:00 to 06:00)
        if start_time <= end_time:
            return start_time <= current_time <= end_time
        else:
            return start_time <= current_time or current_time <= end_time

    def update_nftables(allowed_ips):
        # We assume a set 'time_restricted' exists in the zero_trust table.
        # This set contains IPs that are CURRENTLY BLOCKED due to time restrictions.
        # Wait, usually policies allow access during specific times.
        # Let's flip it: 'time_allowed' set.
        # Or better: The module should define how enforcement works.
        # Let's assume we manage a set of IPs that are ALLOWED right now.
        
        # Simple approach for prototype:
        # We invoke nft command to flush and add elements.
        
        cmd_flush = f"nft flush set inet {NFT_TABLE} {NFT_SET}"
        try:
            subprocess.run(cmd_flush.split(), check=True)
        except Exception:
            pass # Maybe set doesn't exist yet
            
        if not allowed_ips:
            return

        elements = ", ".join(allowed_ips)
        cmd_add = f"nft add element inet {NFT_TABLE} {NFT_SET} {{ {elements} }}"
        try:
            subprocess.run(cmd_add.split(), check=True)
            log(f"Updated allowed IPs: {elements}")
        except Exception as e:
            log(f"NFT Error: {e}")

    def main():
        log("Starting Time-Based Access Engine...")
        os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)

        while True:
            config = load_config()
            schedules = config.get("schedules", {})
            policies = config.get("policies", [])
            
            now_utc = datetime.now(pytz.UTC)
            
            allowed_ips = set()
            
            for policy in policies:
                sched_name = policy.get("schedule")
                if sched_name not in schedules:
                    continue
                    
                schedule = schedules[sched_name]
                
                if is_time_match(schedule, now_utc):
                    # Policy is active (time window matches)
                    # Add subjects to allowed list
                    for subject in policy.get("subjects", []):
                        # Assuming subject format "ip:192.168.1.50" for simplicity in this MVP
                        if subject.startswith("ip:"):
                            allowed_ips.add(subject.split(":")[1])
            
            # Update state file
            with open(STATE_FILE, 'w') as f:
                json.dump({"allowed_ips": list(allowed_ips), "last_update": now_utc.isoformat()}, f)
            
            # Update Firewall
            # Note: The NFTables set must be created by the module first.
            update_nftables(list(allowed_ips))

            time.sleep(10)

    if __name__ == "__main__":
        main()
  '';
in
pkgs.writeScriptBin "time-access-engine" ''
  #!${pkgs.python3.withPackages (ps: [ ps.pytz ])}/bin/python3
  ${pythonScript}
''

{ pkgs, ... }:

let
  pythonScript = ''
    import json
    import time
    import sys
    import os
    import requests
    import subprocess
    import shutil
    from datetime import datetime

    CONFIG_FILE = "/etc/threat-intel/config.json"
    DATA_DIR = "/var/lib/threat-intel/feeds"
    STATE_FILE = "/var/lib/threat-intel/state.json"

    # NFTables
    NFT_TABLE = "zero_trust" 
    NFT_SET_IP = "threat_intel_ip_block"
    NFT_SET_DOMAIN = "threat_intel_domain_block"

    def log(msg):
        print(f"[ThreatIntel] {msg}", flush=True)

    def load_config():
        try:
            with open(CONFIG_FILE, 'r') as f:
                return json.load(f)
        except Exception as e:
            log(f"Error loading config: {e}")
            return {}

    def fetch_feed(feed_config):
        url = feed_config.get("url")
        feed_type = feed_config.get("type", "http")
        
        log(f"Fetching feed {feed_config.get('name')} from {url}")
        
        try:
            if feed_type == "http":
                # Basic fetch
                resp = requests.get(url, timeout=int(feed_config.get("update", {}).get("timeout", "30").strip("s")))
                resp.raise_for_status()
                return resp.text
            elif feed_type == "file":
                 path = feed_config.get("path")
                 if os.path.exists(path):
                     with open(path, 'r') as f:
                         return f.read()
                 return ""
        except Exception as e:
            log(f"Failed to fetch feed {feed_config.get('name')}: {e}")
            return None

    def parse_indicators(content, feed_config):
        indicators = set()
        fmt = feed_config.get("format", "text")
        
        # Extremely simplified parsing for MVP
        if fmt == "json":
            try:
                data = json.loads(content)
                # Assume list of strings or list of dicts with 'ip' key?
                # Let's assume list of IPs for now if it's JSON array
                if isinstance(data, list):
                    for item in data:
                        if isinstance(item, str):
                            indicators.add(item)
                        elif isinstance(item, dict):
                             # Try common keys
                             if 'ip' in item: indicators.add(item['ip'])
            except:
                pass
        else:
            # Assume one per line
            for line in content.splitlines():
                line = line.strip()
                if line and not line.startswith("#"):
                    # Basic validation: is it an IP?
                    # Very loose check
                    if "." in line and not line.startswith("http"):
                         indicators.add(line)
        
        return indicators

    def update_firewall(ip_indicators):
        if not ip_indicators:
            return

        # NFTables update
        # We need to make sure the set exists first.
        # Ideally the module ensures the set exists.
        
        cmd_flush = f"nft flush set inet {NFT_TABLE} {NFT_SET_IP}"
        try:
            subprocess.run(cmd_flush.split(), check=False, stderr=subprocess.DEVNULL)
        except:
            pass
            
        # Chunk updates to avoid huge command lines
        chunk_size = 500
        indicators_list = list(ip_indicators)
        
        for i in range(0, len(indicators_list), chunk_size):
            chunk = indicators_list[i:i+chunk_size]
            elements = ", ".join(chunk)
            
            # This might fail if some "IPs" are actually not valid IPs.
            # In a real system, we'd validate strictly.
            # Here we wrap in try/except and maybe fallback or log.
            
            cmd_add = f"nft add element inet {NFT_TABLE} {NFT_SET_IP} {{ {elements} }}"
            try:
                subprocess.run(cmd_add.split(), check=True, capture_output=True)
            except subprocess.CalledProcessError as e:
                log(f"Failed to add batch to NFTables: {e.stderr.decode()}")
                
        log(f"Updated firewall with {len(ip_indicators)} indicators")

    def main():
        log("Starting Threat Intelligence Engine...")
        os.makedirs(DATA_DIR, exist_ok=True)
        
        while True:
            config = load_config()
            feeds = config.get("feeds", {})
            
            all_ip_indicators = set()
            
            # Process Commercial Feeds
            for feed in feeds.get("commercial", []):
                content = fetch_feed(feed)
                if content:
                    all_ip_indicators.update(parse_indicators(content, feed))
            
            # Process Opensource Feeds
            for feed in feeds.get("opensource", []):
                 content = fetch_feed(feed)
                 if content:
                     all_ip_indicators.update(parse_indicators(content, feed))
            
            # Process Custom Feeds
            for feed in feeds.get("custom", []):
                 content = fetch_feed(feed)
                 if content:
                     all_ip_indicators.update(parse_indicators(content, feed))

            # Deduplication handled by set()
            
            # Enforce
            if config.get("integration", {}).get("firewall", {}).get("enable", False):
                update_firewall(all_ip_indicators)

            # Save state
            with open(STATE_FILE, 'w') as f:
                json.dump({
                    "last_update": datetime.now().isoformat(),
                    "total_indicators": len(all_ip_indicators),
                    "indicators": list(all_ip_indicators)
                }, f)
            
            # Sleep interval (simplified - constant loop for MVP)
            time.sleep(60)

    if __name__ == "__main__":
        main()
  '';
in
pkgs.writeScriptBin "threat-intel-engine" ''
  #!${pkgs.python3.withPackages (ps: [ ps.requests ])}/bin/python3
  ${pythonScript}
''

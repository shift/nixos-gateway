{ lib, pkgs, ... }:

let
  py = pkgs.python3;

  reputationScript = ''
    import json
    import os
    import sys
    import logging
    import time
    from datetime import datetime

    # Configure logging
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    logger = logging.getLogger("ReputationEngine")

    INDICATORS_FILE = "/var/lib/threat-intel/indicators.json"
    REPUTATION_DB = "/var/lib/ip-reputation/database.json"
    FIREWALL_IPSET_DIR = "/var/lib/ip-reputation/ipsets"

    def load_indicators():
        if not os.path.exists(INDICATORS_FILE):
            logger.warning("Indicators file not found. Starting with empty dataset.")
            return []
        try:
            with open(INDICATORS_FILE, 'r') as f:
                return json.load(f)
        except Exception as e:
            logger.error(f"Error loading indicators: {e}")
            return []

    def calculate_reputation_scores(indicators, config):
        scores = {}
        
        # Simple scoring algorithm:
        # Base score comes from indicator confidence.
        # If multiple sources report it, boost the score.
        
        for ind in indicators:
            val = ind.get('value')
            if not val: continue
            
            # Initialize if new
            if val not in scores:
                scores[val] = {
                    "ip": val,
                    "score": 0,
                    "sources": [],
                    "last_seen": ind.get('first_seen')
                }
            
            # Update source list
            src = ind.get('source', 'unknown')
            if src not in scores[val]['sources']:
                scores[val]['sources'].append(src)
            
            # Update base score (max confidence seen so far)
            conf = ind.get('confidence', 0)
            if conf > scores[val]['score']:
                scores[val]['score'] = conf
                
        # Apply Multi-Source Boost
        for ip, data in scores.items():
            source_count = len(data['sources'])
            if source_count > 1:
                # Add 10 points for each additional source, up to 100
                boost = (source_count - 1) * 10
                data['score'] = min(100, data['score'] + boost)
                
        return scores

    def update_ipsets(scores, thresholds):
        block_threshold = thresholds.get('block', 80)
        throttle_threshold = thresholds.get('throttle', 60)
        
        malicious_ips = []
        suspicious_ips = []
        
        for ip, data in scores.items():
            score = data['score']
            if score >= block_threshold:
                malicious_ips.append(ip)
            elif score >= throttle_threshold:
                suspicious_ips.append(ip)
                
        # Write to files (which could be loaded by ipset/nftables)
        try:
            os.makedirs(FIREWALL_IPSET_DIR, exist_ok=True)
            
            with open(os.path.join(FIREWALL_IPSET_DIR, "malicious.txt"), 'w') as f:
                f.write("\n".join(malicious_ips))
                
            with open(os.path.join(FIREWALL_IPSET_DIR, "suspicious.txt"), 'w') as f:
                f.write("\n".join(suspicious_ips))
                
            logger.info(f"Updated IP Sets: {len(malicious_ips)} malicious, {len(suspicious_ips)} suspicious")
            
        except Exception as e:
            logger.error(f"Failed to update IP sets: {e}")

    def main(config_path):
        try:
            with open(config_path, 'r') as f:
                config = json.load(f)
        except Exception as e:
            logger.error(f"Failed to load config: {e}")
            return

        indicators = load_indicators()
        logger.info(f"Loaded {len(indicators)} indicators")
        
        scores = calculate_reputation_scores(indicators, config)
        
        # Save Database
        try:
            os.makedirs(os.path.dirname(REPUTATION_DB), exist_ok=True)
            with open(REPUTATION_DB, 'w') as f:
                # Convert dict to list for easier JSON consumption if needed, or keep dict
                json.dump(scores, f, indent=2)
        except Exception as e:
            logger.error(f"Failed to save reputation DB: {e}")
            
        # Update Enforcement Points
        update_ipsets(scores, config.get('scoring', {}).get('thresholds', {}))

    if __name__ == "__main__":
        if len(sys.argv) < 2:
            print("Usage: reputation-engine <config_file>")
            sys.exit(1)
        main(sys.argv[1])
  '';
in
{
  inherit reputationScript;
}

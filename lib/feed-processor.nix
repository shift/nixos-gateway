{ lib, pkgs, ... }:

let
  py = pkgs.python3;

  feedProcessorScript = ''
    import json
    import os
    import sys
    import requests
    import csv
    import logging
    from datetime import datetime, timezone

    # Configure logging
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    logger = logging.getLogger("FeedProcessor")

    # Mock data for demonstration purposes if URL fetching fails or for testing
    MOCK_FEEDS = {
        "abuseipdb": ["192.0.2.1", "198.51.100.1", "203.0.113.1"],
        "phishstats": ["example.com", "malware.test", "phishing.site"],
        "custom": ["10.0.0.5", "bad-internal-actor.local"]
    }

    def fetch_feed(feed_config):
        """Fetch threat intelligence from configured source"""
        name = feed_config.get('name', 'unknown')
        feed_type = feed_config.get('type', 'http')
        url = feed_config.get('url')
        
        logger.info(f"Fetching feed: {name} ({feed_type})")
        
        indicators = []
        
        try:
            if feed_type == 'http' or feed_type == 'api':
                # In a real implementation, we would perform actual HTTP requests
                # For this demo/prototype, we use mock data
                logger.info(f"Using mock data for {name}")
                raw_indicators = MOCK_FEEDS.get(name, [])
                
                for ind in raw_indicators:
                    indicators.append({
                        "value": ind,
                        "source": name,
                        "type": "ip" if ind.replace(".", "").isdigit() else "domain",
                        "confidence": feed_config.get('confidence', {}).get('threshold', 50),
                        "first_seen": datetime.now(timezone.utc).isoformat()
                    })
                    
            elif feed_type == 'file':
                path = feed_config.get('path')
                if os.path.exists(path):
                     with open(path, 'r') as f:
                        # Assume one indicator per line for simplicity
                        for line in f:
                            ind = line.strip()
                            if ind:
                                indicators.append({
                                    "value": ind,
                                    "source": name,
                                    "type": "custom",
                                    "confidence": 100,
                                    "first_seen": datetime.now(timezone.utc).isoformat()
                                })
                                
        except Exception as e:
            logger.error(f"Error fetching feed {name}: {e}")
            
        return indicators

    def process_feeds(config_path, output_path):
        """Main processing loop"""
        try:
            with open(config_path, 'r') as f:
                config = json.load(f)
        except Exception as e:
            logger.error(f"Failed to load config: {e}")
            return

        all_indicators = []
        
        feeds = config.get('feeds', {})
        
        # Process Commercial Feeds
        for feed in feeds.get('commercial', []):
            all_indicators.extend(fetch_feed(feed))
            
        # Process Open Source Feeds
        for feed in feeds.get('opensource', []):
            all_indicators.extend(fetch_feed(feed))
            
        # Process Custom Feeds
        for feed in feeds.get('custom', []):
            all_indicators.extend(fetch_feed(feed))
            
        logger.info(f"Total indicators collected: {len(all_indicators)}")
        
        # Deduplication and Scoring Logic (Simplified)
        unique_indicators = {}
        for item in all_indicators:
            val = item['value']
            if val not in unique_indicators:
                unique_indicators[val] = item
            else:
                # Merge logic: take higher confidence
                if item['confidence'] > unique_indicators[val]['confidence']:
                    unique_indicators[val]['confidence'] = item['confidence']
                # Append source
                unique_indicators[val]['source'] += f", {item['source']}"

        # Write Output
        final_list = list(unique_indicators.values())
        
        try:
            os.makedirs(os.path.dirname(output_path), exist_ok=True)
            with open(output_path, 'w') as f:
                json.dump(final_list, f, indent=2)
            logger.info(f"Successfully wrote {len(final_list)} indicators to {output_path}")
        except Exception as e:
            logger.error(f"Failed to write output: {e}")

    if __name__ == "__main__":
        if len(sys.argv) < 3:
            print("Usage: feed-processor <config_file> <output_file>")
            sys.exit(1)
            
        process_feeds(sys.argv[1], sys.argv[2])
  '';
in
{
  inherit feedProcessorScript;
}

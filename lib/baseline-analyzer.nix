{ pkgs }:

let
  pythonScript = ''
    import json
    import os
    import sys
    import math
    from datetime import datetime

    METRICS_FILE = os.environ.get("METRICS_FILE", "/var/lib/gateway-baselines/metrics.json")
    BASELINE_FILE = os.environ.get("BASELINE_FILE", "/var/lib/gateway-baselines/baseline.json")
    ANOMALY_FILE = os.environ.get("ANOMALY_FILE", "/var/lib/gateway-baselines/anomalies.json")

    # Configuration
    # How many standard deviations to consider an anomaly
    Z_SCORE_THRESHOLD = float(os.environ.get("Z_SCORE_THRESHOLD", "2.0"))
    # Minimum samples before starting to alert
    MIN_SAMPLES = int(os.environ.get("MIN_SAMPLES", "5"))

    def load_json(filepath, default=None):
        if not os.path.exists(filepath):
            return default if default is not None else {}
        try:
            with open(filepath, 'r') as f:
                return json.load(f)
        except Exception as e:
            print(f"Error loading {filepath}: {e}")
            return default if default is not None else {}

    def save_json(filepath, data):
        try:
            with open(filepath, 'w') as f:
                json.dump(data, f, indent=2)
        except Exception as e:
            print(f"Error saving {filepath}: {e}")

    def update_stats(existing_stats, new_value):
        # Welford's Online Algorithm equivalent or just simple sum aggregation
        # We store count, sum, sum_sq to calculate mean and stdev
        
        n = existing_stats.get('count', 0)
        s = existing_stats.get('sum', 0.0)
        ss = existing_stats.get('sum_sq', 0.0)
        
        n += 1
        s += new_value
        ss += (new_value * new_value)
        
        return {
            'count': n,
            'sum': s,
            'sum_sq': ss,
            'last_updated': datetime.now().isoformat()
        }

    def calculate_metrics(stats):
        n = stats['count']
        if n == 0:
            return 0.0, 0.0
            
        mean = stats['sum'] / n
        
        # Variance = (SumSq - (Sum^2 / n)) / (n - 1) for sample variance
        # or / n for population. Let's use sample variance if n > 1
        if n > 1:
            variance = (stats['sum_sq'] - (stats['sum'] * stats['sum']) / n) / (n - 1)
            # Handle floating point errors leading to negative variance
            variance = max(0.0, variance)
            stdev = math.sqrt(variance)
        else:
            stdev = 0.0
            
        return mean, stdev

    def main():
        print(f"Starting analysis. Metrics: {METRICS_FILE}")
        
        # 1. Load current metrics
        current_metrics = load_json(METRICS_FILE)
        if not current_metrics:
            print("No metrics found or empty file.")
            return

        # 2. Load existing baseline history
        baselines = load_json(BASELINE_FILE, {})
        
        # 3. Load existing anomalies to append/update
        anomalies = load_json(ANOMALY_FILE, [])
        # Keep only recent anomalies? For now just append and let logrotate handle file size or just keep last N
        if len(anomalies) > 100: 
            anomalies = anomalies[-50:]

        new_anomalies = []
        updated_baselines = baselines.copy()

        for metric_name, value in current_metrics.items():
            # Skip non-numeric
            if not isinstance(value, (int, float)):
                continue

            # Get stats for this metric
            stats = baselines.get(metric_name, {'count': 0, 'sum': 0.0, 'sum_sq': 0.0})
            
            # Calculate current mean/stdev BEFORE update to check against *previous* baseline
            # This is standard anomaly detection (check then learn)
            mean, stdev = calculate_metrics(stats)
            
            # Check for anomaly
            is_anomaly = False
            z_score = 0.0
            
            if stats['count'] >= MIN_SAMPLES and stdev > 0:
                deviation = abs(value - mean)
                z_score = deviation / stdev
                
                if z_score > Z_SCORE_THRESHOLD:
                    is_anomaly = True
                    print(f"ANOMALY DETECTED: {metric_name} = {value} (Mean: {mean:.2f}, StdDev: {stdev:.2f}, Z-Score: {z_score:.2f})")
                    new_anomalies.append({
                        'timestamp': datetime.now().isoformat(),
                        'metric': metric_name,
                        'value': value,
                        'mean': mean,
                        'stdev': stdev,
                        'z_score': z_score,
                        'threshold': Z_SCORE_THRESHOLD
                    })

            # Update stats with new value
            updated_stats = update_stats(stats, value)
            updated_baselines[metric_name] = updated_stats

        # 4. Save results
        save_json(BASELINE_FILE, updated_baselines)
        
        if new_anomalies:
            anomalies.extend(new_anomalies)
            save_json(ANOMALY_FILE, anomalies)
            
        print("Analysis complete.")

    if __name__ == "__main__":
        main()
  '';
in
pkgs.writeScriptBin "baseline-analyzer" ''
  #!${pkgs.python3}/bin/python3
  ${pythonScript}
''

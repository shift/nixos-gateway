# Quality Monitoring Library for SD-WAN
{ lib, pkgs }:

with lib;

let
  # Convert time string to seconds
  timeToSeconds =
    timeStr:
    let
      parts = splitString "" timeStr;
      numStr = head (splitString "ms" timeStr);
      num = toInt numStr;
    in
    if hasSuffix "ms" timeStr then
      num / 1000
    else if hasSuffix "s" timeStr then
      num
    else if hasSuffix "m" timeStr then
      num * 60
    else if hasSuffix "h" timeStr then
      num * 3600
    else
      num;

  # Convert bandwidth string to Mbps
  bandwidthToMbps =
    bwStr:
    let
      numStr = head (splitString "bps" bwStr);
      num = toFloat numStr;
    in
    if hasSuffix "Kbps" bwStr then
      num / 1000
    else if hasSuffix "Mbps" bwStr then
      num
    else if hasSuffix "Gbps" bwStr then
      num * 1000
    else
      num / 1000000; # Assume bps

  # Generate monitoring script for a link
  mkLinkMonitor = interface: target: interval: ''
    # Monitor link quality for ${interface}
    # Target: ${target}
    # Interval: ${interval}

    METRICS_FILE="/run/sdwan/metrics.db"

    # Initialize metrics database
    if [[ ! -f "$METRICS_FILE" ]]; then
      echo "timestamp,interface,latency,jitter,loss,bandwidth" > "$METRICS_FILE"
    fi

    while true; do
      # Measure latency and jitter
      if ping_result=$(ping -c 10 -i 0.1 -W 1 ${target} 2>/dev/null); then
        LATENCY=$(echo "$ping_result" | tail -1 | awk -F'/' '{print $5}')
        JITTER=$(echo "$ping_result" | tail -1 | awk -F'/' '{print $7}')
        LOSS=$(echo "$ping_result" | grep "packet loss" | awk '{print $6}' | sed 's/%//')
        
        # Measure bandwidth (simplified)
        BANDWIDTH=$(iperf3 -c ${target} -t 1 -f M 2>/dev/null | grep "receiver" | awk '{print $7}' || echo "0")
        
        # Record metrics
        echo "$(date +%s),${interface},$LATENCY,$JITTER,$LOSS,$BANDWIDTH" >> "$METRICS_FILE"
      else
        # Failed measurement
        echo "$(date +%s),${interface},999,999,100,0" >> "$METRICS_FILE"
      fi
      
      sleep ${interval}
    done
  '';

  # Generate Prometheus exporter script
  mkExporter = port: links: ''
    # Enhanced Prometheus exporter for SD-WAN metrics
    # Listens on port ${toString port}

    cat <<EOF > /var/run/sdwan/exporter.py
    from http.server import BaseHTTPRequestHandler, HTTPServer
    import time
    import os

    class MetricsHandler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path == '/metrics':
                self.send_response(200)
                self.send_header('Content-type', 'text/plain')
                self.end_headers()
                
                metrics = []
                metrics.append('# HELP sdwan_link_latency_ms Link latency in milliseconds')
                metrics.append('# TYPE sdwan_link_latency_ms gauge')
                metrics.append('# HELP sdwan_link_jitter_ms Link jitter in milliseconds')
                metrics.append('# TYPE sdwan_link_jitter_ms gauge')
                metrics.append('# HELP sdwan_link_loss_percent Link packet loss percentage')
                metrics.append('# TYPE sdwan_link_loss_percent gauge')
                metrics.append('# HELP sdwan_link_bandwidth_mbps Link bandwidth in Mbps')
                metrics.append('# TYPE sdwan_link_bandwidth_mbps gauge')
                
                # Read metrics from database
                metrics_file = "/run/sdwan/metrics.db"
                if os.path.exists(metrics_file):
                    with open(metrics_file, 'r') as f:
                        lines = f.readlines()
                    
                    for line in lines[1:]:  # Skip header
                        parts = line.strip().split(',')
                        if len(parts) == 6:
                            timestamp, interface, latency, jitter, loss, bandwidth = parts
                            metrics.append(f'sdwan_link_latency_ms{{interface="{interface}"}} {latency}')
                            metrics.append(f'sdwan_link_jitter_ms{{interface="{interface}"}} {jitter}')
                            metrics.append(f'sdwan_link_loss_percent{{interface="{interface}"}} {loss}')
                            metrics.append(f'sdwan_link_bandwidth_mbps{{interface="{interface}"}} {bandwidth}')
                
                self.wfile.write('\\n'.join(metrics).encode())
            else:
                self.send_response(404)
                self.end_headers()

    server = HTTPServer(('0.0.0.0', ${toString port}), MetricsHandler)
    server.serve_forever()
    EOF

    python3 /var/run/sdwan/exporter.py
  '';

  # Quality evaluation function
  evaluateQuality = metrics: thresholds: ''
    # Evaluate link quality based on metrics and thresholds
    local latency=$1
    local jitter=$2
    local loss=$3
    local bandwidth=$4
    local max_latency=$5
    local max_jitter=$6
    local max_loss=$7
    local min_bandwidth=$8

    # Calculate quality scores (0-100)
    local latency_score=$(echo "scale=2; (1 - ($latency / $max_latency)) * 100" | bc -l 2>/dev/null || echo "0")
    local jitter_score=$(echo "scale=2; (1 - ($jitter / $max_jitter)) * 100" | bc -l 2>/dev/null || echo "0")
    local loss_score=$(echo "scale=2; (1 - ($loss / $max_loss)) * 100" | bc -l 2>/dev/null || echo "0")
    local bandwidth_score=$(echo "scale=2; ($bandwidth / $min_bandwidth) * 100" | bc -l 2>/dev/null || echo "0")

    # Weighted average score
    local quality_score=$(echo "scale=2; ($latency_score * 0.3 + $jitter_score * 0.3 + $loss_score * 0.2 + $bandwidth_score * 0.2)" | bc -l)

    # Clamp to 0-100 range
    echo "$quality_score" | awk '{if($1<0) print 0; else if($1>100) print 100; else print $1}'
  '';

  # Link health check
  checkLinkHealth = interface: thresholds: ''
    # Check if link meets quality thresholds
    local interface=$1
    local max_latency=$2
    local max_jitter=$3
    local max_loss=$4
    local min_bandwidth=$5

    # Get latest metrics
    local latest_metrics=$(tail -1 "/run/sdwan/metrics.db" | grep ",$interface,")

    if [[ -z "$latest_metrics" ]]; then
      echo "unknown"
      return
    fi

    IFS=',' read -r timestamp iface latency jitter loss bandwidth <<< "$latest_metrics"

    # Check if metrics exceed thresholds
    if (( $(echo "$latency > $max_latency || $jitter > $max_jitter || $loss > $max_loss || $bandwidth < $min_bandwidth" | bc -l) )); then
      echo "failed"
    else
      echo "healthy"
    fi
  '';

  # Historical quality analysis
  analyzeHistoricalQuality = interface: duration: ''
    # Analyze quality trends over time
    local interface=$1
    local duration=$2  # in seconds
    local cutoff_time=$(($(date +%s) - duration))

    # Get historical data
    local historical_data=$(awk -F, -v iface="$interface" -v cutoff="$cutoff_time" \
      '$2 == iface && $1 > cutoff' "/run/sdwan/metrics.db")

    if [[ -z "$historical_data" ]]; then
      echo "no_data"
      return
    fi

    # Calculate averages
    local avg_latency=$(echo "$historical_data" | awk -F, '{sum+=$3; count++} END {if(count>0) print sum/count; else print 0}')
    local avg_jitter=$(echo "$historical_data" | awk -F, '{sum+=$4; count++} END {if(count>0) print sum/count; else print 0}')
    local avg_loss=$(echo "$historical_data" | awk -F, '{sum+=$5; count++} END {if(count>0) print sum/count; else print 0}')
    local avg_bandwidth=$(echo "$historical_data" | awk -F, '{sum+=$6; count++} END {if(count>0) print sum/count; else print 0}')

    echo "$avg_latency,$avg_jitter,$avg_loss,$avg_bandwidth"
  '';

in
{
  inherit
    mkLinkMonitor
    mkExporter
    evaluateQuality
    checkLinkHealth
    analyzeHistoricalQuality
    timeToSeconds
    bandwidthToMbps
    ;
}

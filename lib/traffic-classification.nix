# Traffic Classification Library for SD-WAN
{ lib, pkgs }:

with lib;

let
  # Application definitions with traffic patterns
  applicationProfiles = {
    voip = {
      name = "VoIP";
      protocol = "udp";
      ports = [
        5060
        5061
        16384
        32768
      ];
      requirements = {
        maxLatency = "150ms";
        maxJitter = "30ms";
        minBandwidth = "64Kbps";
      };
      priority = "high";
      patterns = [
        "sip"
        "rtp"
        "srtp"
      ];
    };

    video = {
      name = "Video Streaming";
      protocol = "tcp";
      ports = [
        1935
        443
        80
        554
      ];
      requirements = {
        maxLatency = "200ms";
        maxJitter = "50ms";
        minBandwidth = "2Mbps";
      };
      priority = "medium";
      patterns = [
        "rtmp"
        "hls"
        "dash"
        "rtsp"
      ];
    };

    gaming = {
      name = "Gaming";
      protocol = "udp";
      ports = [
        27015
        27016
        27017
        27018
        27019
      ];
      requirements = {
        maxLatency = "50ms";
        maxJitter = "10ms";
        minBandwidth = "1Mbps";
      };
      priority = "high";
      patterns = [
        "steam"
        "udp-game"
        "tcp-game"
      ];
    };

    web = {
      name = "Web Browsing";
      protocol = "tcp";
      ports = [
        80
        443
        8080
        8443
      ];
      requirements = {
        maxLatency = "500ms";
        maxJitter = "100ms";
        minBandwidth = "512Kbps";
      };
      priority = "low";
      patterns = [
        "http"
        "https"
        "websocket"
      ];
    };

    email = {
      name = "Email";
      protocol = "tcp";
      ports = [
        25
        587
        993
        995
        110
        143
      ];
      requirements = {
        maxLatency = "1000ms";
        maxJitter = "200ms";
        minBandwidth = "128Kbps";
      };
      priority = "low";
      patterns = [
        "smtp"
        "imap"
        "pop3"
      ];
    };

    ftp = {
      name = "FTP";
      protocol = "tcp";
      ports = [
        20
        21
      ];
      requirements = {
        maxLatency = "2000ms";
        maxJitter = "500ms";
        minBandwidth = "1Mbps";
      };
      priority = "low";
      patterns = [
        "ftp"
        "ftps"
      ];
    };

    ssh = {
      name = "SSH";
      protocol = "tcp";
      ports = [ 22 ];
      requirements = {
        maxLatency = "300ms";
        maxJitter = "50ms";
        minBandwidth = "256Kbps";
      };
      priority = "medium";
      patterns = [
        "ssh"
        "scp"
        "sftp"
      ];
    };

    vpn = {
      name = "VPN";
      protocol = "udp";
      ports = [
        1194
        4500
        500
        1701
      ];
      requirements = {
        maxLatency = "200ms";
        maxJitter = "40ms";
        minBandwidth = "5Mbps";
      };
      priority = "high";
      patterns = [
        "openvpn"
        "ipsec"
        "l2tp"
      ];
    };
  };

  # Convert priority to numeric value
  priorityToNumber =
    priority:
    if priority == "critical" then
      100
    else if priority == "high" then
      75
    else if priority == "medium" then
      50
    else if priority == "low" then
      25
    else
      50;

  # Generate traffic classification script
  mkTrafficClassifier = interfaces: ''
    # Traffic Classification Script
    # Interfaces: ${lib.concatStringsSep ", " interfaces}

    CLASSIFICATION_FILE="/run/sdwan/classification.json"
    CAPTURE_DIR="/tmp/sdwan-capture"

    # Create capture directory
    mkdir -p "$CAPTURE_DIR"

    # Classification function using nDPI
    classify_traffic() {
      local interface=$1
      local capture_file="$CAPTURE_DIR/capture_''${interface}.pcap"
      local classification_file="$CAPTURE_DIR/classification_''${interface}.json"
      
      # Capture traffic for 5 seconds
      timeout 5 tcpdump -i "$interface" -w "$capture_file" 2>/dev/null || true
      
      if [[ -f "$capture_file" ]]; then
        # Classify traffic using nDPI
        ndpiReader -i "$capture_file" -c "$classification_file" 2>/dev/null || true
        
        # Extract application information
        if [[ -f "$classification_file" ]]; then
          local timestamp=$(date +%s)
          echo "''${timestamp},{\"interface\":\"$interface\",\"data\":$(cat "$classification_file")}" >> "/run/sdwan/traffic_log.csv"
        fi
        
        # Clean up
        rm -f "$capture_file"
      fi
    }

    # Main classification loop
    while true; do
      ${lib.concatMapStrings (interface: ''
        classify_traffic "${interface}"
      '') interfaces}
      
      sleep 10
    done
  '';

  # Generate application-aware routing rules
  mkApplicationRouting = applications: links: ''
    # Application-Aware Routing Rules
    # Applications: ${lib.concatStringsSep ", " (lib.attrNames applications)}
    # Links: ${lib.concatStringsSep ", " (lib.attrNames links)}

    ROUTING_TABLE=100

    # Clear existing application rules
    ip rule flush table "$ROUTING_TABLE" 2>/dev/null || true

    ${lib.concatMapStrings (appName: ''
      local app_name="${appName}"
      local app_config='${builtins.toJSON applications.${appName}}'

      # Parse application configuration
      local protocol=$(echo "$app_config" | jq -r '.protocol // "tcp"')
      local priority=$(echo "$app_config" | jq -r '.priority // "medium"')
      local ports=$(echo "$app_config" | jq -r '.ports[]? // empty')

      # Get application requirements
      local max_latency=$(echo "$app_config" | jq -r '.requirements.maxLatency // "1000ms"')
      local max_jitter=$(echo "$app_config" | jq -r '.requirements.maxJitter // "100ms"')
      local min_bandwidth=$(echo "$app_config" | jq -r '.requirements.minBandwidth // "1Mbps"')

      # Find best link for this application
      local best_link=""
      local best_score=-1

      ${lib.concatMapStrings (linkName: ''
        local link_name="${linkName}"
        local link_config='${builtins.toJSON links.${linkName}}'

        # Get link quality metrics
        local latest_metrics=$(tail -1 "/run/sdwan/metrics.db" | grep ",${linkName},")

        if [[ -n "$latest_metrics" ]]; then
          IFS=',' read -r timestamp interface latency jitter loss bandwidth <<< "$latest_metrics"
          
          # Check if link meets application requirements
          local meets_requirements=true
          
          # Convert thresholds to numeric values
          local max_latency_ms=$(echo "$max_latency" | sed 's/ms//' | sed 's/s/*1000/')
          local max_jitter_ms=$(echo "$max_jitter" | sed 's/ms//' | sed 's/s/*1000/')
          local min_bandwidth_mbps=$(echo "$min_bandwidth" | sed 's/Kbps/*1/1000' | sed 's/Mbps//' | sed 's/Gbps/*1000/')
          
          # Check requirements
          if (( $(echo "$latency > $max_latency_ms" | bc -l) )); then
            meets_requirements=false
          fi
          
          if (( $(echo "$jitter > $max_jitter_ms" | bc -l) )); then
            meets_requirements=false
          fi
          
          if (( $(echo "$bandwidth < $min_bandwidth_mbps" | bc -l) )); then
            meets_requirements=false
          fi
          
          if [[ "$meets_requirements" == "true" ]]; then
            # Calculate application-specific score
            local score=$(echo "scale=2; (100 - $latency/10 - $jitter/5 - $loss*10 + $bandwidth)" | bc -l)
            
            if (( $(echo "$score > $best_score" | bc -l) )); then
              best_score=$score
              best_link="$link_name"
            fi
          fi
        fi
      '') (lib.attrNames links)}

      # Apply routing rules if best link found
      if [[ -n "$best_link" ]]; then
        echo "Routing $app_name via $best_link (score: $best_score)"
        
        # Convert priority to numeric
        local priority_num=50
        case "$priority" in
          "critical") priority_num=100 ;;
          "high") priority_num=75 ;;
          "medium") priority_num=50 ;;
          "low") priority_num=25 ;;
        esac
        
        # Add routing rules for each port
        for port in $ports; do
          ip rule add "$protocol" dport "$port" table "$ROUTING_TABLE" priority $((100 + priority_num))
        done
        
        # Add route for best link
        ip route replace default dev "$best_link" table "$ROUTING_TABLE"
      else
        echo "No suitable link found for $app_name"
      fi
    '') (lib.attrNames applications)}
  '';

  # Generate QoS marking rules
  mkQoSMarking = applications: ''
    # QoS Marking Rules for Applications

    ${lib.concatMapStrings (appName: ''
      local app_name="${appName}"
      local app_config='${builtins.toJSON applications.${appName}}'

      # Parse application configuration
      local protocol=$(echo "$app_config" | jq -r '.protocol // "tcp"')
      local priority=$(echo "$app_config" | jq -r '.priority // "medium"')
      local ports=$(echo "$app_config" | jq -r '.ports[]? // empty')

      # Convert priority to DSCP value
      local dscp_value=0
      case "$priority" in
        "critical") dscp_value=46 ;;  # EF
        "high") dscp_value=34 ;;     # AF41
        "medium") dscp_value=26 ;;   # AF31
        "low") dscp_value=10 ;;      # AF11
      esac

      # Add QoS marking rules
      for port in $ports; do
        # Mark packets for this application
        iptables -t mangle -A PREROUTING -p "$protocol" --dport "$port" -j DSCP --set-dscp "$dscp_value"
      done
    '') (lib.attrNames applications)}
  '';

  # Generate traffic shaping rules
  mkTrafficShaping = applications: interfaces: ''
    # Traffic Shaping Rules

    ${lib.concatMapStrings (interface: ''
      # Create root qdisc for ${interface}
      tc qdisc add dev "${interface}" root handle 1: htb default 30

      # Create main class
      tc class add dev "${interface}" parent 1: classid 1:1 htb rate 1gbit

      ${lib.concatMapStrings (appName: ''
        local app_name="${appName}"
        local app_config='${builtins.toJSON applications.${appName}}'

        # Parse application configuration
        local protocol=$(echo "$app_config" | jq -r '.protocol // "tcp"')
        local priority=$(echo "$app_config" | jq -r '.priority // "medium"')
        local ports=$(echo "$app_config" | jq -r '.requirements.minBandwidth // "1Mbps"')

        # Convert bandwidth to bps
        local bandwidth_bps=$(echo "$ports" | sed 's/Kbps/*1000/' | sed 's/Mbps/*1000000/' | sed 's/Gbps/*1000000000/' | bc)

        # Determine classid based on priority
        local classid=30
        case "$priority" in
          "critical") classid=10 ;;
          "high") classid=15 ;;
          "medium") classid=20 ;;
          "low") classid=30 ;;
        esac

        # Create class for this application
        tc class add dev "${interface}" parent 1:1 classid 1:$classid htb rate "$bandwidth_bps" ceil "$bandwidth_bps"

        # Add filter for this application
        local port_list=$(echo "$app_config" | jq -r '.ports[]? // empty' | tr '\n' ' ')
        for port in $port_list; do
          tc filter add dev "${interface}" parent 1: protocol "$protocol" prio 1 u32 match "$protocol" dport "$port" 0xffffffff flowid 1:$classid
        done
      '') (lib.attrNames applications)}
    '') interfaces}
  '';

in
{
  inherit
    applicationProfiles
    mkTrafficClassifier
    mkApplicationRouting
    mkQoSMarking
    mkTrafficShaping
    priorityToNumber
    ;
}

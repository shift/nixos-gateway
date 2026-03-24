# Dynamic Routing Library for SD-WAN
{ lib, pkgs }:

with lib;

let
  # Convert time string to milliseconds
  timeToMs = timeStr:
    let
      numStr = head (splitString "ms" timeStr);
      num = toFloat numStr;
    in
      if hasSuffix "ms" timeStr then num
      else if hasSuffix "s" timeStr then num * 1000
      else if hasSuffix "m" timeStr then num * 60000
      else if hasSuffix "h" timeStr then num * 3600000
      else num * 1000;

  # Convert bandwidth string to Mbps
  bandwidthToMbps = bwStr:
    let
      numStr = head (splitString "bps" bwStr);
      num = toFloat numStr;
    in
      if hasSuffix "Kbps" bwStr then num / 1000
      else if hasSuffix "Mbps" bwStr then num
      else if hasSuffix "Gbps" bwStr then num * 1000
      else num / 1000000;  # Assume bps

  # Determine best interface based on quality metrics
  mkBestPathLogic = links: ''
    # Find interface with best quality score
    BEST_SCORE=-1
    BEST_IFACE=""
    METRICS_FILE="/run/sdwan/metrics.db"
    
    ${lib.concatMapStrings (link: ''
      # Get latest metrics for ${link}
      local latest_metrics=$(tail -1 "$METRICS_FILE" | grep ",${link},")
      
      if [[ -n "$latest_metrics" ]]; then
        IFS=',' read -r timestamp interface latency jitter loss bandwidth <<< "$latest_metrics"
        
        # Calculate quality score (0-100, higher is better)
        # Weight: latency 30%, jitter 30%, loss 20%, bandwidth 20%
        local latency_score=$(echo "scale=2; (1 - ($latency / 100)) * 100" | bc -l 2>/dev/null || echo "0")
        local jitter_score=$(echo "scale=2; (1 - ($jitter / 50)) * 100" | bc -l 2>/dev/null || echo "0")
        local loss_score=$(echo "scale=2; (1 - ($loss / 5)) * 100" | bc -l 2>/dev/null || echo "0")
        local bandwidth_score=$(echo "scale=2; ($bandwidth / 10) * 100" | bc -l 2>/dev/null || echo "0")
        
        local quality_score=$(echo "scale=2; ($latency_score * 0.3 + $jitter_score * 0.3 + $loss_score * 0.2 + $bandwidth_score * 0.2)" | bc -l)
        
        # Clamp to 0-100 range
        quality_score=$(echo "$quality_score" | awk '{if($1<0) print 0; else if($1>100) print 100; else print $1}')
        
        if (( $(echo "$quality_score > $BEST_SCORE" | bc -l) )); then
          BEST_SCORE=$quality_score
          BEST_IFACE="${link}"
        fi
      fi
    '') links}
    
    echo "Best interface: $BEST_IFACE (score: $BEST_SCORE)"
  '';

  # Application-aware routing decision
  mkAppAwareRouting = applications: links: ''
    # Application-aware routing decisions
    METRICS_FILE="/run/sdwan/metrics.db"
    ROUTING_TABLE=100
    
    ${lib.concatMapStrings (app: ''
      # Find best link for ${app.name}
      local best_link=""
      local best_score=-1
      
      ${lib.concatMapStrings (link: ''
        # Get latest metrics for ${link}
        local latest_metrics=$(tail -1 "$METRICS_FILE" | grep ",${link},")
        
        if [[ -n "$latest_metrics" ]]; then
          IFS=',' read -r timestamp interface latency jitter loss bandwidth <<< "$latest_metrics"
          
          # Check if link meets application requirements
          local meets_requirements=true
          
          ${lib.optionalString (app.requirements ? maxLatency) ''
            if (( $(echo "$latency > ${timeToMs app.requirements.maxLatency}" | bc -l) )); then
              meets_requirements=false
            fi
          ''}
          
          ${lib.optionalString (app.requirements ? maxJitter) ''
            if (( $(echo "$jitter > ${timeToMs app.requirements.maxJitter}" | bc -l) )); then
              meets_requirements=false
            fi
          ''
          
          ${lib.optionalString (app.requirements ? minBandwidth) ''
            if (( $(echo "$bandwidth < ${bandwidthToMbps app.requirements.minBandwidth}" | bc -l) )); then
              meets_requirements=false
            fi
          ''}
          
          if [[ "$meets_requirements" == "true" ]]; then
            # Calculate application-specific score
            local score=$(echo "scale=2; (100 - $latency/10 - $jitter/5 - $loss*10 + $bandwidth)" | bc -l)
            
            if (( $(echo "$score > $best_score" | bc -l) )); then
              best_score=$score
              best_link="${link}"
            fi
          fi
        fi
      '') (lib.attrValues links)}
      
      # Apply routing rules for ${app.name}
      if [[ -n "$best_link" ]]; then
        echo "Routing ${app.name} via $best_link"
        
        ${lib.concatMapStrings (port: ''
          # Add rule for ${app.protocol} port ${toString port}
          ip rule add ${app.protocol} dport ${toString port} table $ROUTING_TABLE priority $((100 + ${toString app.priority or 50}))
        '') app.ports}
        
        # Add route for best link
        ip route replace default dev "$best_link" table $ROUTING_TABLE
      else
        echo "No suitable link found for ${app.name}"
      fi
    '') (lib.mapAttrsToList (name: app: app // { inherit name; }) applications)}
  '';

  # Generate traffic steering rules
  mkSteeringRules = app: bestIface: ''
    # Route ${app.protocol} traffic on ports ${toString app.ports} via ${bestIface}
    ${lib.concatMapStrings (port: ''
      ip rule add ${app.protocol} dport ${toString port} table ${bestIface} priority ${toString app.priority or 100}
    '') app.ports}
    
    ip route add default dev "${bestIface}" table "${bestIface}"
  '';

  # Load balancing across multiple links
  mkLoadBalancing = links: algorithm: ''
    # Load balancing across multiple links
    # Algorithm: ${algorithm}
    
    case "${algorithm}" in
      "round-robin")
        # Simple round-robin distribution
        CURRENT_LINK=$(cat /run/sdwan/current_link 2>/dev/null || echo "")
        LINKS=(${lib.concatStringsSep " " (lib.attrNames links)})
        
        # Find next link
        for link in "''${LINKS[@]}"; do
          if [[ -z "$CURRENT_LINK" || "$link" == "$CURRENT_LINK" ]]; then
            # Get next link in list
            local found=false
            local next_link=""
            for l in "''${LINKS[@]}"; do
              if [[ "$found" == "true" ]]; then
                next_link="$l"
                break
              elif [[ "$l" == "$link" ]]; then
                found=true
              fi
            done
            
            # If we reached the end, start from beginning
            if [[ -z "$next_link" ]]; then
              next_link="''${LINKS[0]}"
            fi
            
            echo "$next_link" > /run/sdwan/current_link
            BEST_IFACE="$next_link"
            break
          fi
        done
        ;;
        
      "weighted")
        # Weighted load balancing based on link weights
        TOTAL_WEIGHT=0
        ${lib.concatMapStrings (link: ''
          TOTAL_WEIGHT=$((TOTAL_WEIGHT + ${toString link.weight}))
        '') (lib.attrValues links)}
        
        # Select link based on weights
        RANDOM_WEIGHT=$((RANDOM % TOTAL_WEIGHT))
        CURRENT_WEIGHT=0
        
        ${lib.concatMapStrings (link: ''
          CURRENT_WEIGHT=$((CURRENT_WEIGHT + ${toString link.weight}))
          if (( CURRENT_WEIGHT > RANDOM_WEIGHT )); then
            BEST_IFACE="${link.interface}"
          fi
        '') (lib.attrValues links)}
        ;;
        
      "quality-based")
        # Quality-based load balancing
        ${mkBestPathLogic (lib.mapAttrsToList (name: link: link.interface) links)}
        ;;
        
      *)
        # Default to best path
        ${mkBestPathLogic (lib.mapAttrsToList (name: link: link.interface) links)}
        ;;
    esac
  '';

  # Failover and recovery logic
  mkFailoverLogic = links: threshold: recoveryTime: ''
    # Failover logic with threshold: ${toString threshold}
    # Recovery time: ${recoveryTime}
    
    STATE_FILE="/run/sdwan/failover.state"
    METRICS_FILE="/run/sdwan/metrics.db"
    
    # Initialize state file
    if [[ ! -f "$STATE_FILE" ]]; then
      echo '{}' > "$STATE_FILE"
    fi
    
    ${lib.concatMapStrings (link: ''
      # Check health of ${link.interface}
      local latest_metrics=$(tail -5 "$METRICS_FILE" | grep ",${link.interface}," | tail -1)
      
      if [[ -n "$latest_metrics" ]]; then
        IFS=',' read -r timestamp interface latency jitter loss bandwidth <<< "$latest_metrics"
        
        # Determine if link is healthy
        local is_healthy=true
        if (( $(echo "$latency > 1000 || $jitter > 200 || $loss > 10" | bc -l) )); then
          is_healthy=false
        fi
        
        # Get current state
        local current_state=$(jq -r ".\"${link.interface}\".state // \"unknown\"" "$STATE_FILE")
        local failure_count=$(jq -r ".\"${link.interface}\".failure_count // 0" "$STATE_FILE")
        local last_failure=$(jq -r ".\"${link.interface}\".last_failure // 0" "$STATE_FILE")
        local current_time=$(date +%s)
        
        if [[ "$is_healthy" == "false" ]]; then
          # Link failed
          if [[ "$current_state" != "failed" ]]; then
            ((failure_count++))
            last_failure=$current_time
            
            echo "$(date): Link ${link.interface} failed (attempt $failure_count)"
            
            # Remove from routing
            ip route flush dev "${link.interface}" 2>/dev/null || true
          fi
        else
          # Link is healthy
          if [[ "$current_state" == "failed" ]]; then
            local time_since_failure=$((current_time - last_failure))
            local recovery_time_sec=$((${toString (timeToMs recoveryTime)} / 1000))
            
            if (( time_since_failure >= recovery_time_sec )); then
              echo "$(date): Link ${link.interface} recovered"
              
              # Restore routing
              ip route add default dev "${link.interface}" metric ${toString link.priority} 2>/dev/null || true
              
              failure_count=0
            fi
          fi
        fi
        
        # Update state
        jq --arg iface "${link.interface}" --arg state "$([[ "$is_healthy" == "true" ]] && echo "healthy" || echo "failed")" \
           --arg count "$failure_count" --arg time "$last_failure" \
           '.[$iface] = {state: $state, failure_count: ($count | tonumber), last_failure: ($time | tonumber)}' \
           "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
      fi
    '') (lib.attrValues links)}
  '';

in
{
  inherit 
    mkBestPathLogic 
    mkSteeringRules 
    mkAppAwareRouting 
    mkLoadBalancing 
    mkFailoverLogic
    timeToMs 
    bandwidthToMbps;
}

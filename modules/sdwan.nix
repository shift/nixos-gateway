# SD-WAN Traffic Engineering Module
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.routing.policy;

  # Quality monitoring configuration
  qualityMonitor = pkgs.writeShellScriptBin "sdwan-quality-monitor" ''
    set -euo pipefail

    # Configuration
    INTERVAL=''${SDWAN_INTERVAL:-5}
    HISTORY_RETENTION=''${SDWAN_HISTORY:-3600}
    METRICS_FILE=''${SDWAN_METRICS_FILE:-/run/sdwan/metrics.db}

    # Create metrics directory
    mkdir -p "$(dirname "$METRICS_FILE")"

    # Initialize metrics database
    if [[ ! -f "$METRICS_FILE" ]]; then
      echo "timestamp,interface,latency,jitter,loss,bandwidth" > "$METRICS_FILE"
    fi

    # Quality measurement function
    measure_quality() {
      local interface=$1
      local target_ip=$2
      
      # Measure latency and jitter using ping
      local ping_result
      if ping_result=$(ping -c 10 -i 0.1 -W 1 "$target_ip" 2>/dev/null); then
        local latency=$(echo "$ping_result" | tail -1 | awk -F'/' '{print $5}')
        local jitter=$(echo "$ping_result" | tail -1 | awk -F'/' '{print $7}')
        
        # Measure packet loss
        local loss=$(echo "$ping_result" | grep "packet loss" | awk '{print $6}' | sed 's/%//')
        
        # Measure available bandwidth (simplified)
        local bandwidth=$(iperf3 -c "$target_ip" -t 1 -f M 2>/dev/null | grep "receiver" | awk '{print $7}' || echo "0")
        
        # Record metrics
        echo "$(date +%s),$interface,$latency,$jitter,$loss,$bandwidth" >> "$METRICS_FILE"
        
        # Clean old records
        local cutoff_time=$(($(date +%s) - HISTORY_RETENTION))
        awk -F, -v cutoff="$cutoff_time" '$1 > cutoff' "$METRICS_FILE" > "$METRICS_FILE.tmp" && mv "$METRICS_FILE.tmp" "$METRICS_FILE"
        
        echo "$latency,$jitter,$loss,$bandwidth"
      else
        echo "999,999,100,0"  # Failed measurement
      fi
    }

    # Main monitoring loop
    while true; do
      ${lib.concatMapStringsSep "\n" (link: ''
        if ip link show "${link.interface}" &>/dev/null; then
          measure_quality "${link.interface}" "${link.target or "8.8.8.8"}"
        fi
      '') (lib.attrValues cfg.links)}
      
      sleep "$INTERVAL"
    done
  '';

  # Traffic classification script
  trafficClassifier = pkgs.writeShellScriptBin "sdwan-traffic-classifier" ''
    set -euo pipefail

    # Traffic classification using nDPI
    classify_traffic() {
      local interface=$1
      
      # Capture and classify traffic
      timeout 5 tcpdump -i "$interface" -w /tmp/capture.pcap 2>/dev/null || true
      
      if [[ -f /tmp/capture.pcap ]]; then
        ndpiReader -i /tmp/capture.pcap -c /tmp/classification.json 2>/dev/null || true
        rm -f /tmp/capture.pcap
      fi
    }

    # Main classification loop
    while true; do
      ${lib.concatMapStringsSep "\n" (link: ''
        classify_traffic "${link.interface}"
      '') (lib.attrValues cfg.links)}
      
      sleep 10
    done
  '';

  # Dynamic routing controller
  routingController = pkgs.writeShellScriptBin "sdwan-routing-controller" ''
    set -euo pipefail

    # Configuration
    DECISION_INTERVAL=''${SDWAN_DECISION_INTERVAL:-10}
    METRICS_FILE=''${SDWAN_METRICS_FILE:-/run/sdwan/metrics.db}
    ROUTING_TABLE=''${SDWAN_ROUTING_TABLE:-100}

    # Link quality evaluation
    evaluate_link() {
      local interface=$1
      local max_latency=$2
      local max_jitter=$3
      local max_loss=$4
      local min_bandwidth=$5
      
      # Get latest metrics
      local latest_metrics=$(tail -1 "$METRICS_FILE" | grep ",$interface,")
      
      if [[ -z "$latest_metrics" ]]; then
        echo "0"  # No data available
        return
      fi
      
      IFS=',' read -r timestamp iface latency jitter loss bandwidth <<< "$latest_metrics"
      
      # Quality score calculation (0-100)
      local latency_score=$(echo "scale=2; (1 - ($latency / $max_latency)) * 100" | bc -l 2>/dev/null || echo "0")
      local jitter_score=$(echo "scale=2; (1 - ($jitter / $max_jitter)) * 100" | bc -l 2>/dev/null || echo "0")
      local loss_score=$(echo "scale=2; (1 - ($loss / $max_loss)) * 100" | bc -l 2>/dev/null || echo "0")
      local bandwidth_score=$(echo "scale=2; ($bandwidth / $min_bandwidth) * 100" | bc -l 2>/dev/null || echo "0")
      
      # Weighted average score
      local quality_score=$(echo "scale=2; ($latency_score * 0.3 + $jitter_score * 0.3 + $loss_score * 0.2 + $bandwidth_score * 0.2)" | bc -l)
      
      # Clamp to 0-100 range
      echo "$quality_score" | awk '{if($1<0) print 0; else if($1>100) print 100; else print $1}'
    }

    # Route decision engine
    make_routing_decision() {
      local app_name=$1
      local app_config=$2
      
      # Find best link for this application
      local best_link=""
      local best_score=-1
      
      ${lib.concatMapStringsSep "\n" (link: ''
        local score=$(evaluate_link "${link.interface}" "${link.quality.maxLatency}" "${link.quality.maxJitter}" "${link.quality.maxLoss}" "${link.quality.minBandwidth}")

        if (( $(echo "$score > $best_score" | bc -l) )); then
          best_score=$score
          best_link="${link.interface}"
        fi
      '') (lib.attrValues cfg.links)}
      
      if [[ -n "$best_link" && $(echo "$best_score > 50" | bc -l) -eq 1 ]]; then
        echo "$best_link"
      else
        echo ""
      fi
    }

    # Apply routing rules
    apply_routing_rules() {
      # Clear existing SD-WAN rules
      ip rule flush table "$ROUTING_TABLE" 2>/dev/null || true
      
      ${lib.concatMapStringsSep "\n" (app: ''
        local best_link=$(make_routing_decision "${app.name}" "${app}")

        if [[ -n "$best_link" ]]; then
          # Add application-specific routing rule
          ${lib.concatMapStringsSep "\n" (port: ''
            ip rule add dport ${toString port} table "$ROUTING_TABLE" priority $((100 + ${toString app.priority or 50}))
          '') app.ports}
          
          # Add route for best link
          ip route replace default dev "$best_link" table "$ROUTING_TABLE"
        fi
      '') (lib.mapAttrsToList (name: app: app // { inherit name; }) cfg.applications)}
    }

    # Main control loop
    while true; do
      apply_routing_rules
      sleep "$DECISION_INTERVAL"
    done
  '';

  # Failover manager
  failoverManager = pkgs.writeShellScriptBin "sdwan-failover-manager" ''
    set -euo pipefail

    # Configuration
    THRESHOLD=''${SDWAN_FAILOVER_THRESHOLD:-3}
    RECOVERY_TIME=''${SDWAN_FAILOVER_RECOVERY:-60}
    METRICS_FILE=''${SDWAN_METRICS_FILE:-/run/sdwan/metrics.db}
    STATE_FILE=''${SDWAN_STATE_FILE:-/run/sdwan/failover.state}

    # Initialize state
    mkdir -p "$(dirname "$STATE_FILE")"
    echo '{}' > "$STATE_FILE"

    # Check link health
    check_link_health() {
      local interface=$1
      
      # Get recent metrics (last 5 measurements)
      local recent_metrics=$(tail -6 "$METRICS_FILE" | grep ",$interface," | tail -5)
      
      if [[ -z "$recent_metrics" ]]; then
        echo "unknown"
        return
      fi
      
      local failed_count=0
      while IFS=',' read -r timestamp iface latency jitter loss bandwidth; do
        # Check if metrics exceed thresholds
        if (( $(echo "$latency > 1000 || $jitter > 100 || $loss > 10" | bc -l) )); then
          ((failed_count++))
        fi
      done <<< "$recent_metrics"
      
      if (( failed_count >= THRESHOLD )); then
        echo "failed"
      else
        echo "healthy"
      fi
    }

    # Failover logic
    manage_failover() {
      ${lib.concatMapStringsSep "\n" (link: ''
        local health=$(check_link_health "${link.interface}")
        local current_state=$(jq -r ".\"${link.interface}\".state // \"unknown\"" "$STATE_FILE")
        local failure_count=$(jq -r ".\"${link.interface}\".failure_count // 0" "$STATE_FILE")
        local last_failure=$(jq -r ".\"${link.interface}\".last_failure // 0" "$STATE_FILE")
        local current_time=$(date +%s)

        case "$health" in
          "failed")
            if [[ "$current_state" != "failed" ]]; then
              ((failure_count++))
              last_failure=$current_time
              
              # Log failover event
              echo "$(date): Link ${link.interface} failed (attempt $failure_count)"
              
              # Update routing to exclude failed link
              ip route flush dev "${link.interface}" 2>/dev/null || true
            fi
            ;;
          "healthy")
            if [[ "$current_state" == "failed" ]]; then
              local time_since_failure=$((current_time - last_failure))
              
              if (( time_since_failure >= RECOVERY_TIME )); then
                echo "$(date): Link ${link.interface} recovered"
                
                # Restore routing for recovered link
                ip route add default dev "${link.interface}" metric $((100 + ${toString link.priority})) 2>/dev/null || true
                
                failure_count=0
              fi
            fi
            ;;
        esac

        # Update state
        jq --arg iface "${link.interface}" --arg state "$health" --arg count "$failure_count" --arg time "$last_failure" \
          '.[$iface] = {state: $state, failure_count: ($count | tonumber), last_failure: ($time | tonumber)}' \
          "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
      '') (lib.attrValues cfg.links)}
    }

    # Main failover loop
    while true; do
      manage_failover
      sleep 5
    done
  '';

in
{
  options.routing.policy = {
    enable = mkEnableOption "SD-WAN traffic engineering";

    links = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            interface = mkOption {
              type = types.str;
              description = "Network interface";
            };

            target = mkOption {
              type = types.str;
              default = "8.8.8.8";
              description = "Target for quality measurements";
            };

            weight = mkOption {
              type = types.int;
              default = 1;
              description = "Link weight for load balancing";
            };

            priority = mkOption {
              type = types.int;
              default = 100;
              description = "Link priority for failover";
            };

            quality = {
              maxLatency = mkOption {
                type = types.str;
                default = "100ms";
                description = "Maximum acceptable latency";
              };

              maxJitter = mkOption {
                type = types.str;
                default = "30ms";
                description = "Maximum acceptable jitter";
              };

              maxLoss = mkOption {
                type = types.str;
                default = "1%";
                description = "Maximum acceptable packet loss";
              };

              minBandwidth = mkOption {
                type = types.str;
                default = "1Mbps";
                description = "Minimum available bandwidth";
              };
            };
          };
        }
      );
      description = "SD-WAN link definitions";
    };

    applications = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            protocol = mkOption {
              type = types.enum [
                "tcp"
                "udp"
                "icmp"
              ];
              description = "Application protocol";
            };

            ports = mkOption {
              type = types.listOf types.port;
              description = "Application ports";
            };

            requirements = {
              maxLatency = mkOption {
                type = types.str;
                description = "Maximum latency requirement";
              };

              maxJitter = mkOption {
                type = types.str;
                description = "Maximum jitter requirement";
              };

              minBandwidth = mkOption {
                type = types.str;
                description = "Minimum bandwidth requirement";
              };
            };

            priority = mkOption {
              type = types.enum [
                "low"
                "medium"
                "high"
                "critical"
              ];
              default = "medium";
              description = "Application priority";
            };
          };
        }
      );
      description = "Application traffic profiles";
    };

    monitoring = {
      enable = mkEnableOption "SD-WAN monitoring";

      interval = mkOption {
        type = types.str;
        default = "5s";
        description = "Quality monitoring interval";
      };

      history = mkOption {
        type = types.int;
        default = 3600;
        description = "History retention time in seconds";
      };

      prometheus = {
        enable = mkEnableOption "Prometheus metrics export";
        port = mkOption {
          type = types.port;
          default = 9092;
          description = "Prometheus metrics port";
        };
      };
    };

    controller = {
      enable = mkEnableOption "SD-WAN controller";

      mode = mkOption {
        type = types.enum [
          "active"
          "passive"
          "hybrid"
        ];
        default = "active";
        description = "Controller mode";
      };

      decisionInterval = mkOption {
        type = types.str;
        default = "10s";
        description = "Route decision interval";
      };

      failover = {
        enable = mkEnableOption "Automatic failover";

        threshold = mkOption {
          type = types.int;
          default = 3;
          description = "Consecutive failures before failover";
        };

        recoveryTime = mkOption {
          type = types.str;
          default = "60s";
          description = "Time before attempting recovery";
        };
      };
    };
  };

  config = mkIf cfg.enable {
    # Required packages
    environment.systemPackages = with pkgs; [
      iproute2
      ndpi
      iperf3
      tcpdump
      bc
      jq
      qualityMonitor
      trafficClassifier
      routingController
      failoverManager
    ];

    # SD-WAN services
    systemd.services.sdwan-quality-monitor = mkIf cfg.monitoring.enable {
      description = "SD-WAN Link Quality Monitor";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        ExecStart = "${qualityMonitor}/bin/sdwan-quality-monitor";
        Restart = "always";
        RestartSec = 5;
        Environment = [
          "SDWAN_INTERVAL=${cfg.monitoring.interval}"
          "SDWAN_HISTORY=${toString cfg.monitoring.history}"
        ];
      };
    };

    systemd.services.sdwan-traffic-classifier = mkIf cfg.monitoring.enable {
      description = "SD-WAN Traffic Classifier";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        ExecStart = "${trafficClassifier}/bin/sdwan-traffic-classifier";
        Restart = "always";
        RestartSec = 10;
      };
    };

    systemd.services.sdwan-routing-controller = mkIf cfg.controller.enable {
      description = "SD-WAN Routing Controller";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
        "sdwan-quality-monitor.service"
      ];
      serviceConfig = {
        ExecStart = "${routingController}/bin/sdwan-routing-controller";
        Restart = "always";
        RestartSec = 10;
        Environment = [
          "SDWAN_DECISION_INTERVAL=${cfg.controller.decisionInterval}"
        ];
      };
    };

    systemd.services.sdwan-failover-manager =
      mkIf (cfg.controller.enable && cfg.controller.failover.enable)
        {
          description = "SD-WAN Failover Manager";
          wantedBy = [ "multi-user.target" ];
          after = [
            "network-online.target"
            "sdwan-quality-monitor.service"
          ];
          serviceConfig = {
            ExecStart = "${failoverManager}/bin/sdwan-failover-manager";
            Restart = "always";
            RestartSec = 5;
            Environment = [
              "SDWAN_FAILOVER_THRESHOLD=${toString cfg.controller.failover.threshold}"
              "SDWAN_FAILOVER_RECOVERY=${cfg.controller.failover.recoveryTime}"
            ];
          };
        };

    # Prometheus metrics exporter
    systemd.services.sdwan-prometheus-exporter =
      mkIf (cfg.monitoring.enable && cfg.monitoring.prometheus.enable)
        {
          description = "SD-WAN Prometheus Metrics Exporter";
          wantedBy = [ "multi-user.target" ];
          after = [ "sdwan-quality-monitor.service" ];
          serviceConfig = {
            ExecStart = pkgs.writeShellScript "prometheus-exporter" ''
                        set -euo pipefail
                        
                        METRICS_FILE="/run/sdwan/metrics.db"
                        PORT=${toString cfg.monitoring.prometheus.port}
                        
                        while true; do
                          if [[ -f "$METRICS_FILE" ]]; then
                            cat << EOF | nc -l -p $PORT
              # HELP sdwan_link_latency_ms Link latency in milliseconds
              # TYPE sdwan_link_latency_ms gauge
              # HELP sdwan_link_jitter_ms Link jitter in milliseconds  
              # TYPE sdwan_link_jitter_ms gauge
              # HELP sdwan_link_loss_percent Link packet loss percentage
              # TYPE sdwan_link_loss_percent gauge
              # HELP sdwan_link_bandwidth_mbps Link bandwidth in Mbps
              # TYPE sdwan_link_bandwidth_mbps gauge
              EOF
                            
                            tail -100 "$METRICS_FILE" | tail -n +2 | while IFS=',' read -r timestamp interface latency jitter loss bandwidth; do
                              echo "sdwan_link_latency_ms{interface=\"$interface\"} $latency"
                              echo "sdwan_link_jitter_ms{interface=\"$interface\"} $jitter"
                              echo "sdwan_link_loss_percent{interface=\"$interface\"} $loss"
                              echo "sdwan_link_bandwidth_mbps{interface=\"$interface\"} $bandwidth"
                            done
                          fi
                          sleep 5
                        done
            '';
            Restart = "always";
            RestartSec = 5;
          };
        };

    # Network configuration for SD-WAN
    networking = {
      # Additional routing tables for SD-WAN
      localCommands = ''
        # Create SD-WAN routing table
        echo "100 sdwan" >> /etc/iproute2/rt_tables 2>/dev/null || true

        # Initialize SD-WAN routes
        ${lib.concatMapStringsSep "\n" (link: ''
          # Add default route for ${link.interface}
          ip route add default dev "${link.interface}" table sdwan metric $((100 + ${toString link.priority})) 2>/dev/null || true
        '') (lib.attrValues cfg.links)}
      '';
    };

    # Firewall rules for SD-WAN
    networking.firewall = {
      allowedTCPPorts = mkIf cfg.monitoring.prometheus.enable [ cfg.monitoring.prometheus.port ];
      allowedUDPPorts = [ 53 ]; # DNS for quality measurements
    };
  };
}

{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.gateway.healthMonitoring or { };
  enabled = cfg.enable or false;
  gatewayCfg = config.services.gateway;

  healthChecksLib = import ../../lib/health-checks.nix { inherit lib; };

  inherit (lib)
    mkIf
    boolToString
    mapAttrsToList
    ;

  # Calculate hierarchical health scores (component -> service -> system)
  calculateHealthScores =
    stateDir:
    let
      # Component-level scoring
      calculateComponentScore = componentName: componentConfig: ''
        ${componentName}_score=0
        ${componentName}_weight=0
        ${componentName}_total_checks=0
        ${componentName}_passing_checks=0

        # Check individual component health checks
        if [ -f "${stateDir}/component/${componentName}.status" ]; then
          status=$(cat "${stateDir}/component/${componentName}.status" 2>/dev/null || echo "0")
          weight=${toString (componentConfig.weight or 1)}
          if [ "$status" = "1" ]; then
            ${componentName}_score=$(( ${componentName}_score + weight * 100 ))
            ${componentName}_passing_checks=$(( ${componentName}_passing_checks + 1 ))
          fi
          ${componentName}_weight=$(( ${componentName}_weight + weight ))
          ${componentName}_total_checks=$(( ${componentName}_total_checks + 1 ))
        fi

        # Calculate component score
        if [ "${componentName}_weight" -gt 0 ]; then
          ${componentName}_final_score=$(( ${componentName}_score / ${componentName}_weight ))
        else
          ${componentName}_final_score=0
        fi

        # Store component score
        echo "${componentName}_final_score" > "${stateDir}/component/${componentName}.score"
        echo "${componentName}_passing_checks ${componentName}_total_checks" > "${stateDir}/component/${componentName}.checks"
      '';

      # Service-level aggregation
      calculateServiceScore = serviceName: serviceConfig: ''
        ${serviceName}_score=0
        ${serviceName}_weight=0
        ${serviceName}_total_components=0
        ${serviceName}_healthy_components=0

        # Aggregate component scores for this service
        ${lib.concatStringsSep "\n" (
          map (componentName: ''
            if [ -f "${stateDir}/component/${componentName}.score" ]; then
              component_score=$(cat "${stateDir}/component/${componentName}.score" 2>/dev/null || echo "0")
              component_weight=${toString (cfg.components.${componentName}.weight or 1)}
              ${serviceName}_score=$(( ${serviceName}_score + component_score * component_weight ))
              ${serviceName}_weight=$(( ${serviceName}_weight + component_weight ))
              ${serviceName}_total_components=$(( ${serviceName}_total_components + 1 ))
              if [ "$component_score" -ge ${toString (cfg.scoring.service.thresholds.good or 85)} ]; then
                ${serviceName}_healthy_components=$(( ${serviceName}_healthy_components + 1 ))
              fi
            fi
          '') serviceConfig.components
        )}

        # Calculate service score based on aggregation method
        case "${cfg.scoring.service.aggregation or "weighted-average"}" in
          "worst-case")
            # Find minimum component score
            ${serviceName}_final_score=100
            ${lib.concatStringsSep "\n" (
              map (componentName: ''
                if [ -f "${stateDir}/component/${componentName}.score" ]; then
                  component_score=$(cat "${stateDir}/component/${componentName}.score" 2>/dev/null || echo "100")
                  if [ "$component_score" -lt "${serviceName}_final_score" ]; then
                    ${serviceName}_final_score=$component_score
                  fi
                fi
              '') serviceConfig.components
            )}
            ;;
          "average")
            if [ "${serviceName}_total_components" -gt 0 ]; then
              ${serviceName}_final_score=$(( ${serviceName}_score / ${serviceName}_total_components ))
            else
              ${serviceName}_final_score=0
            fi
            ;;
          "weighted-average")
            if [ "${serviceName}_weight" -gt 0 ]; then
              ${serviceName}_final_score=$(( ${serviceName}_score / ${serviceName}_weight ))
            else
              ${serviceName}_final_score=0
            fi
            ;;
        esac

        # Store service score
        echo "${serviceName}_final_score" > "${stateDir}/service/${serviceName}.score"
        echo "${serviceName}_healthy_components ${serviceName}_total_components" > "${stateDir}/service/${serviceName}.components"
      '';

      # System-level aggregation
      calculateSystemScore = ''
        system_score=0
        system_weight=0
        system_total_services=0
        system_healthy_services=0

        # Aggregate service scores
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (serviceName: serviceConfig: ''
            if [ -f "${stateDir}/service/${serviceName}.score" ]; then
              service_score=$(cat "${stateDir}/service/${serviceName}.score" 2>/dev/null || echo "0")
              service_weight=${toString serviceConfig.weight}
              system_score=$(( system_score + service_score * service_weight ))
              system_weight=$(( system_weight + service_weight ))
              system_total_services=$(( system_total_services + 1 ))
              if [ "$service_score" -ge ${toString (cfg.scoring.system.thresholds.good or 85)} ]; then
                system_healthy_services=$(( system_healthy_services + 1 ))
              fi
            fi
          '') cfg.services
        )}

        # Calculate system score based on aggregation method
        case "${cfg.scoring.system.aggregation or "weighted-average"}" in
          "worst-case")
            # Find minimum service score
            system_final_score=100
            ${lib.concatStringsSep "\n" (
              lib.mapAttrsToList (serviceName: serviceConfig: ''
                if [ -f "${stateDir}/service/${serviceName}.score" ]; then
                  service_score=$(cat "${stateDir}/service/${serviceName}.score" 2>/dev/null || echo "100")
                  if [ "$service_score" -lt "$system_final_score" ]; then
                    system_final_score=$service_score
                  fi
                fi
              '') cfg.services
            )}
            ;;
          "average")
            if [ "$system_total_services" -gt 0 ]; then
              system_final_score=$(( system_score / system_total_services ))
            else
              system_final_score=0
            fi
            ;;
          "weighted-average")
            if [ "$system_weight" -gt 0 ]; then
              system_final_score=$(( system_score / system_weight ))
            else
              system_final_score=0
            fi
            ;;
        esac

        # Store system score
        echo "$system_final_score" > "${stateDir}/system.score"
        echo "$system_healthy_services $system_total_services" > "${stateDir}/system.services"
      '';
    in
    # This is a shell command string that calculates all levels
    ''
      # Create subdirectories for hierarchical storage
      mkdir -p "${stateDir}/component" "${stateDir}/service"

      # Calculate component scores
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList calculateComponentScore cfg.components)}

      # Calculate service scores
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList calculateServiceScore cfg.services)}

      # Calculate system score
      ${calculateSystemScore}

      # Return system score for backward compatibility
      cat "${stateDir}/system.score" 2>/dev/null || echo "0"
    '';

in
{
  config = lib.mkIf enabled {
    # Create systemd services for health monitoring
    systemd.services.gateway-health-monitor = {
      description = "Gateway health monitoring service";
      # wantedBy = [ "multi-user.target" ]; # Disable auto-start on boot for debugging
      after = lib.mkIf cfg.waitForNetwork [ "network-online.target" ];
      wants = lib.mkIf cfg.waitForNetwork [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeScript "gateway-health-monitor.sh" ''
          #!/bin/sh
          set -e

          HEALTH_STATE_DIR="/run/gateway-health"
          LOG_FILE="/var/log/gateway/health-monitor.log"
          ALERT_STATE_DIR="/run/gateway-health-alerts"

          mkdir -p "$HEALTH_STATE_DIR" "$ALERT_STATE_DIR" "$(dirname "$LOG_FILE")"

          log() {
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
          }

          log "Health monitoring cycle started"

          # Health check for each component
          ${lib.concatMapStringsSep "\n" (
            componentName:
            let
              componentConfig = builtins.getAttr componentName cfg.components or { };
              defaultHealthCheck = healthChecksLib.defaultHealthChecks.${componentName} or null;
              healthChecks =
                if componentConfig ? checks then
                  componentConfig.checks
                else
                  (if defaultHealthCheck != null then defaultHealthCheck.checks else [ ]);
              healthScript =
                if healthChecks != [ ] then
                  let
                    checkScripts = map (check: healthChecksLib.generateHealthCheckScript check) healthChecks;
                    allChecks = lib.concatStringsSep "\n" (
                      map (script: ''
                        # Execute check in a subshell, capturing exit status
                        if ! ( ${script} ); then
                          echo "Health check failed for ${componentName}"
                          exit 1
                        fi
                      '') checkScripts
                    );
                  in
                  ''
                    #!/bin/sh
                    set -e
                    echo "Running health checks for ${componentName}..."
                    ${allChecks}
                    echo "All health checks passed for ${componentName}"
                  ''
                else
                  "echo \"No health checks defined for ${componentName}\"";
            in
            ''
              if [ "${boolToString (componentConfig.enable or true)}" = "true" ]; then
                log "Checking health of ${componentName}"
                
                # Create a temporary script file to avoid quoting issues with bash -c
                CHECK_SCRIPT="$HEALTH_STATE_DIR/${componentName}_check.sh"
                cat << 'EOF_HEALTH_CHECK' > "$CHECK_SCRIPT"
              ${healthScript}
              EOF_HEALTH_CHECK
                chmod +x "$CHECK_SCRIPT"

                if OUTPUT=$("$CHECK_SCRIPT" 2>&1); then
                  echo "1" > "$HEALTH_STATE_DIR/component/${componentName}.status"
                  echo "$(date +%s)" > "$HEALTH_STATE_DIR/component/${componentName}.last_check"
                  log "Health check passed for ${componentName}"
                else
                  echo "0" > "$HEALTH_STATE_DIR/component/${componentName}.status"
                  echo "$(date +%s)" > "$HEALTH_STATE_DIR/component/${componentName}.last_check"
                  log "Health check failed for ${componentName}"
                  log "Output: $OUTPUT"
                fi
                
                # Clean up
                rm -f "$CHECK_SCRIPT"
              fi
            ''
          ) (builtins.attrNames cfg.components)}

          log "Health monitoring cycle completed"
        '';
        StandardOutput = "journal+console";
        User = "root";
        Group = "root";
        PrivateTmp = true;
        ProtectSystem = "strict";
        ReadWritePaths = [
          "/run/gateway-health"
          "/run/gateway-health-alerts"
          "/var/log/gateway"
        ];
      };
        path = with pkgs; [
          coreutils
          bash
          procps
          iproute2
          netcat
          dnsutils
          sqlite
          util-linux
          gawk
          gnugrep
          jq
          bc
          curl
          dhcping
          suricata
        ];
    };

    # Health dashboard service
    systemd.services.gateway-health-dashboard = lib.mkIf cfg.dashboard.enable {
      description = "Gateway health monitoring dashboard";
      wantedBy = [ "multi-user.target" ];
      after = lib.mkIf cfg.waitForNetwork [ "network-online.target" ];
      wants = lib.mkIf cfg.waitForNetwork [ "network-online.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = pkgs.writeScript "gateway-health-dashboard.sh" ''
          #!/bin/sh
          set -e

          HEALTH_STATE_DIR="/run/gateway-health"
          DASHBOARD_DATA="/run/gateway-health/dashboard.json"

          mkdir -p "$HEALTH_STATE_DIR" "$(dirname "$DASHBOARD_DATA")"

          log() {
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/gateway/health-dashboard.log
          }

          # Generate dashboard data
          generate_dashboard_data() {
            echo '{'
            echo '  "timestamp": "'$(date -Iseconds)'",'
            echo '  "system": {'
            echo '    "score": '$(cat "$HEALTH_STATE_DIR/system.score" 2>/dev/null || echo "0")','
            echo '    "services": "'$(cat "$HEALTH_STATE_DIR/system.services" 2>/dev/null || echo "0 0")'"'
            echo '  },'
            echo '  "services": {'

            ${
              let
                serviceEntries = lib.mapAttrsToList (serviceName: serviceConfig: ''
                  echo '    "${serviceName}": {'
                  echo '      "score": '$(cat "$HEALTH_STATE_DIR/service/${serviceName}.score" 2>/dev/null || echo "0")','
                  echo '      "components": "'$(cat "$HEALTH_STATE_DIR/service/${serviceName}.components" 2>/dev/null || echo "0 0")'",'
                  echo '      "critical": '${boolToString serviceConfig.critical}','
                  echo '      "weight": '${toString serviceConfig.weight}'
                  echo '    },'
                '') cfg.services;
              in
              lib.concatStringsSep "\n" serviceEntries
            }

            echo '    "__metadata": { "generated": true }'
            echo '  },'
            echo '  "components": {'

            ${
              let
                componentEntries = map (
                  componentName:
                  let
                    componentConfig = builtins.getAttr componentName cfg.components or { };
                  in
                  ''
                    echo '    "${componentName}": {'
                    echo '      "status": "'$(cat "$HEALTH_STATE_DIR/component/${componentName}.status" 2>/dev/null || echo "unknown")'",'
                    echo '      "score": '$(cat "$HEALTH_STATE_DIR/component/${componentName}.score" 2>/dev/null || echo "0")','
                    echo '      "checks": "'$(cat "$HEALTH_STATE_DIR/component/${componentName}.checks" 2>/dev/null || echo "0 0")'",'
                    echo '      "last_check": "'$(cat "$HEALTH_STATE_DIR/component/${componentName}.last_check" 2>/dev/null || echo "0")'",'
                    echo '      "service": "${componentConfig.service or "unknown"}",'
                    echo '      "interval": "'${componentConfig.interval or "30s"}'",'
                    echo '      "thresholds": {'
                    echo '        "warning": "'${componentConfig.thresholds.warning or "null"}'",'
                    echo '        "critical": "'${componentConfig.thresholds.critical or "null"}'",'
                    echo '        "recovery": "'${componentConfig.thresholds.recovery or "null"}'"'
                    echo '      }'
                    echo '    },'
                  ''
                ) (builtins.attrNames cfg.components);
              in
              lib.concatStringsSep "\n" componentEntries
            }

            echo '    "__metadata": { "generated": true }'
            echo '  }'
            echo '}'
          }

          # Start simple HTTP server for dashboard
          while true; do
            generate_dashboard_data > "$DASHBOARD_DATA"
            
            # Serve dashboard
            ${pkgs.python3}/bin/python3 -m http.server ${toString (cfg.dashboard.port or 8080)} \
              --bind "${cfg.dashboard.bindAddress or "127.0.0.1"}" \
              --directory "$(dirname "$DASHBOARD_DATA")" \
              2>/dev/null || break
            
            sleep 5
          done

          log "Health dashboard started on port ${toString (cfg.dashboard.port or 8080)}"
        '';
        User = "root";
        Group = "root";
        PrivateTmp = true;
        ProtectSystem = "strict";
        ReadWritePaths = [
          "/run/gateway-health"
          "/var/log/gateway"
        ];
      };
    };

    # Analytics service
    systemd.services.gateway-health-analytics = lib.mkIf cfg.analytics.enable {
      description = "Gateway health analytics service";
      wantedBy = [ "multi-user.target" ];
      after = lib.mkIf cfg.waitForNetwork [ "network-online.target" ];
      wants = lib.mkIf cfg.waitForNetwork [ "network-online.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = pkgs.writeScript "gateway-health-analytics.sh" ''
                    #!${pkgs.bash}/bin/bash
                    set -e

                    HEALTH_STATE_DIR="/run/gateway-health"
                    ANALYTICS_DATA="/run/gateway-health/analytics.json"
                    LOG_FILE="/var/log/gateway/health-analytics.log"

                    mkdir -p "$HEALTH_STATE_DIR" "$(dirname "$ANALYTICS_DATA")" "$(dirname "$LOG_FILE")"

                    log() {
                      echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
                    }

                    log "Health analytics service starting..."

                    # Process health data for analytics
                    process_health_analytics() {
                      echo '{'
                      echo '  "timestamp": "'$(date -Iseconds)'",'
                      echo '  "health_scores": {'
                      echo '    "system": '$(${calculateHealthScores "/run/gateway-health"}),
                      echo '    "services": {'

                      # Add service scores
                      ${lib.concatStringsSep "\n" (
                        lib.mapAttrsToList (serviceName: serviceConfig: ''
                          if [ -f "/run/gateway-health/service/${serviceName}.score" ]; then
                            echo '      "${serviceName}": '$(cat "/run/gateway-health/service/${serviceName}.score" 2>/dev/null || echo "0")','
                          fi
                        '') cfg.services
                      )}

                      echo '      "__metadata": { "generated": true }'
                      echo '    },'
                      echo '    "components": {'

                      ${
                        let
                          componentEntries = map (
                            componentName:
                            let
                              componentConfig = builtins.getAttr componentName cfg.components or { };
                            in
                            ''
                              echo '      "${componentName}": {'
                              echo '        "status": "'$(cat "$HEALTH_STATE_DIR/component/${componentName}.status" 2>/dev/null || echo "unknown")'",'
                              echo '        "score": '$(cat "$HEALTH_STATE_DIR/component/${componentName}.score" 2>/dev/null || echo "0")','
                              echo '        "checks": "'$(cat "$HEALTH_STATE_DIR/component/${componentName}.checks" 2>/dev/null || echo "0 0")'",'
                              echo '        "service": "${componentConfig.service or "unknown"}"'
                              echo '      },'
                            ''
                          ) (builtins.attrNames cfg.components);
                        in
                        lib.concatStringsSep "\n" componentEntries
                      }
                      echo '      "__metadata": { "generated": true }'
                      echo '    }'
                      echo '  },'
                      echo '  "trends": {'
                      echo '    "system": [],'
                      echo '    "services": {},'
                      echo '    "components": {}'
                      echo '  }'
                      echo '}'
                    }

                    # Generate analytics report
                    generate_analytics_report() {
                      # Create temporary file with health analytics
                      process_health_analytics > "$ANALYTICS_DATA.tmp"

                      # Add trend data to the analytics
                      TRENDS_DATA=$(cat <<EOF
          {
            "system": $(cat "/run/gateway-health/trends/system.json" 2>/dev/null || echo '{"average": 0, "trend": 0, "direction": "unknown"}'),
            "services": {
          EOF
          )

                      # Add service trends
                      ${lib.concatStringsSep "\n" (
                        lib.mapAttrsToList (serviceName: serviceConfig: ''
                          TRENDS_DATA="$TRENDS_DATA    \"${serviceName}\": $(cat \"/run/gateway-health/trends/service_${serviceName}.json\" 2>/dev/null || echo '{\"average\": 0, \"trend\": 0, \"direction\": \"unknown\"}'),"
                        '') cfg.services
                      )}

                      TRENDS_DATA="$TRENDS_DATA    \"__metadata\": { \"generated\": true }
            },
            \"components\": {"

                      # Add component trends
                      ${lib.concatStringsSep "\n" (
                        lib.mapAttrsToList (componentName: componentConfig: ''
                          TRENDS_DATA="$TRENDS_DATA    \"${componentName}\": $(cat \"/run/gateway-health/trends/component_${componentName}.json\" 2>/dev/null || echo '{\"average\": 0, \"trend\": 0, \"direction\": \"unknown\"}'),"
                        '') cfg.components
                      )}

                      TRENDS_DATA="$TRENDS_DATA    \"__metadata\": { \"generated\": true }
            }
          }"

                      # Combine health data with trends
                      jq --argjson trends "$TRENDS_DATA" '.trends = $trends' "$ANALYTICS_DATA.tmp" > "$ANALYTICS_DATA" 2>/dev/null || cp "$ANALYTICS_DATA.tmp" "$ANALYTICS_DATA"

                      # Add analytics metadata
                      METADATA_FILE="$ANALYTICS_DATA.metadata"
                      cat > "$METADATA_FILE" <<EOF
          {
            "report_type": "health_summary",
            "retention_period": "${cfg.analytics.retention or "30d"}",
            "aggregation": "${cfg.analytics.aggregation or "avg"}",
            "trends_enabled": ${boolToString cfg.analytics.trends},
            "prediction_enabled": ${boolToString cfg.prediction.enable},
            "generated_at": "$(date -Iseconds)"
          }
          EOF

                      # Clean up temp file
                      rm -f "$ANALYTICS_DATA.tmp"
                    }

                    # Store historical health data for trend analysis
                    store_historical_data() {
                      HISTORY_DIR="/run/gateway-health/history"
                      mkdir -p "$HISTORY_DIR"

                      # Store current system score
                      SYSTEM_SCORE=$(cat "$HEALTH_STATE_DIR/system.score" 2>/dev/null || echo "0")
                      TIMESTAMP=$(date +%s)
                      echo "$TIMESTAMP,$SYSTEM_SCORE" >> "$HISTORY_DIR/system.csv"

                      # Store service scores
                      ${lib.concatStringsSep "\n" (
                        lib.mapAttrsToList (serviceName: serviceConfig: ''
                          SERVICE_SCORE=$(cat "$HEALTH_STATE_DIR/service/${serviceName}.score" 2>/dev/null || echo "0")
                          echo "$TIMESTAMP,$SERVICE_SCORE" >> "$HISTORY_DIR/service_${serviceName}.csv"
                        '') cfg.services
                      )}

                      # Store component scores
                      ${lib.concatStringsSep "\n" (
                        lib.mapAttrsToList (componentName: componentConfig: ''
                          COMPONENT_SCORE=$(cat "$HEALTH_STATE_DIR/component/${componentName}.score" 2>/dev/null || echo "0")
                          echo "$TIMESTAMP,$COMPONENT_SCORE" >> "$HISTORY_DIR/component_${componentName}.csv"
                        '') cfg.components
                      )}

                      # Rotate old data (keep last 1000 entries per file)
                      for file in "$HISTORY_DIR"/*.csv; do
                        if [ -f "$file" ]; then
                          tail -n 1000 "$file" > "$file.tmp" && mv "$file.tmp" "$file"
                        fi
                      done
                    }

                    # Calculate health trends
                    calculate_trends() {
                      HISTORY_DIR="/run/gateway-health/history"
                      TRENDS_DIR="/run/gateway-health/trends"
                      mkdir -p "$TRENDS_DIR"

                      # Calculate system trend (last 10 data points)
                      if [ -f "$HISTORY_DIR/system.csv" ]; then
                        # Simple linear trend calculation
                        RECENT_DATA=$(tail -n 10 "$HISTORY_DIR/system.csv" | awk -F',' '{print $2}')
                        COUNT=$(echo "$RECENT_DATA" | wc -l)
                        SUM=$(echo "$RECENT_DATA" | awk '{sum+=$1} END {print sum}')
                        AVG=$(( SUM / COUNT ))

                        # Calculate trend direction (simplified)
                        FIRST=$(echo "$RECENT_DATA" | head -n 1)
                        LAST=$(echo "$RECENT_DATA" | tail -n 1)
                        TREND=$(( LAST - FIRST ))

                        echo "{ \"average\": $AVG, \"trend\": $TREND, \"direction\": \"$([ $TREND -gt 0 ] && echo 'improving' || [ $TREND -lt 0 ] && echo 'degrading' || echo 'stable')\" }" > "$TRENDS_DIR/system.json"
                      fi

                      # Calculate service trends
                      ${lib.concatStringsSep "\n" (
                        lib.mapAttrsToList (serviceName: serviceConfig: ''
                          if [ -f "$HISTORY_DIR/service_${serviceName}.csv" ]; then
                            RECENT_DATA=$(tail -n 10 "$HISTORY_DIR/service_${serviceName}.csv" | awk -F',' '{print $2}')
                            COUNT=$(echo "$RECENT_DATA" | wc -l)
                            if [ "$COUNT" -gt 0 ]; then
                              SUM=$(echo "$RECENT_DATA" | awk '{sum+=$1} END {print sum}')
                              AVG=$(( SUM / COUNT ))
                              FIRST=$(echo "$RECENT_DATA" | head -n 1)
                              LAST=$(echo "$RECENT_DATA" | tail -n 1)
                              TREND=$(( LAST - FIRST ))
                              echo "{ \"average\": $AVG, \"trend\": $TREND, \"direction\": \"$([ $TREND -gt 0 ] && echo 'improving' || [ $TREND -lt 0 ] && echo 'degrading' || echo 'stable')\" }" > "$TRENDS_DIR/service_${serviceName}.json"
                            fi
                          fi
                        '') cfg.services
                      )}

                      # Calculate component trends
                      ${lib.concatStringsSep "\n" (
                        lib.mapAttrsToList (componentName: componentConfig: ''
                          if [ -f "$HISTORY_DIR/component_${componentName}.csv" ]; then
                            RECENT_DATA=$(tail -n 10 "$HISTORY_DIR/component_${componentName}.csv" | awk -F',' '{print $2}')
                            COUNT=$(echo "$RECENT_DATA" | wc -l)
                            if [ "$COUNT" -gt 0 ]; then
                              SUM=$(echo "$RECENT_DATA" | awk '{sum+=$1} END {print sum}')
                              AVG=$(( SUM / COUNT ))
                              FIRST=$(echo "$RECENT_DATA" | head -n 1)
                              LAST=$(echo "$RECENT_DATA" | tail -n 1)
                              TREND=$(( LAST - FIRST ))
                              echo "{ \"average\": $AVG, \"trend\": $TREND, \"direction\": \"$([ $TREND -gt 0 ] && echo 'improving' || [ $TREND -lt 0 ] && echo 'degrading' || echo 'stable')\" }" > "$TRENDS_DIR/component_${componentName}.json"
                            fi
                          fi
                        '') cfg.components
                      )}
                    }

                    # Run predictive analytics if enabled
                    run_prediction() {
                      ${lib.optionalString cfg.prediction.enable ''
                        log "Running predictive analytics models..."
                        # Enhanced prediction with historical data and confidence scoring

                        PREDICTION_DIR="/run/gateway-health/prediction"
                        mkdir -p "$PREDICTION_DIR"

                        ${lib.concatStringsSep "\n" (
                          lib.mapAttrsToList (modelName: modelConfig: ''
                            log "Running ${modelConfig.algorithm} model for ${modelName}..."

                            # Enhanced prediction based on model algorithm
                            case "${modelConfig.algorithm}" in
                              "linear-regression")
                                # Linear regression prediction
                                if [ -f "/run/gateway-health/history/system.csv" ]; then
                                  # Calculate linear trend using simple least squares
                                  DATA=$(tail -n 168 "/run/gateway-health/history/system.csv" 2>/dev/null || echo "")
                                  if [ -n "$DATA" ]; then
                                    # Calculate slope and intercept
                                    CALC_RESULT=$(
                                      echo "$DATA" | awk -F',' '
                                        BEGIN { n=0; sum_x=0; sum_y=0; sum_xy=0; sum_x2=0 }
                                        {
                                          x = n;
                                          y = $2;
                                          sum_x += x;
                                          sum_y += y;
                                          sum_xy += x * y;
                                          sum_x2 += x * x;
                                          n++;
                                        }
                                        END {
                                          if (n > 1) {
                                            slope = (n * sum_xy - sum_x * sum_y) / (n * sum_x2 - sum_x * sum_x);
                                            intercept = (sum_y - slope * sum_x) / n;
                                            prediction = intercept + slope * (n + 24);
                                            r_squared = 1 - ((n * sum_x2 - sum_x * sum_x) / (n * sum_x2 - sum_x * sum_x)); # Simplified
                                            print prediction "," r_squared;
                                          } else {
                                            print "0,0";
                                          }
                                        }
                                      '
                                    )
                                    PREDICTION=$(echo "$CALC_RESULT" | cut -d',' -f1)
                                    CONFIDENCE=$(echo "$CALC_RESULT" | cut -d',' -f2)
                                    PREDICTION_STATUS=$([ $(echo "$PREDICTION > 85" | bc -l) -eq 1 ] && echo "healthy" || [ $(echo "$PREDICTION > 70" | bc -l) -eq 1 ] && echo "degraded" || echo "critical")
                                  else
                                    PREDICTION=0
                                    CONFIDENCE=0.1
                                    PREDICTION_STATUS="unknown"
                                  fi
                                else
                                  PREDICTION=0
                                  CONFIDENCE=0.1
                                  PREDICTION_STATUS="unknown"
                                fi
                                ;;

                              "time-series")
                                # Time series prediction (simplified moving average)
                                if [ -f "/run/gateway-health/history/system.csv" ]; then
                                  RECENT_AVG=$(tail -n 10 "/run/gateway-health/history/system.csv" | awk -F',' '{sum+=$2; count++} END {print count>0 ? sum/count : 0}')
                                  TREND=$(tail -n 20 "/run/gateway-health/history/system.csv" | awk -F',' '
                                    BEGIN { count=0; sum=0 }
                                    {
                                      values[count] = $2;
                                      count++;
                                    }
                                    END {
                                      if (count >= 10) {
                                        recent_avg = 0; old_avg = 0;
                                        for (i = count-10; i < count; i++) recent_avg += values[i];
                                        for (i = 0; i < 10; i++) old_avg += values[i];
                                        recent_avg /= 10; old_avg /= 10;
                                        print recent_avg - old_avg;
                                      } else {
                                        print 0;
                                      }
                                    }
                                  ')
                                  PREDICTION=$(echo "$RECENT_AVG + $TREND" | bc -l 2>/dev/null || echo "$RECENT_AVG")
                                  CONFIDENCE=0.7
                                  PREDICTION_STATUS=$([ $(echo "$PREDICTION > 85" | bc -l) -eq 1 ] && echo "healthy" || [ $(echo "$PREDICTION > 70" | bc -l) -eq 1 ] && echo "degraded" || echo "critical")
                                else
                                  PREDICTION=0
                                  CONFIDENCE=0.1
                                  PREDICTION_STATUS="unknown"
                                fi
                                ;;

                              "random-forest")
                                # Simplified ensemble prediction
                                if [ -f "/run/gateway-health/history/system.csv" ]; then
                                  # Use multiple prediction methods and average
                                  LINEAR_PRED=$(tail -n 20 "/run/gateway-health/history/system.csv" | awk -F',' '
                                    BEGIN { n=0; sum_x=0; sum_y=0; sum_xy=0; sum_x2=0 }
                                    {
                                      x = n; y = $2;
                                      sum_x += x; sum_y += y; sum_xy += x * y; sum_x2 += x * x;
                                      n++;
                                    }
                                    END {
                                      if (n > 1) {
                                        slope = (n * sum_xy - sum_x * sum_y) / (n * sum_x2 - sum_x * sum_x);
                                        intercept = (sum_y - slope * sum_x) / n;
                                        print intercept + slope * (n + 5);
                                      } else print 0;
                                    }
                                  ')
                                  AVG_PRED=$(tail -n 10 "/run/gateway-health/history/system.csv" | awk -F',' '{sum+=$2; count++} END {print count>0 ? sum/count : 0}')
                                  
                                  PREDICTION=$(echo "($LINEAR_PRED + $AVG_PRED) / 2" | bc -l 2>/dev/null || echo "$AVG_PRED")
                                  CONFIDENCE=0.85
                                  PREDICTION_STATUS=$([ $(echo "$PREDICTION > 85" | bc -l) -eq 1 ] && echo "healthy" || [ $(echo "$PREDICTION > 70" | bc -l) -eq 1 ] && echo "degraded" || echo "critical")
                                else
                                  PREDICTION=0
                                  CONFIDENCE=0.1
                                  PREDICTION_STATUS="unknown"
                                fi
                                ;;

                              *)
                                PREDICTION=0
                                CONFIDENCE=0
                                PREDICTION_STATUS="unknown"
                                ;;
                            esac

                            echo "{ \"model\": \"${modelName}\", \"prediction\": $PREDICTION, \"status\": \"$PREDICTION_STATUS\", \"confidence\": $CONFIDENCE, \"timestamp\": \"$(date -Iseconds)\" }" > "$PREDICTION_DIR/${modelName}.json"
                          '') cfg.prediction.models
                        )}
                      ''}
                    }

                    # Run anomaly detection if enabled
                    run_anomaly_detection() {
                      ${lib.optionalString cfg.prediction.anomaly.enable ''
                        log "Running anomaly detection..."
                        ANOMALY_DIR="/run/gateway-health/anomalies"
                        mkdir -p "$ANOMALY_DIR"

                        # Simple statistical anomaly detection (z-score)
                        if [ -f "/run/gateway-health/history/system.csv" ]; then
                          STATS=$(tail -n 100 "/run/gateway-health/history/system.csv" | awk -F',' '
                            BEGIN { sum=0; sumsq=0; count=0 }
                            {
                              sum += $2;
                              sumsq += $2 * $2;
                              count++;
                              last_val = $2;
                            }
                            END {
                              if (count > 0) {
                                mean = sum / count;
                                variance = (sumsq - (sum * sum / count)) / count;
                                stddev = sqrt(variance);
                                print mean "," stddev "," last_val;
                              } else {
                                print "0,0,0";
                              }
                            }
                          ')
                          MEAN=$(echo "$STATS" | cut -d',' -f1)
                          STDDEV=$(echo "$STATS" | cut -d',' -f2)
                          LAST_VAL=$(echo "$STATS" | cut -d',' -f3)

                          # Avoid division by zero
                          if [ $(echo "$STDDEV > 0.001" | bc -l) -eq 1 ]; then
                            Z_SCORE=$(echo "($LAST_VAL - $MEAN) / $STDDEV" | bc -l)
                            IS_ANOMALY=$(echo "$Z_SCORE > 3 || $Z_SCORE < -3" | bc -l)
                            
                            if [ "$IS_ANOMALY" -eq 1 ]; then
                              log "ANOMALY DETECTED: System score $LAST_VAL is anomalous (Z-score: $Z_SCORE)"
                              echo "{ \"timestamp\": \"$(date -Iseconds)\", \"score\": $LAST_VAL, \"z_score\": $Z_SCORE, \"type\": \"statistical\" }" >> "$ANOMALY_DIR/system_anomalies.log"
                            fi
                          fi
                        fi
                      ''}
                    }

                    # Main loop
                    while true; do
                      store_historical_data
                      ${lib.optionalString cfg.analytics.trends "calculate_trends"}
                      ${lib.optionalString cfg.prediction.enable "run_prediction"}
                      ${lib.optionalString cfg.prediction.anomaly.enable "run_anomaly_detection"}
                      generate_analytics_report
                      
                      # Run every minute
                      sleep 60
                    done
        '';
        User = "root";
        Group = "root";
        PrivateTmp = true;
        ProtectSystem = "strict";
        ReadWritePaths = [
          "/run/gateway-health"
          "/var/log/gateway"
        ];
      };
      path = with pkgs; [
        coreutils
        bash
        jq
        bc
        gawk
      ];
    };
  };
}

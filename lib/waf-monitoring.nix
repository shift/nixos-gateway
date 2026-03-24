{ lib, pkgs }:

let
  # WAF monitoring configuration
  monitoringConfig = {
    # Metrics to collect
    metrics = {
      blockedRequests = "waf_blocked_requests_total";
      allowedRequests = "waf_allowed_requests_total";
      ruleHits = "waf_rule_hits_total";
      responseTime = "waf_response_time_seconds";
      activeConnections = "waf_active_connections";
    };

    # Alert thresholds
    alerts = {
      highBlockRate = {
        threshold = 0.1; # 10% block rate
        severity = "warning";
      };
      highResponseTime = {
        threshold = 5.0; # 5 seconds
        severity = "critical";
      };
      ruleHits = {
        threshold = 100; # 100 rule hits per minute
        severity = "warning";
      };
    };
  };

  # Generate Prometheus metrics configuration
  generateMetricsConfig = port: ''
    # WAF Metrics Configuration
    global:
      scrape_interval: 15s
      evaluation_interval: 15s

    rule_files:
      - /etc/waf/monitoring/rules.yml

    scrape_configs:
      - job_name: 'waf'
        static_configs:
          - targets: ['localhost:${toString port}']
        metrics_path: /metrics

    alerting:
      alertmanagers:
        - static_configs:
            - targets:
              - localhost:9093
  '';

  # Generate alert rules
  generateAlertRules = ''
    groups:
    - name: waf_alerts
      rules:
      - alert: WAFHighBlockRate
        expr: rate(waf_blocked_requests_total[5m]) / rate(waf_allowed_requests_total[5m]) > ${toString monitoringConfig.alerts.highBlockRate.threshold}
        for: 5m
        labels:
          severity: ${monitoringConfig.alerts.highBlockRate.severity}
        annotations:
          summary: "High WAF block rate detected"
          description: "WAF is blocking more than ${
            toString (monitoringConfig.alerts.highBlockRate.threshold * 100)
          }% of requests"

      - alert: WAFHighResponseTime
        expr: waf_response_time_seconds{quantile="0.95"} > ${toString monitoringConfig.alerts.highResponseTime.threshold}
        for: 5m
        labels:
          severity: ${monitoringConfig.alerts.highResponseTime.severity}
        annotations:
          summary: "High WAF response time"
          description: "WAF response time is above ${toString monitoringConfig.alerts.highResponseTime.threshold}s"

      - alert: WAFRuleHits
        expr: rate(waf_rule_hits_total[5m]) > ${toString monitoringConfig.alerts.ruleHits.threshold}
        for: 5m
        labels:
          severity: ${monitoringConfig.alerts.ruleHits.severity}
        annotations:
          summary: "High WAF rule hit rate"
          description: "WAF rules are being triggered more than ${toString monitoringConfig.alerts.ruleHits.threshold} times per minute"
  '';

  # Generate Grafana dashboard configuration
  generateGrafanaDashboard = ''
    {
      "dashboard": {
        "title": "WAF Security Dashboard",
        "tags": ["waf", "security"],
        "timezone": "browser",
        "panels": [
          {
            "title": "Request Rate",
            "type": "graph",
            "targets": [
              {
                "expr": "rate(waf_allowed_requests_total[5m])",
                "legendFormat": "Allowed"
              },
              {
                "expr": "rate(waf_blocked_requests_total[5m])",
                "legendFormat": "Blocked"
              }
            ]
          },
          {
            "title": "Block Rate Percentage",
            "type": "singlestat",
            "targets": [
              {
                "expr": "(rate(waf_blocked_requests_total[5m]) / (rate(waf_allowed_requests_total[5m]) + rate(waf_blocked_requests_total[5m]))) * 100",
                "format": "percent"
              }
            ]
          },
          {
            "title": "Response Time",
            "type": "graph",
            "targets": [
              {
                "expr": "waf_response_time_seconds{quantile=\"0.95\"}",
                "legendFormat": "95th percentile"
              },
              {
                "expr": "waf_response_time_seconds{quantile=\"0.50\"}",
                "legendFormat": "50th percentile"
              }
            ]
          },
          {
            "title": "Active Connections",
            "type": "graph",
            "targets": [
              {
                "expr": "waf_active_connections",
                "legendFormat": "Active connections"
              }
            ]
          }
        ]
      }
    }
  '';

  # Log analysis functions
  logAnalysis = {
    # Parse ModSecurity audit logs
    parseAuditLog = logFile: ''
      #!/bin/bash
      # Parse ModSecurity audit logs and extract metrics

      BLOCKED=$(grep -c "deny" ${logFile} || echo "0")
      ALLOWED=$(grep -c "pass" ${logFile} || echo "0")
      RULE_HITS=$(grep -c "id:" ${logFile} || echo "0")

      # Output metrics in Prometheus format
      echo "# HELP waf_blocked_requests_total Total number of blocked requests"
      echo "# TYPE waf_blocked_requests_total counter"
      echo "waf_blocked_requests_total $BLOCKED"

      echo "# HELP waf_allowed_requests_total Total number of allowed requests"
      echo "# TYPE waf_allowed_requests_total counter"
      echo "waf_allowed_requests_total $ALLOWED"

      echo "# HELP waf_rule_hits_total Total number of rule hits"
      echo "# TYPE waf_rule_hits_total counter"
      echo "waf_rule_hits_total $RULE_HITS"
    '';

    # Generate security reports
    generateSecurityReport = ''
      #!/bin/bash
      # Generate daily security report

      LOG_FILE="/etc/waf/logs/modsec_audit.log"
      REPORT_FILE="/var/lib/waf/security_report_$(date +%Y%m%d).txt"

      echo "WAF Security Report - $(date)" > $REPORT_FILE
      echo "=================================" >> $REPORT_FILE
      echo "" >> $REPORT_FILE

      echo "Summary:" >> $REPORT_FILE
      echo "- Total requests: $(wc -l < $LOG_FILE)" >> $REPORT_FILE
      echo "- Blocked requests: $(grep -c "deny" $LOG_FILE)" >> $REPORT_FILE
      echo "- Rule violations: $(grep -c "id:" $LOG_FILE)" >> $REPORT_FILE
      echo "" >> $REPORT_FILE

      echo "Top triggered rules:" >> $REPORT_FILE
      grep "id:" $LOG_FILE | sed 's/.*id:\([0-9]*\).*/\1/' | sort | uniq -c | sort -nr | head -10 >> $REPORT_FILE
      echo "" >> $REPORT_FILE

      echo "Top attacking IPs:" >> $REPORT_FILE
      grep "deny" $LOG_FILE | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | sort | uniq -c | sort -nr | head -10 >> $REPORT_FILE
    '';
  };

in
{
  inherit
    monitoringConfig
    generateMetricsConfig
    generateAlertRules
    generateGrafanaDashboard
    logAnalysis
    ;
}

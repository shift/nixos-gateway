# Test Result and Evidence Collection System

## Evidence Collection Architecture

```nix
# lib/evidence-collector.nix
{ lib, ... }:

let
  # Evidence types
  evidenceTypes = {
    log = {
      extension = "log";
      directory = "logs";
      description = "System and application log files";
    };

    metric = {
      extension = "json";
      directory = "metrics";
      description = "Performance and system metrics";
    };

    output = {
      extension = "txt";
      directory = "outputs";
      description = "Command outputs and test results";
    };

    config = {
      extension = "nix";
      directory = "configs";
      description = "Configuration files used in test";
    };

    screenshot = {
      extension = "png";
      directory = "screenshots";
      description = "Visual captures of test states";
    };
  };

  # Evidence collection functions
  collectEvidence = {
    name,
    type,
    content,
    metadata ? {},
    testName
  }: ''
    # Create evidence directory structure
    mkdir -p /tmp/evidence/${testName}/${evidenceTypes.${type}.directory}

    # Generate filename with timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    filename="/tmp/evidence/${testName}/${evidenceTypes.${type}.directory}/${name}-${timestamp}.${evidenceTypes.${type}.extension}"

    # Write content
    cat > "$filename" << 'EOF'
    ${content}
    EOF

    # Create metadata file
    cat > "${filename}.metadata.json" << EOF
    {
      "evidence_name": "${name}",
      "evidence_type": "${type}",
      "test_name": "${testName}",
      "timestamp": "$timestamp",
      "description": "${evidenceTypes.${type}.description}",
      "metadata": ${builtins.toJSON metadata}
    }
    EOF

    echo "Collected evidence: $filename"
  '';

  # Specialized evidence collectors
  collectors = {
    # System information collector
    systemInfo = testName: ''
      ${collectEvidence {
        name = "system-info";
        type = "output";
        content = ''
          === System Information ===
          Hostname: $(hostname)
          Kernel: $(uname -a)
          Uptime: $(uptime)
          Load Average: $(uptime | awk -F'load average:' '{ print $2 }')
          Memory: $(free -h)
          Disk: $(df -h)
          Network: $(ip addr show)
        '';
        metadata = {
          collection_type = "system";
          importance = "high";
        };
        inherit testName;
      }}
    '';

    # Service status collector
    serviceStatus = testName: ''
      ${collectEvidence {
        name = "service-status";
        type = "output";
        content = ''
          === Service Status ===
          $(systemctl list-units --type=service --all --no-legend | head -20)

          === Failed Services ===
          $(systemctl list-units --type=service --failed --no-legend)

          === Active Services ===
          $(systemctl list-units --type=service --state=active --no-legend | wc -l) active services
        '';
        metadata = {
          collection_type = "services";
          importance = "high";
        };
        inherit testName;
      }}
    '';

    # Network configuration collector
    networkConfig = testName: ''
      ${collectEvidence {
        name = "network-config";
        type = "config";
        content = ''
          === Network Configuration ===
          Interfaces: $(ip addr show)
          Routes: $(ip route show)
          ARP Table: $(ip neigh show)
          DNS: $(cat /etc/resolv.conf 2>/dev/null || echo "No resolv.conf")
          Firewall: $(iptables -L -n 2>/dev/null || echo "No iptables")
        '';
        metadata = {
          collection_type = "network";
          importance = "high";
        };
        inherit testName;
      }}
    '';

    # Performance metrics collector
    performanceMetrics = testName: ''
      ${collectEvidence {
        name = "performance-metrics";
        type = "metric";
        content = ''
          {
            "cpu_usage_percent": $(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print $1}'),
            "memory_usage": $(free | jq -R -s 'split("\n") | .[1] | split(" ") | map(select(. != "")) | {"total": .[0], "used": .[1], "free": .[2]}'),
            "disk_usage": $(df / | jq -R -s 'split("\n") | .[1] | split(" ") | map(select(. != "")) | {"filesystem": .[0], "used_percent": .[4]}'),
            "load_average": "$(uptime | awk -F'load average:' '{ print $2 }' | tr -d ' ')",
            "timestamp": "$(date -Iseconds)"
          }
        '';
        metadata = {
          collection_type = "performance";
          importance = "medium";
        };
        inherit testName;
      }}
    '';

    # Log file collector
    systemLogs = testName: ''
      # Collect recent system logs
      journalctl --since "1 hour ago" --no-pager > /tmp/temp-system.log
      ${collectEvidence {
        name = "system-logs";
        type = "log";
        content = "$(cat /tmp/temp-system.log)";
        metadata = {
          collection_type = "logs";
          log_type = "system";
          time_range = "1_hour";
          importance = "high";
        };
        inherit testName;
      }}
      rm -f /tmp/temp-system.log

      # Collect service-specific logs
      for service in $(systemctl list-units --type=service --state=active --no-legend | awk '{print $1}' | sed 's/\.service$//' | head -10); do
        journalctl -u "$service" --since "1 hour ago" --no-pager > "/tmp/temp-$service.log" 2>/dev/null || true
        if [ -f "/tmp/temp-$service.log" ] && [ -s "/tmp/temp-$service.log" ]; then
          ${collectEvidence {
            name = "service-log-$service";
            type = "log";
            content = "$(cat /tmp/temp-$service.log)";
            metadata = {
              collection_type = "logs";
              log_type = "service";
              service_name = "$service";
              time_range = "1_hour";
              importance = "medium";
            };
            inherit testName;
          }}
        fi
        rm -f "/tmp/temp-$service.log"
      done
    '';

    # Test result collector
    testResults = { testName, result, duration, error ? null }: ''
      ${collectEvidence {
        name = "test-result";
        type = "output";
        content = ''
          === Test Result Summary ===
          Test Name: ${testName}
          Result: ${result}
          Duration: ${duration} seconds
          Timestamp: $(date -Iseconds)
          ${if error != null then "Error: ${error}" else "No errors"}
        '';
        metadata = {
          collection_type = "test_result";
          test_result = result;
          test_duration = duration;
          error_message = error;
          importance = "critical";
        };
        inherit testName;
      }}
    '';
  };

in {
  inherit collectEvidence collectors evidenceTypes;

  # Evidence collection orchestrator
  collectAllEvidence = { testName, collectors }: ''
    echo "Starting evidence collection for test: ${testName}"

    # Run all specified collectors
    ${lib.concatMapStrings (collector: ''
      echo "Running collector: ${collector.name}"
      ${collector.script testName}
    '') collectors}

    # Create evidence manifest
    cat > /tmp/evidence/${testName}/evidence-manifest.json << EOF
    {
      "test_name": "${testName}",
      "collection_timestamp": "$(date -Iseconds)",
      "collectors_run": ${toString (lib.length collectors)},
      "evidence_files": $(find /tmp/evidence/${testName} -type f -name "*.metadata.json" | wc -l),
      "total_size_bytes": $(du -sb /tmp/evidence/${testName} | cut -f1)
    }
    EOF

    # Package evidence
    cd /tmp
    tar -czf ${testName}-evidence.tar.gz evidence/${testName}/
    echo "Evidence packaged: /tmp/${testName}-evidence.tar.gz"
  '';
}
```

## Test Result Storage and Retrieval

```bash
#!/usr/bin/env bash
# scripts/store-test-results.sh

set -euo pipefail

TEST_NAME="$1"
EVIDENCE_FILE="$2"
RESULTS_DB="${3:-test-results.db}"

echo "Storing test results for: $TEST_NAME"

# Initialize results database if it doesn't exist
if [ ! -f "$RESULTS_DB" ]; then
  cat > "$RESULTS_DB" << EOF
{
  "database_version": "1.0",
  "created": "$(date -Iseconds)",
  "tests": {}
}
EOF
fi

# Extract evidence metadata
if [ -f "$EVIDENCE_FILE" ]; then
  mkdir -p /tmp/evidence-extract
  tar -xzf "$EVIDENCE_FILE" -C /tmp/evidence-extract

  # Read test result
  if [ -f "/tmp/evidence-extract/evidence/${TEST_NAME}/outputs/test-result-$(date +%Y%m%d)*.txt" ]; then
    TEST_RESULT=$(grep "Result:" "/tmp/evidence-extract/evidence/${TEST_NAME}/outputs/test-result-"*.txt | head -1 | cut -d: -f2 | tr -d ' ')
  else
    TEST_RESULT="unknown"
  fi

  # Count evidence files
  EVIDENCE_COUNT=$(find /tmp/evidence-extract -name "*.metadata.json" | wc -l)

  # Calculate evidence size
  EVIDENCE_SIZE=$(du -sh /tmp/evidence-extract | cut -f1)

  # Clean up
  rm -rf /tmp/evidence-extract
else
  TEST_RESULT="no_evidence"
  EVIDENCE_COUNT=0
  EVIDENCE_SIZE="0B"
fi

# Store result in database
jq --arg testName "$TEST_NAME" \
   --arg result "$TEST_RESULT" \
   --arg evidenceCount "$EVIDENCE_COUNT" \
   --arg evidenceSize "$EVIDENCE_SIZE" \
   --arg timestamp "$(date -Iseconds)" \
   '.tests[$testName] = {
     "result": $result,
     "evidence_count": ($evidenceCount | tonumber),
     "evidence_size": $evidenceSize,
     "timestamp": $timestamp,
     "evidence_file": "'$EVIDENCE_FILE'"
   }' "$RESULTS_DB" > "${RESULTS_DB}.tmp"

mv "${RESULTS_DB}.tmp" "$RESULTS_DB"

echo "Test result stored: $TEST_NAME = $TEST_RESULT ($EVIDENCE_COUNT evidence files)"
```

## Evidence Analysis and Reporting

```bash
#!/usr/bin/env bash
# scripts/analyze-evidence.sh

set -euo pipefail

TEST_NAME="$1"
EVIDENCE_FILE="$2"
REPORT_DIR="${3:-evidence-analysis}"

echo "Analyzing evidence for test: $TEST_NAME"

# Create analysis directory
mkdir -p "$REPORT_DIR/$TEST_NAME"

# Extract evidence
tar -xzf "$EVIDENCE_FILE" -C "$REPORT_DIR/$TEST_NAME"

# Analyze different evidence types
echo "=== Evidence Analysis Report ===" > "$REPORT_DIR/$TEST_NAME/analysis.txt"
echo "Test: $TEST_NAME" >> "$REPORT_DIR/$TEST_NAME/analysis.txt"
echo "Analysis Date: $(date)" >> "$REPORT_DIR/$TEST_NAME/analysis.txt"
echo >> "$REPORT_DIR/$TEST_NAME/analysis.txt"

# Analyze logs
echo "=== Log Analysis ===" >> "$REPORT_DIR/$TEST_NAME/analysis.txt"
LOG_FILES=$(find "$REPORT_DIR/$TEST_NAME" -name "*.log" | wc -l)
echo "Log files found: $LOG_FILES" >> "$REPORT_DIR/$TEST_NAME/analysis.txt"

if [ $LOG_FILES -gt 0 ]; then
  # Check for errors in logs
  ERROR_COUNT=$(find "$REPORT_DIR/$TEST_NAME" -name "*.log" -exec grep -l "error\|Error\|ERROR\|fail\|Fail\|FAIL" {} \; | wc -l)
  echo "Logs with errors: $ERROR_COUNT" >> "$REPORT_DIR/$TEST_NAME/analysis.txt"

  # Check for critical errors
  CRITICAL_COUNT=$(find "$REPORT_DIR/$TEST_NAME" -name "*.log" -exec grep -l "critical\|Critical\|CRITICAL\|panic\|Panic\|PANIC" {} \; | wc -l)
  echo "Logs with critical errors: $CRITICAL_COUNT" >> "$REPORT_DIR/$TEST_NAME/analysis.txt"
fi

echo >> "$REPORT_DIR/$TEST_NAME/analysis.txt"

# Analyze metrics
echo "=== Metrics Analysis ===" >> "$REPORT_DIR/$TEST_NAME/analysis.txt"
METRIC_FILES=$(find "$REPORT_DIR/$TEST_NAME" -name "*.json" -path "*/metrics/*" | wc -l)
echo "Metric files found: $METRIC_FILES" >> "$REPORT_DIR/$TEST_NAME/analysis.txt"

if [ -f "$REPORT_DIR/$TEST_NAME/evidence/$TEST_NAME/metrics/performance-metrics-*.json" ]; then
  CPU_USAGE=$(jq -r '.cpu_usage_percent' "$REPORT_DIR/$TEST_NAME/evidence/$TEST_NAME/metrics/performance-metrics-"*.json 2>/dev/null || echo "N/A")
  MEM_USAGE=$(jq -r '.memory_usage.used_percent' "$REPORT_DIR/$TEST_NAME/evidence/$TEST_NAME/metrics/performance-metrics-"*.json 2>/dev/null || echo "N/A")

  echo "CPU Usage: $CPU_USAGE%" >> "$REPORT_DIR/$TEST_NAME/analysis.txt"
  echo "Memory Usage: $MEM_USAGE%" >> "$REPORT_DIR/$TEST_NAME/analysis.txt"
fi

echo >> "$REPORT_DIR/$TEST_NAME/analysis.txt"

# Analyze configurations
echo "=== Configuration Analysis ===" >> "$REPORT_DIR/$TEST_NAME/analysis.txt"
CONFIG_FILES=$(find "$REPORT_DIR/$TEST_NAME" -name "*.nix" -path "*/configs/*" | wc -l)
echo "Configuration files collected: $CONFIG_FILES" >> "$REPORT_DIR/$TEST_NAME/analysis.txt"

# Analyze test outputs
echo "=== Test Output Analysis ===" >> "$REPORT_DIR/$TEST_NAME/analysis.txt"
OUTPUT_FILES=$(find "$REPORT_DIR/$TEST_NAME" -name "*.txt" -path "*/outputs/*" | wc -l)
echo "Test output files: $OUTPUT_FILES" >> "$REPORT_DIR/$TEST_NAME/analysis.txt"

# Generate summary
cat > "$REPORT_DIR/$TEST_NAME/summary.json" << EOF
{
  "test_name": "$TEST_NAME",
  "analysis_date": "$(date -Iseconds)",
  "evidence_files": {
    "logs": $LOG_FILES,
    "metrics": $METRIC_FILES,
    "configs": $CONFIG_FILES,
    "outputs": $OUTPUT_FILES
  },
  "issues_found": {
    "error_logs": $ERROR_COUNT,
    "critical_logs": $CRITICAL_COUNT
  },
  "performance_indicators": {
    "cpu_usage_percent": "$CPU_USAGE",
    "memory_usage_percent": "$MEM_USAGE"
  }
}
EOF

echo "Evidence analysis complete. Report saved to: $REPORT_DIR/$TEST_NAME/"
```

## Evidence Quality Validation

```bash
#!/usr/bin/env bash
# scripts/validate-evidence-quality.sh

set -euo pipefail

EVIDENCE_FILE="$1"
MIN_EVIDENCE_FILES="${2:-5}"

echo "Validating evidence quality for: $EVIDENCE_FILE"

# Extract evidence
mkdir -p /tmp/evidence-validate
tar -tzf "$EVIDENCE_FILE" > /tmp/evidence-validate/manifest.txt

# Count evidence files by type
TOTAL_FILES=$(wc -l < /tmp/evidence-validate/manifest.txt)
LOG_FILES=$(grep -c "\.log$" /tmp/evidence-validate/manifest.txt || echo "0")
METRIC_FILES=$(grep -c "/metrics/" /tmp/evidence-validate/manifest.txt || echo "0")
CONFIG_FILES=$(grep -c "/configs/" /tmp/evidence-validate/manifest.txt || echo "0")
OUTPUT_FILES=$(grep -c "/outputs/" /tmp/evidence-validate/manifest.txt || echo "0")

# Check for required evidence types
ISSUES=()

if [ $TOTAL_FILES -lt $MIN_EVIDENCE_FILES ]; then
  ISSUES+=("Insufficient evidence files: $TOTAL_FILES (minimum: $MIN_EVIDENCE_FILES)")
fi

if [ $LOG_FILES -eq 0 ]; then
  ISSUES+=("Missing log files")
fi

if [ $METRIC_FILES -eq 0 ]; then
  ISSUES+=("Missing metric files")
fi

if [ $CONFIG_FILES -eq 0 ]; then
  ISSUES+=("Missing configuration files")
fi

# Check for evidence manifest
if ! grep -q "evidence-manifest.json" /tmp/evidence-validate/manifest.txt; then
  ISSUES+=("Missing evidence manifest")
fi

# Generate validation report
cat > /tmp/evidence-validation.json << EOF
{
  "evidence_file": "$EVIDENCE_FILE",
  "validation_date": "$(date -Iseconds)",
  "total_files": $TOTAL_FILES,
  "file_breakdown": {
    "logs": $LOG_FILES,
    "metrics": $METRIC_FILES,
    "configs": $CONFIG_FILES,
    "outputs": $OUTPUT_FILES
  },
  "issues": [$(printf '"%s",' "''${ISSUES[@]}" | sed 's/,$//')],
  "quality_score": $(echo "scale=2; ($TOTAL_FILES - ''${#ISSUES[@]}) * 100 / $TOTAL_FILES" | bc 2>/dev/null || echo "0"),
  "validation_passed": $([ ''${#ISSUES[@]} -eq 0 ] && echo "true" || echo "false")
}
EOF

# Clean up
rm -rf /tmp/evidence-validate

# Report results
if [ ''${#ISSUES[@]} -eq 0 ]; then
  echo "✅ Evidence quality validation passed"
  echo "Total files: $TOTAL_FILES"
else
  echo "❌ Evidence quality validation failed"
  printf '%s\n' "''${ISSUES[@]}"
  exit 1
fi
```

This evidence collection and analysis system provides:

1. **Comprehensive Collection**: Logs, metrics, configurations, and outputs
2. **Structured Storage**: Organized by type with metadata
3. **Quality Validation**: Ensures evidence completeness and quality
4. **Analysis Tools**: Automated analysis of collected evidence
5. **Reporting**: Detailed reports for human review and certification
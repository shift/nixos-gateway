{ lib, ... }:

let
  # Default configuration drift detection configuration
  defaultConfigDriftConfig = {
    enable = true;

    baseline = {
      creation = {
        schedule = "daily";
        time = "03:00";
        approval = "automatic";

        sources = [
          "nixos-configuration"
          "service-configs"
          "system-settings"
          "security-policies"
        ];
      };

      storage = {
        path = "/var/lib/config-drift/baselines";
        retention = "90d";
        encryption = true;

        versioning = {
          enable = true;
          maxVersions = 30;
          compression = true;
        };
      };

      validation = {
        enable = true;
        checks = [
          "syntax-validation"
          "semantic-validation"
          "security-validation"
          "compliance-validation"
        ];
      };
    };

    monitoring = {
      realTime = {
        enable = true;

        paths = [
          "/etc/nixos"
          "/etc/gateway"
          "/var/lib/gateway"
          "/etc/systemd"
        ];

        events = [
          "create"
          "modify"
          "delete"
          "permission-change"
          "ownership-change"
        ];

        filters = [
          { path = "*.tmp"; action = "ignore"; }
          { path = "*.log"; action = "ignore"; }
          { path = "cache/*"; action = "ignore"; }
        ];
      };

      scheduled = {
        enable = true;

        scans = [
          {
            name = "full-scan";
            schedule = "daily";
            time = "04:00";
            scope = "full";
          }
          {
            name = "security-scan";
            schedule = "hourly";
            scope = "security";
          }
          {
            name = "compliance-scan";
            schedule = "weekly";
            scope = "compliance";
          }
        ];
      };

      comparison = {
        algorithm = "hash-based";
        method = "sha256";

        attributes = [
          "content"
          "permissions"
          "ownership"
          "timestamps"
        ];

        sensitivity = {
          high = "security-files";
          medium = "config-files";
          low = "log-files";
        };
      };
    };

    drift = {
      classification = {
        severity = [
          {
            level = "critical";
            score = 90;
            types = [ "security-policy" "access-control" "encryption-keys" ];
            action = "immediate-alert";
          }
          {
            level = "high";
            score = 75;
            types = [ "service-config" "network-config" "firewall-rules" ];
            action = "alert-and-remediate";
          }
          {
            level = "medium";
            score = 50;
            types = [ "system-config" "application-config" ];
            action = "alert-and-log";
          }
          {
            level = "low";
            score = 25;
            types = [ "documentation" "log-config" ];
            action = "log-only";
          }
        ];
      };

      detection = {
        algorithms = [
          {
            name = "content-hash";
            type = "cryptographic";
            sensitivity = "high";
          }
          {
            name = "permission-check";
            type = "attribute";
            sensitivity = "medium";
          }
          {
            name = "timestamp-analysis";
            type = "behavioral";
            sensitivity = "low";
          }
        ];

        correlation = {
          enable = true;
          window = "5m";
          threshold = 3;
        };
      };

      remediation = {
        automatic = {
          enable = true;

          actions = [
            {
              trigger = "critical-drift";
              action = "restore-from-baseline";
              approval = "automatic";
            }
            {
              trigger = "high-drift";
              action = "create-ticket";
              approval = "automatic";
            }
            {
              trigger = "medium-drift";
              action = "notify-admin";
              approval = "automatic";
            }
          ];
        };

        manual = {
          enable = true;

          workflows = [
            {
              name = "security-drift";
              steps = [
                { type = "isolate-system"; }
                { type = "notify-security"; }
                { type = "investigate-change"; }
                { type = "approve-remediation"; }
                { type = "apply-remediation"; }
              ];
            }
            {
              name = "config-drift";
              steps = [
                { type = "analyze-change"; }
                { type = "assess-impact"; }
                { type = "approve-change"; }
                { type = "update-baseline"; }
              ];
            }
          ];
        };
      };
    };

    change = {
      management = {
        enable = true;

        approval = {
          required = true;

          workflows = [
            {
              name = "standard-change";
              approvers = [ "ops-team" ];
              timeout = "24h";
              autoApprove = false;
            }
            {
              name = "emergency-change";
              approvers = [ "ops-manager" ];
              timeout = "1h";
              autoApprove = true;
            }
            {
              name = "security-change";
              approvers = [ "security-team" "ops-team" ];
              timeout = "48h";
              autoApprove = false;
            }
          ];
        };

        tracking = {
          enable = true;

          attributes = [
            "requester"
            "timestamp"
            "reason"
            "approval"
            "implementation"
            "verification"
          ];

          retention = "7y";
        };
      };

      attribution = {
        enable = true;

        methods = [
          "system-logs"
          "audit-trails"
          "session-records"
          "api-calls"
        ];

        correlation = {
          enable = true;
          sources = [ "ssh" "sudo" "systemd" "application" ];
          confidence = 0.8;
        };
      };
    };

    analytics = {
      enable = true;

      metrics = {
        driftFrequency = true;
        driftSeverity = true;
        remediationSuccess = true;
        changeTrends = true;
      };

      reporting = {
        schedules = [
          {
            name = "daily-drift-summary";
            frequency = "daily";
            recipients = [ "ops@example.com" ];
            include = [ "drift-events" "remediation-actions" "trends" ];
          }
          {
            name = "weekly-compliance";
            frequency = "weekly";
            recipients = [ "compliance@example.com" ];
            include = [ "compliance-status" "violations" "recommendations" ];
          }
          {
            name = "monthly-analysis";
            frequency = "monthly";
            recipients = [ "management@example.com" ];
            include = [ "trend-analysis" "risk-assessment" "improvements" ];
          }
        ];
      };

      dashboard = {
        enable = true;

        panels = [
          { title = "Drift Events"; type = "timeline"; }
          { title = "Severity Distribution"; type = "pie"; }
          { title = "Remediation Success"; type = "gauge"; }
          { title = "Change Trends"; type = "trend"; }
        ];
      };
    };

    integration = {
      siem = {
        enable = true;
        endpoint = "https://siem.example.com";
        events = [ "drift-detected" "change-made" "remediation-action" ];
      };

      ticketing = {
        enable = true;
        system = "jira";
        endpoint = "https://company.atlassian.net";

        projects = [ "SEC" "OPS" ];
        priorities = [ "High" "Medium" "Low" ];
      };

      compliance = {
        enable = true;
        frameworks = [ "sox" "hipaa" "pci-dss" "iso-27001" ];

        reporting = true;
        audit = true;
        retention = "7y";
      };
    };
  };

  # Enhanced drift detector utilities
  driftDetectorUtils = ''
    import os
    import sys
    import logging
    import hashlib
    import json
    import time
    import stat
    import shutil
    from datetime import datetime, timedelta
    from pathlib import Path
    import subprocess

    # Configure logging
    logging.basicConfig(
        level=logging.INFO,
        format='''%(asctime)s - %(name)s - %(levelname)s - %(message)s'''
    )
    logger = logging.getLogger("DriftDetector")

    class DriftDetector:
        """Advanced configuration drift detection and management"""

        def __init__(self, config):
            self.config = config
            self.baseline_config = config.get('baseline', {})
            self.monitoring_config = config.get('monitoring', {})
            self.drift_config = config.get('drift', {})

        def create_baseline(self, name, paths, timestamp=None):
            """Create a configuration baseline"""
            if timestamp is None:
                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

            baseline_dir = self.baseline_config.get('storage', {}).get('path', '/var/lib/config-drift/baselines')
            baseline_path = os.path.join(baseline_dir, f"baseline_{name}_{timestamp}")

            os.makedirs(baseline_path, exist_ok=True)

            baseline_data = {
                'name': name,
                'timestamp': timestamp,
                'paths': {},
                'metadata': {
                    'created_by': 'drift-detector',
                    'version': '1.0'
                }
            }

            logger.info(f"Creating baseline: {baseline_path}")

            for path in paths:
                if os.path.exists(path):
                    self._capture_path_baseline(path, baseline_data, baseline_path)
                else:
                    logger.warning(f"Path does not exist: {path}")

            # Save baseline metadata
            metadata_file = os.path.join(baseline_path, 'metadata.json')
            with open(metadata_file, 'w') as f:
                json.dump(baseline_data, f, indent=2)

            logger.info(f"Baseline created: {baseline_path}")
            return baseline_path

        def _capture_path_baseline(self, path, baseline_data, baseline_path):
            """Capture baseline for a specific path"""
            if os.path.isfile(path):
                self._capture_file_baseline(path, baseline_data, baseline_path)
            elif os.path.isdir(path):
                self._capture_directory_baseline(path, baseline_data, baseline_path)

        def _capture_file_baseline(self, file_path, baseline_data, baseline_path):
            """Capture baseline for a single file"""
            try:
                # Calculate file hash
                with open(file_path, 'rb') as f:
                    content = f.read()
                    file_hash = hashlib.sha256(content).hexdigest()

                # Get file attributes
                stat_info = os.stat(file_path)
                attributes = {
                    'size': stat_info.st_size,
                    'mode': oct(stat_info.st_mode),
                    'uid': stat_info.st_uid,
                    'gid': stat_info.st_gid,
                    'mtime': stat_info.st_mtime,
                    'hash': file_hash
                }

                # Store in baseline
                rel_path = os.path.relpath(file_path, '/')
                baseline_data['paths'][rel_path] = attributes

                # Copy file to baseline directory
                baseline_file = os.path.join(baseline_path, 'files', rel_path)
                os.makedirs(os.path.dirname(baseline_file), exist_ok=True)
                shutil.copy2(file_path, baseline_file)

                logger.debug(f"Captured baseline for file: {file_path}")

            except Exception as e:
                logger.error(f"Failed to capture baseline for {file_path}: {e}")

        def _capture_directory_baseline(self, dir_path, baseline_data, baseline_path):
            """Capture baseline for a directory"""
            for root, dirs, files in os.walk(dir_path):
                for file in files:
                    file_path = os.path.join(root, file)
                    self._capture_file_baseline(file_path, baseline_data, baseline_path)

        def detect_drift(self, baseline_path, current_paths=None):
            """Detect configuration drift against a baseline"""
            logger.info(f"Detecting drift against baseline: {baseline_path}")

            # Load baseline
            metadata_file = os.path.join(baseline_path, 'metadata.json')
            if not os.path.exists(metadata_file):
                raise FileNotFoundError(f"Baseline metadata not found: {metadata_file}")

            with open(metadata_file, 'r') as f:
                baseline_data = json.load(f)

            drift_events = []

            # Check each path in baseline
            for path, baseline_attrs in baseline_data.get('paths', {}).items():
                full_path = os.path.join('/', path)

                if current_paths and full_path not in current_paths:
                    continue

                drift = self._check_path_drift(full_path, baseline_attrs, baseline_path)
                if drift:
                    drift_events.extend(drift)

            # Check for new files not in baseline
            if current_paths:
                for path in current_paths:
                    rel_path = os.path.relpath(path, '/')
                    if rel_path not in baseline_data.get('paths', {}):
                        drift_events.append({
                            'type': 'new_file',
                            'path': path,
                            'severity': 'low',
                            'description': f"New file not in baseline: {path}"
                        })

            logger.info(f"Drift detection complete. Found {len(drift_events)} drift events")
            return drift_events

        def _check_path_drift(self, path, baseline_attrs, baseline_path):
            """Check for drift in a specific path"""
            drift_events = []

            if not os.path.exists(path):
                drift_events.append({
                    'type': 'file_deleted',
                    'path': path,
                    'severity': 'high',
                    'description': f"File deleted: {path}"
                })
                return drift_events

            try:
                # Check file hash
                with open(path, 'rb') as f:
                    content = f.read()
                    current_hash = hashlib.sha256(content).hexdigest()

                baseline_hash = baseline_attrs.get('hash')
                if current_hash != baseline_hash:
                    severity = self._classify_drift_severity(path, 'content_change')
                    drift_events.append({
                        'type': 'content_changed',
                        'path': path,
                        'severity': severity,
                        'description': f"Content changed: {path}",
                        'old_hash': baseline_hash,
                        'new_hash': current_hash
                    })

                # Check permissions
                stat_info = os.stat(path)
                current_mode = oct(stat_info.st_mode)
                baseline_mode = baseline_attrs.get('mode')

                if current_mode != baseline_mode:
                    severity = self._classify_drift_severity(path, 'permission_change')
                    drift_events.append({
                        'type': 'permission_changed',
                        'path': path,
                        'severity': severity,
                        'description': f"Permissions changed: {path}",
                        'old_mode': baseline_mode,
                        'new_mode': current_mode
                    })

                # Check ownership
                current_uid = stat_info.st_uid
                current_gid = stat_info.st_gid
                baseline_uid = baseline_attrs.get('uid')
                baseline_gid = baseline_attrs.get('gid')

                if current_uid != baseline_uid or current_gid != baseline_gid:
                    severity = self._classify_drift_severity(path, 'ownership_change')
                    drift_events.append({
                        'type': 'ownership_changed',
                        'path': path,
                        'severity': severity,
                        'description': f"Ownership changed: {path}",
                        'old_uid': baseline_uid,
                        'old_gid': baseline_gid,
                        'new_uid': current_uid,
                        'new_gid': current_gid
                    })

            except Exception as e:
                logger.error(f"Error checking drift for {path}: {e}")

            return drift_events

        def _classify_drift_severity(self, path, drift_type):
            """Classify the severity of a drift event"""
            severity_config = self.drift_config.get('classification', {}).get('severity', [])

            # Default severity mapping
            severity_map = {
                'security-policy': 'critical',
                'access-control': 'critical',
                'encryption-keys': 'critical',
                'service-config': 'high',
                'network-config': 'high',
                'firewall-rules': 'high',
                'system-config': 'medium',
                'application-config': 'medium',
                'documentation': 'low',
                'log-config': 'low'
            }

            # Determine file type
            file_type = 'system-config'  # default

            if 'security' in path or 'ssl' in path or 'crypto' in path:
                file_type = 'security-policy'
            elif 'network' in path or 'firewall' in path:
                file_type = 'network-config'
            elif 'systemd' in path or 'service' in path:
                file_type = 'service-config'

            return severity_map.get(file_type, 'medium')

        def remediate_drift(self, drift_event, baseline_path):
            """Remediate a detected drift"""
            logger.info(f"Remediating drift: {drift_event['type']} for {drift_event['path']}")

            remediation_config = self.drift_config.get('remediation', {})

            if drift_event['severity'] == 'critical' and remediation_config.get('automatic', {}).get('enable', False):
                # Automatic remediation for critical drifts
                if drift_event['type'] in ['content_changed', 'permission_changed', 'ownership_changed']:
                    return self._restore_from_baseline(drift_event['path'], baseline_path)
                elif drift_event['type'] == 'file_deleted':
                    return self._restore_file_from_baseline(drift_event['path'], baseline_path)

            # For other cases, create ticket or notify
            logger.info(f"Manual remediation required for {drift_event['path']}")
            return False

        def _restore_from_baseline(self, path, baseline_path):
            """Restore a file from baseline"""
            try:
                rel_path = os.path.relpath(path, '/')
                baseline_file = os.path.join(baseline_path, 'files', rel_path)

                if os.path.exists(baseline_file):
                    # Create backup of current file
                    backup_path = f"{path}.drift-backup"
                    if os.path.exists(path):
                        shutil.copy2(path, backup_path)

                    # Restore from baseline
                    shutil.copy2(baseline_file, path)

                    logger.info(f"Restored {path} from baseline")
                    return True
                else:
                    logger.error(f"Baseline file not found: {baseline_file}")
                    return False

            except Exception as e:
                logger.error(f"Failed to restore {path}: {e}")
                return False

        def _restore_file_from_baseline(self, path, baseline_path):
            """Restore a deleted file from baseline"""
            return self._restore_from_baseline(path, baseline_path)

        def monitor_changes(self, paths, callback=None):
            """Monitor paths for real-time changes"""
            logger.info(f"Starting real-time monitoring for {len(paths)} paths")

            # Use inotify or similar for real-time monitoring
            # For this implementation, we'll use periodic checks
            import time

            monitored_files = {}
            for path in paths:
                if os.path.exists(path):
                    monitored_files[path] = self._get_file_signature(path)

            while True:
                for path in paths:
                    if os.path.exists(path):
                        current_sig = self._get_file_signature(path)
                        if path in monitored_files:
                            if current_sig != monitored_files[path]:
                                logger.info(f"Change detected: {path}")
                                if callback:
                                    callback(path, 'modified')
                                monitored_files[path] = current_sig
                        else:
                            logger.info(f"New file detected: {path}")
                            if callback:
                                callback(path, 'created')
                            monitored_files[path] = current_sig
                    elif path in monitored_files:
                        logger.info(f"File deleted: {path}")
                        if callback:
                            callback(path, 'deleted')
                        del monitored_files[path]

                time.sleep(30)  # Check every 30 seconds

        def _get_file_signature(self, path):
            """Get a signature for file change detection"""
            try:
                stat_info = os.stat(path)
                with open(path, 'rb') as f:
                    content = f.read()
                    content_hash = hashlib.sha256(content).hexdigest()

                return {
                    'size': stat_info.st_size,
                    'mtime': stat_info.st_mtime,
                    'hash': content_hash,
                    'mode': oct(stat_info.st_mode)
                }
            except Exception:
                return None

        def generate_report(self, drift_events, time_period="daily"):
            """Generate drift analysis report"""
            logger.info(f"Generating {time_period} drift report")

            report = {
                'period': time_period,
                'timestamp': datetime.now().isoformat(),
                'summary': {
                    'total_events': len(drift_events),
                    'critical_events': len([e for e in drift_events if e['severity'] == 'critical']),
                    'high_events': len([e for e in drift_events if e['severity'] == 'high']),
                    'medium_events': len([e for e in drift_events if e['severity'] == 'medium']),
                    'low_events': len([e for e in drift_events if e['severity'] == 'low'])
                },
                'events': drift_events,
                'recommendations': self._generate_recommendations(drift_events)
            }

            return report

        def _generate_recommendations(self, drift_events):
            """Generate recommendations based on drift events"""
            recommendations = []

            critical_count = len([e for e in drift_events if e['severity'] == 'critical'])
            if critical_count > 0:
                recommendations.append({
                    'priority': 'high',
                    'action': 'security-review',
                    'description': f"Review {critical_count} critical security drifts"
                })

            # Add more recommendation logic
            recommendations.append({
                'priority': 'medium',
                'action': 'baseline-update',
                'description': "Consider updating baseline to include approved changes"
            })

            return recommendations

    def main():
        """Main function for command-line usage"""
        if len(sys.argv) < 2:
            print("Usage: drift-detector <command> [args...]")
            print("Commands: baseline, detect, monitor, report")
            sys.exit(1)

        command = sys.argv[1]

        if command == 'baseline':
            if len(sys.argv) < 4:
                print("Usage: drift-detector baseline <config_file> <name> <path1> [path2...]")
                sys.exit(1)

            config_file = sys.argv[2]
            name = sys.argv[3]
            paths = sys.argv[4:]

            try:
                with open(config_file, 'r') as f:
                    config = json.load(f)

                detector = DriftDetector(config)
                result = detector.create_baseline(name, paths)
                print(f"Baseline created: {result}")

            except Exception as e:
                print(f"Baseline creation failed: {e}")
                sys.exit(1)

        elif command == 'detect':
            if len(sys.argv) < 4:
                print("Usage: drift-detector detect <config_file> <baseline_path> [current_paths...]")
                sys.exit(1)

            config_file = sys.argv[2]
            baseline_path = sys.argv[3]
            current_paths = sys.argv[4:] if len(sys.argv) > 4 else None

            try:
                with open(config_file, 'r') as f:
                    config = json.load(f)

                detector = DriftDetector(config)
                drift_events = detector.detect_drift(baseline_path, current_paths)

                print(f"Drift detection complete. Found {len(drift_events)} events:")
                for event in drift_events:
                    print(f"  {event['severity'].upper()}: {event['description']}")

            except Exception as e:
                print(f"Drift detection failed: {e}")
                sys.exit(1)

        elif command == 'monitor':
            if len(sys.argv) < 4:
                print("Usage: drift-detector monitor <config_file> <path1> [path2...]")
                sys.exit(1)

            config_file = sys.argv[2]
            paths = sys.argv[3:]

            try:
                with open(config_file, 'r') as f:
                    config = json.load(f)

                detector = DriftDetector(config)

                def change_callback(path, action):
                    print(f"CHANGE: {action.upper()} - {path}")

                detector.monitor_changes(paths, change_callback)

            except Exception as e:
                print(f"Monitoring failed: {e}")
                sys.exit(1)

        elif command == 'report':
            if len(sys.argv) < 4:
                print("Usage: drift-detector report <config_file> <drift_events_file> [period]")
                sys.exit(1)

            config_file = sys.argv[2]
            events_file = sys.argv[3]
            period = sys.argv[4] if len(sys.argv) > 4 else "daily"

            try:
                with open(config_file, 'r') as f:
                    config = json.load(f)

                with open(events_file, 'r') as f:
                    drift_events = json.load(f)

                detector = DriftDetector(config)
                report = detector.generate_report(drift_events, period)

                print("Drift Report:")
                print(f"Period: {report['period']}")
                print(f"Total Events: {report['summary']['total_events']}")
                print(f"Critical: {report['summary']['critical_events']}")
                print(f"High: {report['summary']['high_events']}")
                print(f"Medium: {report['summary']['medium_events']}")
                print(f"Low: {report['summary']['low_events']}")

            except Exception as e:
                print(f"Report generation failed: {e}")
                sys.exit(1)

        else:
            print(f"Unknown command: {command}")
            sys.exit(1)

    if __name__ == "__main__":
        main()
  '';

  # Utility functions for configuration drift detection
  utils = {
    # Validate configuration drift detection configuration
    validateConfig = config:
      let
        inherit (lib) types;
        cfg = config.services.gateway.configDrift or {};
      in
      if cfg.enable or false then
        # Basic validation - check required fields
        if !(cfg ? baseline) then
          throw "Configuration drift detection enabled but no baseline configuration provided"
        else if !(cfg ? monitoring) then
          throw "Configuration drift detection enabled but no monitoring configuration provided"
        else if !(cfg ? drift) then
          throw "Configuration drift detection enabled but no drift configuration provided"
        else
          cfg
      else
        cfg;

    # Generate baseline creation script
    generateBaselineScript = baselineConfig: ''
      #!/bin/bash
      set -e

      BASELINE_NAME="$1"
      TIMESTAMP=$(date +%Y%m%d_%H%M%S)
      BASELINE_DIR="${baselineConfig.storage.path}/baseline_$BASELINE_NAME_$TIMESTAMP"

      mkdir -p "$BASELINE_DIR"

      echo "Creating baseline: $BASELINE_NAME"

      # Create baseline using drift detector
      gateway-drift-detector baseline "${baselineConfig}" "$BASELINE_NAME" ${lib.concatStringsSep " " baselineConfig.creation.sources}

      echo "Baseline created: $BASELINE_DIR"
    '';

    # Generate drift detection script
    generateDriftDetectionScript = config: ''
      #!/bin/bash
      set -e

      BASELINE_PATH="$1"
      OUTPUT_FILE="${config.monitoring.scheduled.scans[0].name}_drift_$(date +%Y%m%d_%H%M%S).json"

      echo "Detecting configuration drift..."

      # Run drift detection
      gateway-drift-detector detect "${config}" "$BASELINE_PATH" > "$OUTPUT_FILE"

      echo "Drift detection complete. Results saved to: $OUTPUT_FILE"

      # Check for critical drifts
      CRITICAL_COUNT=$(grep -c '"severity": "critical"' "$OUTPUT_FILE" || true)
      if [ "$CRITICAL_COUNT" -gt 0 ]; then
        echo "WARNING: $CRITICAL_COUNT critical drifts detected!"
        # Send alert
      fi
    '';

    # Generate real-time monitoring script
    generateMonitoringScript = monitoringConfig: ''
      #!/bin/bash

      LOG_FILE="/var/log/gateway/drift-monitoring.log"

      log() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
      }

      log "Starting real-time drift monitoring..."

      # Monitor paths for changes
      gateway-drift-detector monitor "${monitoringConfig}" ${lib.concatStringsSep " " monitoringConfig.realTime.paths}

      log "Real-time monitoring stopped"
    '';

    # Generate systemd timer configuration
    generateSystemdTimer = name: schedule: ''
      [Unit]
      Description=Timer for ${name} configuration drift check
      PartOf=${name}.service

      [Timer]
      OnCalendar=${schedule}
      Persistent=true

      [Install]
      WantedBy=timers.target
    '';

    # Generate systemd service configuration
    generateSystemdService = name: script: ''
      [Unit]
      Description=${name} configuration drift detection service
      After=network-online.target
      Wants=network-online.target

      [Service]
      Type=oneshot
      ExecStart=${script}
      User=root
      Group=root
      PrivateTmp=true
      ProtectSystem=strict
      ReadWritePaths=${lib.concatStringsSep " " [
        "/var/lib/config-drift"
        "/var/log/gateway"
        "/tmp"
      ]}

      [Install]
      WantedBy=multi-user.target
    '';

    # Merge user config with defaults
    mergeConfig = userConfig:
      lib.recursiveUpdate defaultConfigDriftConfig userConfig;
  };

in
{
  inherit defaultConfigDriftConfig driftDetectorUtils utils;
}

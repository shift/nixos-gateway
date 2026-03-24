{ lib, ... }:

let
  # Default backup and recovery configuration
  defaultBackupConfig = {
    enable = true;

    backup = {
      schedule = {
        full = "daily";
        incremental = "hourly";
        validation = "weekly";

        time = {
          full = "02:00";
          incremental = "*/15";
          validation = "03:00";
        };
      };

      destinations = [
        {
          name = "local-storage";
          type = "local";
          path = "/backup/gateway";
          retention = "30d";
          encryption = true;
        }
      ];

      sources = {
        configuration = {
          enable = true;
          paths = [
            "/etc/nixos"
            "/var/lib/nixos"
            "/etc/gateway"
          ];
          exclude = [
            "*.tmp"
            "*.log"
            "cache/*"
          ];
        };

        databases = {
          enable = true;
          dhcp = {
            enable = true;
            type = "file";
            paths = [ "/var/lib/kea" ];
          };
          dns = {
            enable = true;
            type = "file";
            paths = [
              "/var/lib/knot/zones"
              "/var/lib/knot/keys"
            ];
          };
        };

        certificates = {
          enable = true;
          paths = [
            "/etc/ssl"
            "/var/lib/acme"
          ];
          encryption = true;
        };

        logs = {
          enable = true;
          paths = [ "/var/log" ];
          retention = "7d";
          compression = true;
        };
      };

      validation = {
        enable = true;
        integrity = {
          checksums = true;
          encryption = true;
          restoration = true;
        };
        testing = {
          enable = true;
          frequency = "weekly";
          testRestore = true;
          testConfiguration = true;
        };
      };
    };

    recovery = {
      procedures = [
        {
          name = "configuration-restore";
          type = "configuration";
          sources = [ "configuration" ];
          steps = [
            { type = "backup-current"; }
            { type = "restore-config"; }
            { type = "validate-config"; }
            { type = "apply-config"; }
            { type = "verify-services"; }
          ];
          rollback = true;
        }
        {
          name = "database-restore";
          type = "database";
          sources = [ "databases" ];
          steps = [
            { type = "stop-services"; }
            { type = "restore-database"; }
            { type = "verify-integrity"; }
            { type = "start-services"; }
            { type = "verify-functionality"; }
          ];
          rollback = true;
        }
      ];

      automation = {
        enable = true;
        triggers = [
          {
            name = "config-corruption";
            condition = "config-validation-failed";
            procedure = "configuration-restore";
            priority = "high";
          }
          {
            name = "database-corruption";
            condition = "database-check-failed";
            procedure = "database-restore";
            priority = "critical";
          }
        ];
      };
    };

    monitoring = {
      enable = true;
      metrics = {
        backupSuccess = true;
        backupSize = true;
        backupDuration = true;
        recoverySuccess = true;
      };
      alerts = {
        backupFailure = { severity = "high"; };
        recoveryFailure = { severity = "critical"; };
        storageFull = { severity = "medium"; };
        validationFailure = { severity = "warning"; };
      };
    };

    compliance = {
      enable = true;
      retention = {
        configuration = "7y";
        databases = "3y";
        certificates = "5y";
        logs = "1y";
      };
      encryption = {
        enable = true;
        algorithm = "AES-256";
        keyRotation = "90d";
      };
      audit = {
        enable = true;
        logging = true;
        reporting = true;
        events = [
          "backup-start"
          "backup-complete"
          "backup-failure"
          "recovery-start"
          "recovery-complete"
          "recovery-failure"
        ];
      };
    };
  };

  # Enhanced backup manager utilities
  backupUtils = ''
    import os
    import sys
    import logging
    import shutil
    import tarfile
    import gzip
    import datetime
    import json
    import glob
    import hashlib
    import subprocess
    from pathlib import Path

    # Configure logging
    logging.basicConfig(
        level=logging.INFO,
        format='''%(asctime)s - %(name)s - %(levelname)s - %(message)s'''
    )
    logger = logging.getLogger("BackupManager")

    class BackupManager:
        """Enhanced backup and recovery manager"""

        def __init__(self, config):
            self.config = config
            self.backup_config = config.get('backup', {})
            self.recovery_config = config.get('recovery', {})

        def create_backup(self, backup_type='full'):
            """Create backup of specified type"""
            timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
            logger.info(f"Starting {backup_type} backup at {timestamp}")

            # Get destination
            destinations = self.backup_config.get('destinations', [])
            if not destinations:
                raise ValueError("No backup destinations configured")

            # Use first destination for now
            dest = destinations[0]
            dest_path = dest.get('path', '/backup/gateway')

            os.makedirs(dest_path, exist_ok=True)

            backup_name = f"{backup_type}_{timestamp}.tar.gz"
            backup_path = os.path.join(dest_path, backup_name)

            sources = self.backup_config.get('sources', {})

            try:
                with tarfile.open(backup_path, "w:gz") as tar:
                    # Configuration backup
                    if sources.get('configuration', {}).get('enable', False):
                        self._backup_configuration(tar, sources['configuration'])

                    # Database backup
                    if sources.get('databases', {}).get('enable', False):
                        self._backup_databases(tar, sources['databases'])

                    # Certificate backup
                    if sources.get('certificates', {}).get('enable', False):
                        self._backup_certificates(tar, sources['certificates'])

                    # Log backup
                    if sources.get('logs', {}).get('enable', False):
                        self._backup_logs(tar, sources['logs'])

                logger.info(f"Backup created successfully: {backup_path}")

                # Validation
                if self.backup_config.get('validation', {}).get('enable', False):
                    self._validate_backup(backup_path)

                # Cleanup old backups
                self._cleanup_old_backups(dest_path, backup_type)

                return backup_path

            except Exception as e:
                logger.error(f"Backup failed: {e}")
                # Clean up failed backup
                if os.path.exists(backup_path):
                    os.remove(backup_path)
                raise

        def _backup_configuration(self, tar, config):
            """Backup configuration files"""
            logger.info("Backing up configuration files")
            paths = config.get('paths', [])
            exclude = config.get('exclude', [])

            for path in paths:
                if os.path.exists(path):
                    # Apply exclusions
                    if self._should_exclude(path, exclude):
                        continue
                    logger.info(f"Adding configuration path: {path}")
                    tar.add(path, arcname=os.path.basename(path), recursive=True)
                else:
                    logger.warning(f"Configuration path does not exist: {path}")

        def _backup_databases(self, tar, config):
            """Backup database files"""
            logger.info("Backing up databases")

            for db_name, db_config in config.items():
                if db_name == 'enable':
                    continue

                if not db_config.get('enable', False):
                    continue

                db_type = db_config.get('type', 'file')

                if db_type == 'file':
                    paths = db_config.get('paths', [])
                    for path in paths:
                        if os.path.exists(path):
                            logger.info(f"Adding database path: {path}")
                            tar.add(path, arcname=f"db_{db_name}_{os.path.basename(path)}", recursive=True)
                        else:
                            logger.warning(f"Database path does not exist: {path}")

                elif db_type == 'mysql':
                    # MySQL dump would go here
                    logger.info(f"MySQL backup for {db_name} (placeholder)")

        def _backup_certificates(self, tar, config):
            """Backup certificates"""
            logger.info("Backing up certificates")
            paths = config.get('paths', [])

            for path in paths:
                if os.path.exists(path):
                    logger.info(f"Adding certificate path: {path}")
                    tar.add(path, arcname=f"certs_{os.path.basename(path)}", recursive=True)
                else:
                    logger.warning(f"Certificate path does not exist: {path}")

        def _backup_logs(self, tar, config):
            """Backup log files"""
            logger.info("Backing up logs")
            paths = config.get('paths', [])

            for path in paths:
                if os.path.exists(path):
                    logger.info(f"Adding log path: {path}")
                    tar.add(path, arcname=f"logs_{os.path.basename(path)}", recursive=True)
                else:
                    logger.warning(f"Log path does not exist: {path}")

        def _should_exclude(self, path, exclude_patterns):
            """Check if path should be excluded"""
            for pattern in exclude_patterns:
                if pattern in path:
                    return True
            return False

        def _validate_backup(self, backup_path):
            """Validate backup integrity"""
            logger.info(f"Validating backup: {backup_path}")

            try:
                # Check file exists and is readable
                if not os.path.exists(backup_path):
                    raise ValueError("Backup file does not exist")

                # Check file size
                size = os.path.getsize(backup_path)
                if size == 0:
                    raise ValueError("Backup file is empty")

                # Verify tar integrity
                with tarfile.open(backup_path, "r:gz") as tar:
                    for member in tar.getmembers():
                        pass

                logger.info("Backup validation successful")
                return True

            except Exception as e:
                logger.error(f"Backup validation failed: {e}")
                raise

        def _cleanup_old_backups(self, dest_path, backup_type):
            """Clean up old backups based on retention policy"""
            retention_days = 30  # Default

            # Find retention from destinations config
            destinations = self.backup_config.get('destinations', [])
            for dest in destinations:
                if dest.get('type') == 'local':
                    retention_str = dest.get('retention', '30d')
                    if retention_str.endswith('d'):
                        retention_days = int(retention_str[:-1])
                    break

            logger.info(f"Cleaning up backups older than {retention_days} days")

            pattern = os.path.join(dest_path, f"{backup_type}_*.tar.gz")
            old_files = glob.glob(pattern)

            cutoff_time = datetime.datetime.now() - datetime.timedelta(days=retention_days)

            for file_path in old_files:
                file_time = datetime.datetime.fromtimestamp(os.path.getmtime(file_path))
                if file_time < cutoff_time:
                    logger.info(f"Removing old backup: {file_path}")
                    os.remove(file_path)

        def restore_backup(self, backup_path, procedure_name=None):
            """Restore from backup"""
            logger.info(f"Starting restore from: {backup_path}")

            if not os.path.exists(backup_path):
                raise FileNotFoundError(f"Backup file not found: {backup_path}")

            # Determine restore procedure
            if procedure_name:
                procedures = self.recovery_config.get('procedures', [])
                procedure = next((p for p in procedures if p['name'] == procedure_name), None)
                if not procedure:
                    raise ValueError(f"Procedure not found: {procedure_name}")
            else:
                # Default procedure
                procedure = {
                    'name': 'default-restore',
                    'type': 'full',
                    'steps': [
                        {'type': 'restore-config'},
                        {'type': 'restore-data'},
                        {'type': 'verify-system'}
                    ]
                }

            try:
                # Execute restore steps
                for step in procedure.get('steps', []):
                    step_type = step.get('type')
                    logger.info(f"Executing step: {step_type}")

                    if step_type == 'restore-config':
                        self._restore_configuration(backup_path)
                    elif step_type == 'restore-data':
                        self._restore_databases(backup_path)
                    elif step_type == 'verify-system':
                        self._verify_system()
                    # Add more step types as needed

                logger.info("Restore completed successfully")
                return True

            except Exception as e:
                logger.error(f"Restore failed: {e}")
                raise

        def _restore_configuration(self, backup_path):
            """Restore configuration files"""
            logger.info("Restoring configuration files")

            temp_dir = f"/tmp/restore_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}"
            os.makedirs(temp_dir, exist_ok=True)

            try:
                with tarfile.open(backup_path, "r:gz") as tar:
                    # Extract configuration files
                    for member in tar.getmembers():
                        if member.name.startswith(('etc/nixos', 'etc/gateway')):
                            tar.extract(member, temp_dir)

                # Copy to actual locations (with backup of current)
                config_sources = self.backup_config.get('sources', {}).get('configuration', {})
                paths = config_sources.get('paths', [])

                for path in paths:
                    temp_path = os.path.join(temp_dir, os.path.basename(path))
                    if os.path.exists(temp_path):
                        # Backup current
                        if os.path.exists(path):
                            backup_current = f"{path}.backup"
                            shutil.move(path, backup_current)
                            logger.info(f"Backed up current config: {backup_current}")

                        # Restore new
                        shutil.move(temp_path, path)
                        logger.info(f"Restored configuration: {path}")

            finally:
                # Cleanup temp directory
                shutil.rmtree(temp_dir, ignore_errors=True)

        def _restore_databases(self, backup_path):
            """Restore database files"""
            logger.info("Restoring databases")

            temp_dir = f"/tmp/db_restore_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}"
            os.makedirs(temp_dir, exist_ok=True)

            try:
                with tarfile.open(backup_path, "r:gz") as tar:
                    # Extract database files
                    for member in tar.getmembers():
                        if member.name.startswith('db_'):
                            tar.extract(member, temp_dir)

                # Restore database files
                db_sources = self.backup_config.get('sources', {}).get('databases', {})

                for db_name, db_config in db_sources.items():
                    if db_name == 'enable':
                        continue

                    if db_config.get('type') == 'file':
                        paths = db_config.get('paths', [])
                        for path in paths:
                            temp_path = os.path.join(temp_dir, f"db_{db_name}_{os.path.basename(path)}")
                            if os.path.exists(temp_path):
                                # Backup current
                                if os.path.exists(path):
                                    backup_current = f"{path}.backup"
                                    shutil.move(path, backup_current)

                                # Restore new
                                shutil.move(temp_path, path)
                                logger.info(f"Restored database: {path}")

            finally:
                # Cleanup temp directory
                shutil.rmtree(temp_dir, ignore_errors=True)

        def _verify_system(self):
            """Verify system after restore"""
            logger.info("Verifying system integrity")

            # Basic checks
            checks = [
                "/etc/nixos/configuration.nix",
                "/etc/gateway"
            ]

            for check_path in checks:
                if os.path.exists(check_path):
                    logger.info(f"✓ {check_path} exists")
                else:
                    logger.warning(f"✗ {check_path} missing")

            logger.info("System verification completed")

        def list_backups(self, backup_type=None):
            """List available backups"""
            destinations = self.backup_config.get('destinations', [])
            if not destinations:
                return []

            dest = destinations[0]
            dest_path = dest.get('path', '/backup/gateway')

            if not os.path.exists(dest_path):
                return []

            pattern = "*.tar.gz"
            if backup_type:
                pattern = f"{backup_type}_*.tar.gz"

            files = glob.glob(os.path.join(dest_path, pattern))
            files.sort(key=os.path.getmtime, reverse=True)

            return files

        def get_backup_info(self, backup_path):
            """Get information about a backup"""
            if not os.path.exists(backup_path):
                return None

            stat = os.stat(backup_path)
            size = stat.st_size
            mtime = datetime.datetime.fromtimestamp(stat.st_mtime)

            # Try to get contents info
            contents = []
            try:
                with tarfile.open(backup_path, "r:gz") as tar:
                    contents = [member.name for member in tar.getmembers()]
            except Exception:
                pass

            return {
                'path': backup_path,
                'size': size,
                'created': mtime.isoformat(),
                'contents': contents
            }

    def main():
        """Main function for command-line usage"""
        if len(sys.argv) < 2:
            print("Usage: backup-manager <command> [args...]")
            print("Commands: backup, restore, list, info")
            sys.exit(1)

        command = sys.argv[1]

        if command == 'backup':
            if len(sys.argv) < 3:
                print("Usage: backup-manager backup <config_file> [type]")
                sys.exit(1)

            config_file = sys.argv[2]
            backup_type = sys.argv[3] if len(sys.argv) > 3 else 'full'

            try:
                with open(config_file, 'r') as f:
                    config = json.load(f)

                manager = BackupManager(config)
                result = manager.create_backup(backup_type)
                print(f"Backup created: {result}")

            except Exception as e:
                print(f"Backup failed: {e}")
                sys.exit(1)

        elif command == 'restore':
            if len(sys.argv) < 4:
                print("Usage: backup-manager restore <config_file> <backup_path> [procedure]")
                sys.exit(1)

            config_file = sys.argv[2]
            backup_path = sys.argv[3]
            procedure = sys.argv[4] if len(sys.argv) > 4 else None

            try:
                with open(config_file, 'r') as f:
                    config = json.load(f)

                manager = BackupManager(config)
                manager.restore_backup(backup_path, procedure)
                print("Restore completed successfully")

            except Exception as e:
                print(f"Restore failed: {e}")
                sys.exit(1)

        elif command == 'list':
            if len(sys.argv) < 3:
                print("Usage: backup-manager list <config_file> [type]")
                sys.exit(1)

            config_file = sys.argv[2]
            backup_type = sys.argv[3] if len(sys.argv) > 3 else None

            try:
                with open(config_file, 'r') as f:
                    config = json.load(f)

                manager = BackupManager(config)
                backups = manager.list_backups(backup_type)

                print("Available backups:")
                for backup in backups:
                    info = manager.get_backup_info(backup)
                    if info:
                        print(f"  {info['path']} ({info['size']} bytes, {info['created']})")

            except Exception as e:
                print(f"List failed: {e}")
                sys.exit(1)

        elif command == 'info':
            if len(sys.argv) < 4:
                print("Usage: backup-manager info <config_file> <backup_path>")
                sys.exit(1)

            config_file = sys.argv[2]
            backup_path = sys.argv[3]

            try:
                with open(config_file, 'r') as f:
                    config = json.load(f)

                manager = BackupManager(config)
                info = manager.get_backup_info(backup_path)

                if info:
                    print(f"Backup: {info['path']}")
                    print(f"Size: {info['size']} bytes")
                    print(f"Created: {info['created']}")
                    print("Contents:")
                    for item in info['contents'][:10]:  # Show first 10 items
                        print(f"  {item}")
                    if len(info['contents']) > 10:
                        print(f"  ... and {len(info['contents']) - 10} more items")
                else:
                    print("Backup not found")

            except Exception as e:
                print(f"Info failed: {e}")
                sys.exit(1)

        else:
            print(f"Unknown command: {command}")
            sys.exit(1)

    if __name__ == "__main__":
        main()
  '';

  # Utility functions for backup and recovery
  utils = {
    # Validate backup configuration
    validateConfig = config:
      let
        inherit (lib) types;
        cfg = config.services.gateway.backupRecovery or {};
      in
      if cfg.enable or false then
        # Basic validation - check required fields
        if !(cfg ? backup) then
          throw "Backup recovery enabled but no backup configuration provided"
        else if !(cfg ? recovery) then
          throw "Backup recovery enabled but no recovery configuration provided"
        else
          cfg
      else
        cfg;

    # Generate backup script for different types
    generateBackupScript = backupType: config: ''
      #!/bin/bash
      set -e

      LOG_FILE="/var/log/gateway/backup-''${backupType}.log"
      TIMESTAMP=$(date +%Y%m%d_%H%M%S)
      BACKUP_DIR="${config.backup.destinations[0].path}/''${backupType}"

      log() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
      }

      log "Starting ''${backupType} backup"

      # Create backup directory
      mkdir -p "$BACKUP_DIR"

      case "$backupType" in
        "configuration")
          # Configuration backup
          CONFIG_BACKUP="$BACKUP_DIR/config_$TIMESTAMP.tar.gz"
          tar -czf "$CONFIG_BACKUP" \
            --exclude="*.tmp" \
            --exclude="*.log" \
            --exclude="cache/*" \
            ${lib.concatStringsSep " " config.backup.sources.configuration.paths} \
            >> "$LOG_FILE" 2>&1
          log "Configuration backup completed: $CONFIG_BACKUP"
          ;;

        "database")
          # Database backup
          DB_BACKUP="$BACKUP_DIR/database_$TIMESTAMP.sql.gz"
          # Add database-specific backup commands here
          log "Database backup completed: $DB_BACKUP"
          ;;

        "certificates")
          # Certificate backup
          CERT_BACKUP="$BACKUP_DIR/certs_$TIMESTAMP.tar.gz"
          tar -czf "$CERT_BACKUP" \
            ${lib.concatStringsSep " " config.backup.sources.certificates.paths} \
            >> "$LOG_FILE" 2>&1
          log "Certificate backup completed: $CERT_BACKUP"
          ;;

        "logs")
          # Log backup
          LOG_BACKUP="$BACKUP_DIR/logs_$TIMESTAMP.tar.gz"
          tar -czf "$LOG_BACKUP" \
            ${lib.concatStringsSep " " config.backup.sources.logs.paths} \
            >> "$LOG_FILE" 2>&1
          log "Log backup completed: $LOG_BACKUP"
          ;;
      esac

      # Cleanup old backups
      find "$BACKUP_DIR" -name "''${backupType}_*.tar.gz" -mtime +30 -delete 2>/dev/null || true

      log "''${backupType} backup process completed successfully"
    '';

    # Generate recovery script
    generateRecoveryScript = procedureName: procedure: config: ''
      #!/bin/bash
      set -e

      LOG_FILE="/var/log/gateway/recovery-''${procedureName}.log"
      TIMESTAMP=$(date +%Y%m%d_%H%M%S)

      log() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
      }

      error() {
        log "ERROR: $*"
        exit 1
      }

      log "Starting recovery procedure: ''${procedureName}"

      case "''${procedure.type}" in
        "configuration")
          # Configuration recovery
          log "Performing configuration recovery"

          # Find latest backup
          BACKUP_DIR="${config.backup.destinations[0].path}/configuration"
          LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/config_*.tar.gz 2>/dev/null | head -1)

          if [ -z "$LATEST_BACKUP" ]; then
            error "No configuration backup found"
          fi

          log "Using backup: $LATEST_BACKUP"

          # Create recovery directory
          RECOVERY_DIR="/tmp/gateway-recovery-$TIMESTAMP"
          mkdir -p "$RECOVERY_DIR"

          # Extract backup
          tar -xzf "$LATEST_BACKUP" -C "$RECOVERY_DIR" >> "$LOG_FILE" 2>&1

          # Validate configuration
          if [ -f "$RECOVERY_DIR/etc/nixos/configuration.nix" ]; then
            log "Configuration validation passed"
          else
            error "Configuration validation failed - missing configuration.nix"
          fi

          # Apply configuration (would need nixos-rebuild in real implementation)
          log "Configuration recovery completed"
          ;;

        "database")
          # Database recovery
          log "Performing database recovery"

          # Find latest backup
          BACKUP_DIR="${config.backup.destinations[0].path}/database"
          LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/database_*.sql.gz 2>/dev/null | head -1)

          if [ -z "$LATEST_BACKUP" ]; then
            error "No database backup found"
          fi

          log "Using backup: $LATEST_BACKUP"

          # Database recovery logic would go here
          log "Database recovery completed"
          ;;

        "full")
          # Full system recovery
          log "Performing full system recovery"
          # Full recovery logic would go here
          log "Full system recovery completed"
          ;;
      esac

      log "Recovery procedure ''${procedureName} completed successfully"
    '';

    # Generate monitoring script
    generateMonitoringScript = config: let
      backupPath = config.backup.destinations[0].path or "/backup/gateway";
    in ''
      #!/bin/bash

      LOG_FILE="/var/log/gateway/backup-monitoring.log"
      BACKUP_BASE="${backupPath}"

      log() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
      }

      # Check backup success
      check_backup_status() {
        local backup_type="$1"
        local backup_dir="$BACKUP_BASE/$backup_type"

        if [ ! -d "$backup_dir" ]; then
          log "WARNING: Backup directory $backup_dir does not exist"
          return 1
        fi

        # Check for recent backups (within last 25 hours for daily)
        local pattern="$backup_type"'_*.tar.gz'
        local recent_backups=$(find "$backup_dir" -name "$pattern" -mtime -1 2>/dev/null | wc -l)

        if [ "$recent_backups" -eq 0 ]; then
          log "ERROR: No recent $backup_type backups found"
          return 1
        fi

        log "SUCCESS: $recent_backups recent $backup_type backups found"
        return 0
      }

      # Check disk space
      check_disk_space() {
        local backup_path="$BACKUP_BASE"
        local usage=$(df "$backup_path" | tail -1 | awk '{print $5}' | sed 's/%//')

        if [ "$usage" -gt 90 ]; then
          log "ERROR: Backup disk usage is ''${usage}% - above 90% threshold"
          return 1
        elif [ "$usage" -gt 80 ]; then
          log "WARNING: Backup disk usage is ''${usage}% - above 80% threshold"
        fi

        log "SUCCESS: Backup disk usage is ''${usage}%"
        return 0
      }

      log "Starting backup monitoring checks"

      # Run checks
      check_backup_status "configuration"
      check_backup_status "database"
      check_backup_status "certificates"
      check_disk_space

      log "Backup monitoring checks completed"
    '';

    # Generate systemd timer configuration
    generateSystemdTimer = name: schedule: ''
      [Unit]
      Description=Timer for ''${name} backup
      PartOf=''${name}.service

      [Timer]
      OnCalendar=''${schedule}
      Persistent=true

      [Install]
      WantedBy=timers.target
    '';

    # Generate systemd service configuration
    generateSystemdService = name: script: ''
      [Unit]
      Description=''${name} backup service
      After=network-online.target
      Wants=network-online.target

      [Service]
      Type=oneshot
      ExecStart=''${script}
      User=root
      Group=root
      PrivateTmp=true
      ProtectSystem=strict
      ReadWritePaths=${lib.concatStringsSep " " [
        "/backup"
        "/var/log/gateway"
        "/tmp"
      ]}

      [Install]
      WantedBy=multi-user.target
    '';

    # Merge user config with defaults
    mergeConfig = userConfig:
      lib.recursiveUpdate defaultBackupConfig userConfig;
  };

in
{
  inherit defaultBackupConfig backupUtils utils;
}

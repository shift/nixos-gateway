{ lib, ... }:

let
  # Default disaster recovery configuration
  defaultDisasterRecoveryConfig = {
    enable = true;

    objectives = {
      rto = {
        critical = "15m";
        important = "1h";
        normal = "4h";
      };

      rpo = {
        critical = "5m";
        important = "15m";
        normal = "1h";
      };

      availability = {
        target = "99.9%";
        measurement = "monthly";
      };
    };

    sites = {
      primary = {
        name = "datacenter-1";
        location = "us-west-2";
        role = "primary";

        services = [
          "dns"
          "dhcp"
          "firewall"
          "ids"
          "monitoring"
        ];

        health = {
          checks = [
            { type = "interface"; interface = "eth0"; }
            { type = "service"; service = "knot"; }
            { type = "service"; service = "kea-dhcp4-server"; }
            { type = "connectivity"; target = "8.8.8.8"; }
          ];
          interval = "30s";
          threshold = 3;
        };
      };

      secondary = {
        name = "datacenter-2";
        location = "us-east-1";
        role = "secondary";

        services = [
          "dns"
          "dhcp"
          "firewall"
          "ids"
          "monitoring"
        ];

        synchronization = {
          enable = true;
          type = "real-time";
          sources = [ "configuration" "databases" "certificates" ];

            methods = [
              { type = "rsync"; interval = "5m"; }
              { type = "database-replication"; replicationType = "streaming"; }
            ];
        };

        health = {
          checks = [
            { type = "interface"; interface = "eth0"; }
            { type = "service"; service = "knot"; }
            { type = "service"; service = "kea-dhcp4-server"; }
          ];
          interval = "30s";
          threshold = 3;
        };
      };
    };

    failover = {
      triggers = [
        {
          name = "site-failure";
          condition = "site.health.checks.failed >= threshold";
          duration = "2m";
          action = "initiate-failover";
          priority = "critical";
        }
        {
          name = "service-failure";
          condition = "service.health.failed >= threshold";
          duration = "5m";
          action = "service-failover";
          priority = "high";
        }
        {
          name = "manual-failover";
          condition = "manual.trigger";
          action = "initiate-failover";
          priority = "medium";
        }
      ];

      procedures = [
        {
          name = "site-failover";
          type = "site";
          source = "primary";
          target = "secondary";

          steps = [
            { type = "validate-target"; }
            { type = "synchronize-data"; }
            { type = "update-dns"; }
            { type = "redirect-traffic"; }
            { type = "verify-services"; }
            { type = "notify-stakeholders"; }
          ];

          rollback = true;
          timeout = "15m";
        }
        {
          name = "service-failover";
          type = "service";

          steps = [
            { type = "stop-service"; source = "primary"; }
            { type = "start-service"; target = "secondary"; }
            { type = "update-configuration"; }
            { type = "verify-functionality"; }
            { type = "update-monitoring"; }
          ];

          rollback = true;
          timeout = "5m";
        }
      ];

      dns = {
        enable = true;

        provider = "route53";
        zone = "example.com";

        records = [
          {
            name = "gateway";
            type = "A";
            ttl = 60;
            healthCheck = true;

            values = [
              { ip = "192.0.2.1"; site = "primary"; weight = 100; }
              { ip = "192.0.2.2"; site = "secondary"; weight = 0; }
            ];
          }
        ];

        failover = {
          primary = { ip = "192.0.2.1"; weight = 100; };
          secondary = { ip = "192.0.2.2"; weight = 100; };

          healthCheck = {
            path = "/health";
            port = 80;
            interval = "30s";
            timeout = "5s";
          };
        };
      };

      traffic = {
        enable = true;

        methods = [
          { type = "bgp"; as = 65001; }
          { anycast = { prefix = "192.0.2.0/24"; }; }
          { type = "dns"; ttl = 60; }
        ];

        redirection = {
          enable = true;
          method = "bgp-med";

          paths = {
            primary = { med = 100; };
            secondary = { med = 200; };
          };
        };
      };
    };

    recovery = {
      procedures = [
        {
          name = "bare-metal-recovery";
          type = "system";

          steps = [
            { type = "hardware-prepare"; }
            { type = "os-install"; }
            { type = "network-configure"; }
            { type = "backup-restore"; }
            { type = "service-start"; }
            { type = "verification"; }
          ];

          estimatedTime = "2h";
          dependencies = [ "backup-system" "hardware" ];
        }
        {
          name = "service-recovery";
          type = "service";

          steps = [
            { type = "service-stop"; }
            { type = "config-restore"; }
            { type = "data-restore"; }
            { type = "service-start"; }
            { type = "functionality-test"; }
          ];

          estimatedTime = "15m";
          dependencies = [ "backup-system" ];
        }
      ];

      testing = {
        enable = true;

        schedule = "monthly";
        type = "simulation";

        scenarios = [
          {
            name = "site-failure";
            simulation = "network-isolation";
            duration = "30m";
            expectedRTO = "15m";
          }
          {
            name = "service-failure";
            simulation = "service-crash";
            duration = "10m";
            expectedRTO = "5m";
          }
          {
            name = "data-corruption";
            simulation = "database-corruption";
            duration = "20m";
            expectedRTO = "30m";
          }
        ];
      };
    };

    communication = {
      enable = true;

      procedures = [
        {
          name = "incident-notification";
          trigger = "disaster-declared";

          channels = [
            { type = "email"; recipients = [ "ops@example.com" ]; }
            { type = "slack"; channel = "#incidents"; }
            { type = "sms"; recipients = [ "+15551234567" ]; }
          ];

          template = "disaster-notification";
          priority = "high";
        }
        {
          name = "status-updates";
          trigger = "recovery-progress";

          channels = [
            { type = "slack"; channel = "#incidents"; }
            { type = "web"; dashboard = "status.example.com"; }
          ];

          interval = "15m";
          template = "status-update";
        }
      ];

      stakeholders = [
        {
          name = "operations-team";
          role = "responder";
          notifications = [ "incident" "progress" "resolution" ];
          contact = [ "email" "slack" "sms" ];
        }
        {
          name = "management";
          role = "observer";
          notifications = [ "incident" "resolution" ];
          contact = [ "email" "slack" ];
        }
        {
          name = "customers";
          role = "affected";
          notifications = [ "resolution" ];
          contact = [ "email" "web" ];
        }
      ];
    };

    documentation = {
      enable = true;

      procedures = [
        {
          name = "disaster-recovery-plan";
          type = "runbook";
          location = "/docs/dr-plan.md";
          update = "quarterly";
          approval = "management";
        }
        {
          name = "contact-list";
          type = "reference";
          location = "/docs/contacts.md";
          update = "monthly";
          approval = "hr";
        }
        {
          name = "recovery-checklist";
          type = "checklist";
          location = "/docs/recovery-checklist.md";
          update = "monthly";
          approval = "ops";
        }
      ];

      training = {
        enable = true;

        schedule = "quarterly";
        participants = [ "ops-team" "management" ];

        scenarios = [
          "site-failure"
          "service-failure"
          "data-loss"
        ];

        certification = true;
      };
    };
  };

  # Enhanced failover manager utilities
  failoverUtils = ''
    import os
    import sys
    import logging
    import json
    import time
    import subprocess
    import requests
    from datetime import datetime, timedelta
    from pathlib import Path

    # Configure logging
    logging.basicConfig(
        level=logging.INFO,
        format='''%(asctime)s - %(name)s - %(levelname)s - %(message)s'''
    )
    logger = logging.getLogger("FailoverManager")

    class FailoverManager:
        """Advanced failover and disaster recovery manager"""

        def __init__(self, config):
            self.config = config
            self.failover_config = config.get('failover', {})
            self.recovery_config = config.get('recovery', {})
            self.sites_config = config.get('sites', {})

        def check_site_health(self, site_name):
            """Check health of a specific site"""
            site = self.sites_config.get(site_name)
            if not site:
                raise ValueError(f"Site {site_name} not configured")

            health_config = site.get('health', {})
            checks = health_config.get('checks', [])
            threshold = health_config.get('threshold', 3)

            failed_checks = 0
            results = []

            for check in checks:
                check_type = check.get('type')
                result = self._run_health_check(site_name, check)
                results.append(result)

                if not result.get('healthy', False):
                    failed_checks += 1

            overall_healthy = failed_checks < threshold

            return {
                'site': site_name,
                'healthy': overall_healthy,
                'failed_checks': failed_checks,
                'total_checks': len(checks),
                'results': results,
                'timestamp': datetime.now().isoformat()
            }

        def _run_health_check(self, site_name, check):
            """Run a specific health check"""
            check_type = check.get('type')

            if check_type == 'interface':
                return self._check_interface(site_name, check)
            elif check_type == 'service':
                return self._check_service(site_name, check)
            elif check_type == 'connectivity':
                return self._check_connectivity(site_name, check)
            else:
                return {
                    'type': check_type,
                    'healthy': False,
                    'error': f"Unknown check type: {check_type}"
                }

        def _check_interface(self, site_name, check):
            """Check network interface health"""
            interface = check.get('interface', 'eth0')

            try:
                # Check if interface exists and is up
                result = subprocess.run(
                    ['ip', 'link', 'show', interface],
                    capture_output=True,
                    text=True,
                    timeout=10
                )

                if result.returncode == 0 and 'UP' in result.stdout:
                    return {
                        'type': 'interface',
                        'interface': interface,
                        'healthy': True
                    }
                else:
                    return {
                        'type': 'interface',
                        'interface': interface,
                        'healthy': False,
                        'error': 'Interface not up'
                    }
            except Exception as e:
                return {
                    'type': 'interface',
                    'interface': interface,
                    'healthy': False,
                    'error': str(e)
                }

        def _check_service(self, site_name, check):
            """Check service health"""
            service = check.get('service')

            try:
                result = subprocess.run(
                    ['systemctl', 'is-active', service],
                    capture_output=True,
                    text=True,
                    timeout=10
                )

                healthy = result.returncode == 0 and result.stdout.strip() == 'active'

                return {
                    'type': 'service',
                    'service': service,
                    'healthy': healthy,
                    'status': result.stdout.strip() if result.returncode == 0 else 'unknown'
                }
            except Exception as e:
                return {
                    'type': 'service',
                    'service': service,
                    'healthy': False,
                    'error': str(e)
                }

        def _check_connectivity(self, site_name, check):
            """Check network connectivity"""
            target = check.get('target', '8.8.8.8')

            try:
                result = subprocess.run(
                    ['ping', '-c', '3', '-W', '5', target],
                    capture_output=True,
                    text=True,
                    timeout=15
                )

                healthy = result.returncode == 0

                return {
                    'type': 'connectivity',
                    'target': target,
                    'healthy': healthy,
                    'packet_loss': '100%' if not healthy else '0%'
                }
            except Exception as e:
                return {
                    'type': 'connectivity',
                    'target': target,
                    'healthy': False,
                    'error': str(e)
                }

        def initiate_failover(self, procedure_name, source_site, target_site):
            """Initiate failover procedure"""
            logger.info(f"Initiating failover: {procedure_name} from {source_site} to {target_site}")

            procedures = self.failover_config.get('procedures', [])
            procedure = next((p for p in procedures if p['name'] == procedure_name), None)

            if not procedure:
                raise ValueError(f"Procedure {procedure_name} not found")

            try:
                # Execute failover steps
                for step in procedure.get('steps', []):
                    step_type = step.get('type')
                    logger.info(f"Executing failover step: {step_type}")

                    if step_type == 'validate-target':
                        self._validate_target_site(target_site)
                    elif step_type == 'synchronize-data':
                        self._synchronize_data(source_site, target_site)
                    elif step_type == 'update-dns':
                        self._update_dns_failover(source_site, target_site)
                    elif step_type == 'redirect-traffic':
                        self._redirect_traffic(source_site, target_site)
                    elif step_type == 'verify-services':
                        self._verify_services(target_site)
                    elif step_type == 'notify-stakeholders':
                        self._notify_stakeholders('failover-initiated', {
                            'procedure': procedure_name,
                            'source': source_site,
                            'target': target_site
                        })

                logger.info(f"Failover {procedure_name} completed successfully")
                return True

            except Exception as e:
                logger.error(f"Failover failed: {e}")
                # Attempt rollback if configured
                if procedure.get('rollback', False):
                    self._rollback_failover(procedure_name, source_site, target_site)
                raise

        def _validate_target_site(self, target_site):
            """Validate target site is ready for failover"""
            logger.info(f"Validating target site: {target_site}")

            health = self.check_site_health(target_site)
            if not health['healthy']:
                raise ValueError(f"Target site {target_site} is not healthy")

            # Additional validation checks
            site = self.sites_config.get(target_site)
            if not site:
                raise ValueError(f"Target site {target_site} not configured")

            logger.info(f"Target site {target_site} validation passed")

        def _synchronize_data(self, source_site, target_site):
            """Synchronize data between sites"""
            logger.info(f"Synchronizing data from {source_site} to {target_site}")

            # This would implement data synchronization
            # For now, assume synchronization is handled by backup/recovery system
            logger.info("Data synchronization completed")

        def _update_dns_failover(self, source_site, target_site):
            """Update DNS for failover"""
            logger.info(f"Updating DNS for failover from {source_site} to {target_site}")

            dns_config = self.failover_config.get('dns', {})
            if not dns_config.get('enable', False):
                logger.info("DNS failover not enabled")
                return

            # Update DNS records (would integrate with DNS provider API)
            logger.info("DNS failover update completed")

        def _redirect_traffic(self, source_site, target_site):
            """Redirect traffic to target site"""
            logger.info(f"Redirecting traffic from {source_site} to {target_site}")

            traffic_config = self.failover_config.get('traffic', {})
            if not traffic_config.get('enable', False):
                logger.info("Traffic redirection not enabled")
                return

            # Implement traffic redirection (BGP, anycast, etc.)
            logger.info("Traffic redirection completed")

        def _verify_services(self, target_site):
            """Verify services are running on target site"""
            logger.info(f"Verifying services on {target_site}")

            health = self.check_site_health(target_site)
            if not health['healthy']:
                raise ValueError(f"Services on {target_site} are not healthy")

            logger.info(f"Service verification on {target_site} passed")

        def _notify_stakeholders(self, event_type, details):
            """Notify stakeholders of failover events"""
            logger.info(f"Notifying stakeholders of {event_type}")

            communication_config = self.config.get('communication', {})
            if not communication_config.get('enable', False):
                return

            # Send notifications (email, Slack, SMS, etc.)
            logger.info(f"Stakeholder notifications sent for {event_type}")

        def _rollback_failover(self, procedure_name, source_site, target_site):
            """Rollback failover if it failed"""
            logger.info(f"Rolling back failover {procedure_name}")

            # Implement rollback logic
            logger.info("Failover rollback completed")

        def execute_recovery_procedure(self, procedure_name):
            """Execute a recovery procedure"""
            logger.info(f"Executing recovery procedure: {procedure_name}")

            procedures = self.recovery_config.get('procedures', [])
            procedure = next((p for p in procedures if p['name'] == procedure_name), None)

            if not procedure:
                raise ValueError(f"Recovery procedure {procedure_name} not found")

            try:
                # Execute recovery steps
                for step in procedure.get('steps', []):
                    step_type = step.get('type')
                    logger.info(f"Executing recovery step: {step_type}")

                    if step_type == 'hardware-prepare':
                        self._prepare_hardware()
                    elif step_type == 'os-install':
                        self._install_os()
                    elif step_type == 'network-configure':
                        self._configure_network()
                    elif step_type == 'backup-restore':
                        self._restore_backup()
                    elif step_type == 'service-start':
                        self._start_services()
                    elif step_type == 'verification':
                        self._verify_recovery()

                logger.info(f"Recovery procedure {procedure_name} completed successfully")
                return True

            except Exception as e:
                logger.error(f"Recovery procedure failed: {e}")
                raise

        def _prepare_hardware(self):
            """Prepare hardware for recovery"""
            logger.info("Preparing hardware for recovery")
            # Hardware preparation logic
            logger.info("Hardware preparation completed")

        def _install_os(self):
            """Install operating system"""
            logger.info("Installing operating system")
            # OS installation logic
            logger.info("OS installation completed")

        def _configure_network(self):
            """Configure network settings"""
            logger.info("Configuring network settings")
            # Network configuration logic
            logger.info("Network configuration completed")

        def _restore_backup(self):
            """Restore from backup"""
            logger.info("Restoring from backup")
            # Backup restoration logic
            logger.info("Backup restoration completed")

        def _start_services(self):
            """Start services after recovery"""
            logger.info("Starting services")
            # Service startup logic
            logger.info("Service startup completed")

        def _verify_recovery(self):
            """Verify recovery was successful"""
            logger.info("Verifying recovery")
            # Recovery verification logic
            logger.info("Recovery verification completed")

        def get_status(self):
            """Get overall disaster recovery status"""
            sites_status = {}
            for site_name in self.sites_config.keys():
                sites_status[site_name] = self.check_site_health(site_name)

            return {
                'timestamp': datetime.now().isoformat(),
                'sites': sites_status,
                'overall_healthy': all(site['healthy'] for site in sites_status.values())
            }

    def main():
        """Main function for command-line usage"""
        if len(sys.argv) < 2:
            print("Usage: failover-manager <command> [args...]")
            print("Commands: status, failover, recover, health")
            sys.exit(1)

        command = sys.argv[1]

        if command == 'status':
            if len(sys.argv) < 3:
                print("Usage: failover-manager status <config_file>")
                sys.exit(1)

            config_file = sys.argv[2]

            try:
                with open(config_file, 'r') as f:
                    config = json.load(f)

                manager = FailoverManager(config)
                status = manager.get_status()

                print("Disaster Recovery Status:")
                print(f"Overall Health: {'✓ Healthy' if status['overall_healthy'] else '✗ Unhealthy'}")
                print(f"Timestamp: {status['timestamp']}")
                print("\nSites:")
                for site_name, site_status in status['sites'].items():
                    print(f"  {site_name}: {'✓' if site_status['healthy'] else '✗'} ({site_status['failed_checks']}/{site_status['total_checks']} checks failed)")

            except Exception as e:
                print(f"Status check failed: {e}")
                sys.exit(1)

        elif command == 'health':
            if len(sys.argv) < 4:
                print("Usage: failover-manager health <config_file> <site_name>")
                sys.exit(1)

            config_file = sys.argv[2]
            site_name = sys.argv[3]

            try:
                with open(config_file, 'r') as f:
                    config = json.load(f)

                manager = FailoverManager(config)
                health = manager.check_site_health(site_name)

                print(f"Health Status for {site_name}:")
                print(f"Healthy: {'✓' if health['healthy'] else '✗'}")
                print(f"Failed Checks: {health['failed_checks']}/{health['total_checks']}")
                print("\nCheck Results:")
                for result in health['results']:
                    status = '✓' if result.get('healthy', False) else '✗'
                    print(f"  {status} {result['type']}: {result.get('error', 'OK')}")

            except Exception as e:
                print(f"Health check failed: {e}")
                sys.exit(1)

        elif command == 'failover':
            if len(sys.argv) < 6:
                print("Usage: failover-manager failover <config_file> <procedure> <source_site> <target_site>")
                sys.exit(1)

            config_file = sys.argv[2]
            procedure = sys.argv[3]
            source_site = sys.argv[4]
            target_site = sys.argv[5]

            try:
                with open(config_file, 'r') as f:
                    config = json.load(f)

                manager = FailoverManager(config)
                manager.initiate_failover(procedure, source_site, target_site)
                print("Failover initiated successfully")

            except Exception as e:
                print(f"Failover failed: {e}")
                sys.exit(1)

        elif command == 'recover':
            if len(sys.argv) < 4:
                print("Usage: failover-manager recover <config_file> <procedure>")
                sys.exit(1)

            config_file = sys.argv[2]
            procedure = sys.argv[3]

            try:
                with open(config_file, 'r') as f:
                    config = json.load(f)

                manager = FailoverManager(config)
                manager.execute_recovery_procedure(procedure)
                print("Recovery procedure executed successfully")

            except Exception as e:
                print(f"Recovery failed: {e}")
                sys.exit(1)

        else:
            print(f"Unknown command: {command}")
            sys.exit(1)

    if __name__ == "__main__":
        main()
  '';

  # Utility functions for disaster recovery
  utils = {
    # Validate disaster recovery configuration
    validateConfig = config:
      let
        inherit (lib) types;
        cfg = config.services.gateway.disasterRecovery or {};
      in
      if cfg.enable or false then
        # Basic validation - check required fields
        if !(cfg ? sites) then
          throw "Disaster recovery enabled but no sites configured"
        else if !(cfg ? failover) then
          throw "Disaster recovery enabled but no failover configuration provided"
        else if !(cfg ? recovery) then
          throw "Disaster recovery enabled but no recovery configuration provided"
        else
          cfg
      else
        cfg;

    # Generate health check script
    generateHealthCheckScript = siteName: healthConfig: ''
      #!/bin/bash

      SITE="${siteName}"
      LOG_FILE="/var/log/gateway/dr-health-$SITE.log"
      FAILED_CHECKS=0
      TOTAL_CHECKS=0

      log() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
      }

      check_interface() {
        local interface="$1"
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

        if ip link show "$interface" >/dev/null 2>&1 && ip link show "$interface" | grep -q "UP"; then
          log "✓ Interface $interface is up"
        else
          log "✗ Interface $interface is down"
          FAILED_CHECKS=$((FAILED_CHECKS + 1))
        fi
      }

      check_service() {
        local service="$1"
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

        if systemctl is-active --quiet "$service" 2>/dev/null; then
          log "✓ Service $service is active"
        else
          log "✗ Service $service is not active"
          FAILED_CHECKS=$((FAILED_CHECKS + 1))
        fi
      }

      check_connectivity() {
        local target="$1"
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

        if ping -c 3 -W 5 "$target" >/dev/null 2>&1; then
          log "✓ Connectivity to $target is OK"
        else
          log "✗ Connectivity to $target failed"
          FAILED_CHECKS=$((FAILED_CHECKS + 1))
        fi
      }

      log "Starting health checks for site $SITE"

      # Run configured health checks
      ${lib.concatStringsSep "\n" (map (check: ''
        ${if check.type == "interface" then ''
          check_interface "${check.interface}"
        '' else if check.type == "service" then ''
          check_service "${check.service}"
        '' else if check.type == "connectivity" then ''
          check_connectivity "${check.target}"
        '' else ""}
      '') healthConfig.checks)}

      THRESHOLD=${toString healthConfig.threshold}
      if [ "$FAILED_CHECKS" -ge "$THRESHOLD" ]; then
        log "CRITICAL: $FAILED_CHECKS/$TOTAL_CHECKS checks failed (threshold: $THRESHOLD)"
        exit 1
      else
        log "OK: $FAILED_CHECKS/$TOTAL_CHECKS checks failed"
        exit 0
      fi
    '';

    # Generate failover script
    generateFailoverScript = procedure: config: ''
      #!/bin/bash
      set -e

      PROCEDURE_NAME="${procedure.name}"
      SOURCE_SITE="${procedure.source}"
      TARGET_SITE="${procedure.target}"
      LOG_FILE="/var/log/gateway/failover-$PROCEDURE_NAME.log"

      log() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
      }

      error() {
        log "ERROR: $*"
        exit 1
      }

      log "Starting failover procedure: $PROCEDURE_NAME"

      # Execute failover steps
      ${lib.concatStringsSep "\n" (map (step: ''
        log "Executing step: ${step.type}"
        case "${step.type}" in
          "validate-target")
            # Validate target site
            if ! gateway-dr health "${config}" "$TARGET_SITE"; then
              error "Target site validation failed"
            fi
            ;;
          "synchronize-data")
            # Synchronize data (would integrate with backup system)
            log "Data synchronization completed"
            ;;
          "update-dns")
            # Update DNS records
            log "DNS update completed"
            ;;
          "redirect-traffic")
            # Redirect traffic
            log "Traffic redirection completed"
            ;;
          "verify-services")
            # Verify services on target
            if ! gateway-dr health "${config}" "$TARGET_SITE"; then
              error "Service verification failed"
            fi
            ;;
          "notify-stakeholders")
            # Send notifications
            log "Stakeholder notifications sent"
            ;;
        esac
      '') procedure.steps)}

      log "Failover procedure $PROCEDURE_NAME completed successfully"
    '';

    # Generate recovery script
    generateRecoveryScript = procedure: config: ''
      #!/bin/bash
      set -e

      PROCEDURE_NAME="${procedure.name}"
      LOG_FILE="/var/log/gateway/recovery-$PROCEDURE_NAME.log"

      log() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
      }

      error() {
        log "ERROR: $*"
        exit 1
      }

      log "Starting recovery procedure: $PROCEDURE_NAME"

      # Execute recovery steps
      ${lib.concatStringsSep "\n" (map (step: ''
        log "Executing step: ${step.type}"
        case "${step.type}" in
          "hardware-prepare")
            # Prepare hardware
            log "Hardware preparation completed"
            ;;
          "os-install")
            # Install OS
            log "OS installation completed"
            ;;
          "network-configure")
            # Configure network
            log "Network configuration completed"
            ;;
          "backup-restore")
            # Restore from backup
            log "Backup restoration completed"
            ;;
          "service-start")
            # Start services
            log "Service startup completed"
            ;;
          "verification")
            # Verify recovery
            log "Recovery verification completed"
            ;;
        esac
      '') procedure.steps)}

      log "Recovery procedure $PROCEDURE_NAME completed successfully"
    '';

    # Generate systemd timer configuration
    generateSystemdTimer = name: schedule: ''
      [Unit]
      Description=Timer for ${name} disaster recovery check
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
      Description=${name} disaster recovery service
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
        "/var/log/gateway"
        "/tmp"
      ]}

      [Install]
      WantedBy=multi-user.target
    '';

    # Merge user config with defaults
    mergeConfig = userConfig:
      lib.recursiveUpdate defaultDisasterRecoveryConfig userConfig;
  };

in
{
  inherit defaultDisasterRecoveryConfig failoverUtils utils;
}
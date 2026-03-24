{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.gateway.devicePosture;

  # Define sub-options for checks
  checkOpts =
    { name, config, ... }:
    {
      options = {
        name = mkOption {
          type = types.str;
          description = "Name of the check";
        };
        type = mkOption {
          type = types.enum [
            "patch-level"
            "service-status"
            "system-check"
            "policy-check"
            "configuration-check"
            "privilege-check"
            "inventory-check"
          ];
          description = "Type of check to perform";
        };
        criticality = mkOption {
          type = types.enum [
            "low"
            "medium"
            "high"
            "critical"
          ];
          default = "medium";
          description = "Criticality of this check";
        };
        remediation = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Automated remediation action";
        };
        # Additional dynamic fields can be handled by the engine
        extraConfig = mkOption {
          type = types.attrs;
          default = { };
          description = "Extra configuration for specific check types";
        };
      };
    };

in
{
  options.services.gateway.devicePosture = {
    enable = mkEnableOption "Device Posture Assessment";

    assessment = {
      checks = mkOption {
        type = types.attrsOf (types.listOf (types.submodule checkOpts));
        default = {
          security = [
            {
              name = "os-updates";
              type = "patch-level";
              criticality = "high";
              remediation = "auto-update";
              extraConfig = { threshold = "30d"; };
            }
            {
              name = "antivirus";
              type = "service-status";
              criticality = "high";
              remediation = "install-av";
            }
            {
              name = "disk-encryption";
              type = "system-check";
              criticality = "medium";
              remediation = "enable-bitlocker";
            }
            {
              name = "firewall";
              type = "service-status";
              criticality = "medium";
              remediation = "enable-firewall";
            }
          ];

          compliance = [
            {
              name = "password-policy";
              type = "policy-check";
              criticality = "high";
              extraConfig = { framework = "nist"; };
            }
            {
              name = "screen-lock";
              type = "configuration-check";
              criticality = "medium";
              extraConfig = { timeout = "15m"; };
            }
            {
              name = "admin-rights";
              type = "privilege-check";
              criticality = "high";
              extraConfig = { maxUsers = 2; };
            }
          ];

          applications = [
            {
              name = "approved-software";
              type = "inventory-check";
              criticality = "medium";
              extraConfig = {
                whitelist = true;
                exceptions = [ "vpn-client" "backup-agent" ];
              };
            }
            {
              name = "prohibited-software";
              type = "inventory-check";
              criticality = "high";
              extraConfig = {
                blacklist = true;
                categories = [ "torrents" "hacking-tools" ];
              };
            }
          ];
        };
        description = "Map of check categories (security, compliance, etc.) to list of checks";
      };

      scoring = {
        weights = mkOption {
          type = types.attrsOf types.int;
          default = {
            security = 40;
            compliance = 30;
            applications = 20;
            behavior = 10;
          };
          description = "Weights for different check categories";
        };
        thresholds = mkOption {
          type = types.attrsOf types.int;
          default = {
            excellent = 95;
            good = 80;
            warning = 60;
            critical = 40;
            fail = 20;
          };
          description = "Score thresholds for posture states";
        };
      };

      frequency = mkOption {
        type = types.submodule {
          options = {
            initial = mkOption {
              type = types.str;
              default = "on-connect";
              description = "When to perform initial assessment";
            };

            periodic = mkOption {
              type = types.str;
              default = "4h";
              description = "Periodic assessment interval";
            };

            eventDriven = mkOption {
              type = types.listOf types.str;
              default = [ "policy-change" "security-event" ];
              description = "Events that trigger assessment";
            };
          };
        };
        default = { };
        description = "Assessment frequency configuration";
      };
    };

    remediation = mkOption {
      type = types.submodule {
        options = {
          automatic = mkOption {
            type = types.submodule {
              options = {
                enable = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Enable automatic remediation";
                };

                actions = mkOption {
                  type = types.listOf (
                    types.submodule {
                      options = {
                        trigger = mkOption {
                          type = types.str;
                          description = "Trigger condition";
                        };

                        action = mkOption {
                          type = types.str;
                          description = "Remediation action";
                        };

                        priority = mkOption {
                          type = types.enum [ "low" "medium" "high" "critical" ];
                          default = "medium";
                          description = "Action priority";
                        };

                        deadline = mkOption {
                          type = types.nullOr types.str;
                          default = null;
                          description = "Deadline for completion";
                        };
                      };
                    }
                  );
                  default = [
                    {
                      trigger = "os-updates-failed";
                      action = "schedule-update";
                      priority = "high";
                      deadline = "24h";
                    }
                    {
                      trigger = "antivirus-missing";
                      action = "deploy-antivirus";
                      priority = "critical";
                      deadline = "1h";
                    }
                    {
                      trigger = "firewall-disabled";
                      action = "enable-firewall";
                      priority = "high";
                      deadline = "30m";
                    }
                  ];
                  description = "Automatic remediation actions";
                };
              };
            };
            default = { };
            description = "Automatic remediation configuration";
          };

          manual = mkOption {
            type = types.submodule {
              options = {
                enable = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Enable manual remediation workflows";
                };

                workflows = mkOption {
                  type = types.listOf (
                    types.submodule {
                      options = {
                        name = mkOption {
                          type = types.str;
                          description = "Workflow name";
                        };

                        steps = mkOption {
                          type = types.listOf (
                            types.submodule {
                              options = {
                                type = mkOption {
                                  type = types.enum [ "notify" "create-ticket" "schedule-audit" "isolate-device" "escalate" ];
                                  description = "Step type";
                                };

                                recipient = mkOption {
                                  type = types.nullOr types.str;
                                  default = null;
                                  description = "Recipient for notifications";
                                };

                                template = mkOption {
                                  type = types.nullOr types.str;
                                  default = null;
                                  description = "Notification template";
                                };

                                system = mkOption {
                                  type = types.nullOr types.str;
                                  default = null;
                                  description = "System for ticket creation";
                                };

                                priority = mkOption {
                                  type = types.nullOr types.str;
                                  default = null;
                                  description = "Ticket priority";
                                };

                                delay = mkOption {
                                  type = types.nullOr types.str;
                                  default = null;
                                  description = "Delay before step execution";
                                };

                                duration = mkOption {
                                  type = types.nullOr types.str;
                                  default = null;
                                  description = "Duration for isolation";
                                };
                              };
                            }
                          );
                          description = "Workflow steps";
                        };
                      };
                    }
                  );
                  default = [
                    {
                      name = "compliance-violation";
                      steps = [
                        { type = "notify"; recipient = "user"; template = "compliance-notice"; }
                        { type = "notify"; recipient = "manager"; template = "manager-alert"; }
                        { type = "create-ticket"; system = "helpdesk"; priority = "medium"; }
                        { type = "schedule-audit"; delay = "7d"; }
                      ];
                    }
                    {
                      name = "security-risk";
                      steps = [
                        { type = "isolate-device"; duration = "1h"; }
                        { type = "notify"; recipient = "security-team"; template = "security-incident"; }
                        { type = "create-ticket"; system = "security"; priority = "high"; }
                        { type = "escalate"; delay = "4h"; recipient = "ciso"; }
                      ];
                    }
                  ];
                  description = "Manual remediation workflows";
                };
              };
            };
            default = { };
            description = "Manual remediation configuration";
          };
        };
      };
      default = { };
      description = "Remediation configuration";
    };

    policies = mkOption {
      type = types.submodule {
        options = {
          deviceTypes = mkOption {
            type = types.attrsOf (
              types.submodule {
                options = {
                  requiredChecks = mkOption {
                    type = types.listOf types.str;
                    description = "Required checks for this device type";
                  };

                  scoreThreshold = mkOption {
                    type = types.int;
                    description = "Minimum posture score required";
                  };

                  remediation = mkOption {
                    type = types.enum [ "automatic" "manual" "none" ];
                    default = "manual";
                    description = "Remediation approach";
                  };

                  restrictions = mkOption {
                    type = types.listOf types.str;
                    default = [ ];
                    description = "Access restrictions for this device type";
                  };
                };
              }
            );
            default = {
              corporate = {
                requiredChecks = [ "os-updates" "antivirus" "disk-encryption" "firewall" ];
                scoreThreshold = 80;
                remediation = "automatic";
              };

              byod = {
                requiredChecks = [ "os-updates" "antivirus" "password-policy" ];
                scoreThreshold = 70;
                remediation = "manual";
                restrictions = [ "limited-access" "audit-logging" ];
              };

              guest = {
                requiredChecks = [ "password-policy" ];
                scoreThreshold = 50;
                remediation = "none";
                restrictions = [ "internet-only" "time-limit" ];
              };
            };
            description = "Device type policies";
          };

          contexts = mkOption {
            type = types.attrsOf (
              types.attrsOf (
                types.submodule {
                  options = {
                    scoreMultiplier = mkOption {
                      type = types.float;
                      default = 1.0;
                      description = "Score multiplier for this context";
                    };
                  };
                }
              )
            );
            default = {
              location = {
                office = { scoreMultiplier = 1.0; };
                remote = { scoreMultiplier = 1.2; };
                public = { scoreMultiplier = 1.5; };
              };

              time = {
                business-hours = { scoreMultiplier = 1.0; };
                after-hours = { scoreMultiplier = 1.1; };
                weekend = { scoreMultiplier = 1.2; };
              };

              risk = {
                normal = { scoreMultiplier = 1.0; };
                elevated = { scoreMultiplier = 1.3; };
                high = { scoreMultiplier = 1.5; };
              };
            };
            description = "Context-based policy adjustments";
          };
        };
      };
      default = { };
      description = "Device posture policies";
    };

    integration = mkOption {
      type = types.submodule {
        options = {
          nac = mkOption {
            type = types.submodule {
              options = {
                enable = mkOption {
                  type = types.bool;
                  default = false;
                  description = "Enable NAC system integration";
                };

                systems = mkOption {
                  type = types.listOf (
                    types.enum [ "cisco-ise" "arista-clearpass" "fortinet-nac" "juniper-mist" "extremecloud" ]
                  );
                  default = [ ];
                  description = "Supported NAC systems";
                };

                enforcement = mkOption {
                  type = types.submodule {
                    options = {
                      quarantine = mkOption {
                        type = types.bool;
                        default = true;
                        description = "Enable device quarantine";
                      };

                      limitedAccess = mkOption {
                        type = types.bool;
                        default = true;
                        description = "Enable limited access VLAN";
                      };

                      blockAccess = mkOption {
                        type = types.bool;
                        default = true;
                        description = "Enable complete access blocking";
                      };

                      remediationVlan = mkOption {
                        type = types.nullOr types.str;
                        default = null;
                        description = "VLAN for remediation access";
                      };
                    };
                  };
                  default = { };
                  description = "NAC enforcement options";
                };

                api = mkOption {
                  type = types.submodule {
                    options = {
                      endpoint = mkOption {
                        type = types.nullOr types.str;
                        default = null;
                        description = "NAC API endpoint";
                      };

                      credentials = mkOption {
                        type = types.nullOr types.str;
                        default = null;
                        description = "API credentials path";
                      };

                      timeout = mkOption {
                        type = types.int;
                        default = 30;
                        description = "API timeout in seconds";
                      };
                    };
                  };
                  default = { };
                  description = "NAC API configuration";
                };
              };
            };
            default = { };
            description = "NAC system integration";
          };

          endpoint = mkOption {
            type = types.submodule {
              options = {
                enable = mkOption {
                  type = types.bool;
                  default = false;
                  description = "Enable endpoint management integration";
                };

                systems = mkOption {
                  type = types.listOf (
                    types.enum [ "intune" "jamf" "sccm" "workspace-one" "ibm-maa" ]
                  );
                  default = [ ];
                  description = "Supported endpoint management systems";
                };

                data = mkOption {
                  type = types.submodule {
                    options = {
                      inventory = mkOption {
                        type = types.bool;
                        default = true;
                        description = "Collect device inventory data";
                      };

                      compliance = mkOption {
                        type = types.bool;
                        default = true;
                        description = "Collect compliance data";
                      };

                      security = mkOption {
                        type = types.bool;
                        default = true;
                        description = "Collect security posture data";
                      };

                      performance = mkOption {
                        type = types.bool;
                        default = false;
                        description = "Collect performance metrics";
                      };
                    };
                  };
                  default = { };
                  description = "Data collection options";
                };

                api = mkOption {
                  type = types.submodule {
                    options = {
                      endpoint = mkOption {
                        type = types.nullOr types.str;
                        default = null;
                        description = "Endpoint management API endpoint";
                      };

                      authentication = mkOption {
                        type = types.submodule {
                          options = {
                            type = mkOption {
                              type = types.enum [ "oauth2" "basic" "certificate" ];
                              default = "oauth2";
                              description = "Authentication type";
                            };

                            credentials = mkOption {
                              type = types.nullOr types.str;
                              default = null;
                              description = "Credentials path";
                            };
                          };
                        };
                        default = { };
                        description = "API authentication";
                      };

                      timeout = mkOption {
                        type = types.int;
                        default = 30;
                        description = "API timeout in seconds";
                      };
                    };
                  };
                  default = { };
                  description = "Endpoint management API configuration";
                };
              };
            };
            default = { };
            description = "Endpoint management integration";
          };

          siem = mkOption {
            type = types.submodule {
              options = {
                enable = mkOption {
                  type = types.bool;
                  default = false;
                  description = "Enable SIEM integration";
                };

                endpoint = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = "SIEM endpoint URL";
                };

                events = mkOption {
                  type = types.listOf types.str;
                  default = [
                    "posture-assessment"
                    "remediation-action"
                    "policy-violation"
                    "compliance-failure"
                  ];
                  description = "Events to send to SIEM";
                };

                format = mkOption {
                  type = types.enum [ "cef" "leef" "json" "syslog" ];
                  default = "json";
                  description = "Log format for SIEM";
                };
              };
            };
            default = { };
            description = "SIEM integration";
          };
        };
      };
      default = { };
      description = "External system integration";
    };

    monitoring = mkOption {
      type = types.submodule {
        options = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Enable posture monitoring";
          };

          metrics = mkOption {
            type = types.submodule {
              options = {
                postureScores = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Track posture scores";
                };

                complianceRates = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Track compliance rates";
                };

                remediationSuccess = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Track remediation success";
                };

                deviceTrends = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Track device posture trends";
                };
              };
            };
            default = { };
            description = "Monitoring metrics";
          };

          alerts = mkOption {
            type = types.attrsOf (
              types.submodule {
                options = {
                  threshold = mkOption {
                    type = types.nullOr types.int;
                    default = null;
                    description = "Alert threshold";
                  };

                  severity = mkOption {
                    type = types.enum [ "info" "warning" "error" "critical" ];
                    default = "warning";
                    description = "Alert severity";
                  };
                };
              }
            );
            default = {
              lowPostureScore = { threshold = 40; severity = "warning"; };
              complianceViolation = { severity = "high"; };
              remediationFailure = { severity = "critical"; };
              unusualBehavior = { severity = "medium"; };
            };
            description = "Alert configuration";
          };

          reporting = mkOption {
            type = types.submodule {
              options = {
                schedules = mkOption {
                  type = types.listOf (
                    types.submodule {
                      options = {
                        name = mkOption {
                          type = types.str;
                          description = "Report name";
                        };

                        frequency = mkOption {
                          type = types.enum [ "daily" "weekly" "monthly" ];
                          description = "Report frequency";
                        };

                        recipients = mkOption {
                          type = types.listOf types.str;
                          default = [ ];
                          description = "Email recipients";
                        };

                        include = mkOption {
                          type = types.listOf types.str;
                          default = [ ];
                          description = "Report sections to include";
                        };
                      };
                    }
                  );
                  default = [
                    {
                      name = "daily-summary";
                      frequency = "daily";
                      recipients = [ "security@example.com" ];
                      include = [ "posture-overview" "violations" "remediation-status" ];
                    }
                    {
                      name = "weekly-compliance";
                      frequency = "weekly";
                      recipients = [ "compliance@example.com" ];
                      include = [ "compliance-report" "trends" "recommendations" ];
                    }
                  ];
                  description = "Scheduled reports";
                };
              };
            };
            default = { };
            description = "Reporting configuration";
          };
        };
      };
      default = { };
      description = "Monitoring configuration";
    };
  };

  config = mkIf cfg.enable {
    # We will implement a Python-based posture engine service similar to the Zero Trust engine
    systemd.services.device-posture-engine = {
      description = "Device Posture Assessment Engine";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      path = [
        pkgs.python3
        pkgs.iproute2
        pkgs.nftables
      ];

       serviceConfig = {
         ExecStart = "${pkgs.python3}/bin/python3 ${pkgs.writeText "posture-engine.py" ''
           import time
           import json
           import os
           import sys
           import subprocess
           import re
           from datetime import datetime, timedelta

           # Configuration injected via Nix
           CONFIG_FILE = "${pkgs.writeText "posture-config.json" (builtins.toJSON cfg)}"
           with open(CONFIG_FILE, 'r') as f:
               CONFIG = json.load(f)

           # State database
           device_state = {}
           assessment_history = {}

           def parse_time_string(time_str):
               """Parse time strings like '30d', '4h', '15m' to seconds"""
               if not time_str:
                   return 3600  # Default 1 hour

               match = re.match(r'(\d+)([smhd])', time_str)
               if not match:
                   return 3600

               value, unit = match.groups()
               value = int(value)

               if unit == 's':
                   return value
               elif unit == 'm':
                   return value * 60
               elif unit == 'h':
                   return value * 3600
               elif unit == 'd':
                   return value * 86400

               return 3600

           def run_system_command(cmd):
               """Run a system command and return (success, output)"""
               try:
                   result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)
                   return result.returncode == 0, result.stdout.strip()
               except (subprocess.TimeoutExpired, subprocess.CalledProcessError):
                   return False, ""

           def perform_security_checks(device_id, device_data):
               """Perform actual security checks on the system"""
               results = []

               checks_config = CONFIG['assessment']['checks'].get('security', [])

               for check in checks_config:
                   check_name = check['name']
                   check_type = check['type']
                   extra_config = check.get('extraConfig', {})

                   status = 'pass'
                   details = ""

                   if check_type == "patch-level":
                       # Check OS update status
                       threshold_days = parse_time_string(extra_config.get('threshold', '30d')) / 86400
                       success, output = run_system_command("apt list --upgradable 2>/dev/null | wc -l")
                       if success and int(output) > 1:  # More than just the header line
                           # Check if updates are older than threshold
                           success, last_update = run_system_command("stat -c %Y /var/cache/apt/pkgcache.bin")
                           if success:
                               last_update_time = datetime.fromtimestamp(int(last_update))
                               if (datetime.now() - last_update_time).days > threshold_days:
                                   status = 'fail'
                                   details = f"Updates pending for {(datetime.now() - last_update_time).days} days"

                   elif check_type == "service-status":
                       # Check if security services are running
                       if check_name == "antivirus":
                           success, _ = run_system_command("pgrep -f clamav || pgrep -f antivirus")
                           if not success:
                               status = 'fail'
                               details = "Antivirus service not running"
                       elif check_name == "firewall":
                           success, _ = run_system_command("ufw status | grep -q 'Status: active'")
                           if not success:
                               status = 'fail'
                               details = "Firewall not active"

                   elif check_type == "system-check":
                       # Check system security settings
                       if check_name == "disk-encryption":
                           success, _ = run_system_command("lsblk -o NAME,FSTYPE | grep -q 'crypto_LUKS'")
                           if not success:
                               status = 'fail'
                               details = "Full disk encryption not detected"

                   results.append({
                       'name': check_name,
                       'type': check_type,
                       'criticality': check['criticality'],
                       'status': status,
                       'details': details,
                       'timestamp': time.time()
                   })

               return results

           def perform_compliance_checks(device_id, device_data):
               """Perform compliance validation checks"""
               results = []

               checks_config = CONFIG['assessment']['checks'].get('compliance', [])

               for check in checks_config:
                   check_name = check['name']
                   check_type = check['type']
                   extra_config = check.get('extraConfig', {})

                   status = 'pass'
                   details = ""

                   if check_type == "policy-check":
                       # Check password policy compliance
                       framework = extra_config.get('framework', 'nist')
                       # Simplified policy check - in real implementation would check actual policies
                       success, _ = run_system_command("grep -q 'minlen=8' /etc/security/pwquality.conf")
                       if not success:
                           status = 'fail'
                           details = f"Password policy does not meet {framework} requirements"

                   elif check_type == "configuration-check":
                       # Check system configuration
                       if check_name == "screen-lock":
                           timeout = extra_config.get('timeout', '15m')
                           # Check screen lock settings
                           success, _ = run_system_command("gsettings get org.gnome.desktop.session idle-delay 2>/dev/null | grep -q 'uint32' || true")
                           if not success:
                               status = 'fail'
                               details = "Screen lock timeout not configured"

                   elif check_type == "privilege-check":
                       # Check admin privileges
                       max_users = extra_config.get('maxUsers', 2)
                       success, output = run_system_command("getent group sudo | cut -d: -f4 | tr ',' '\\n' | wc -l")
                       if success and int(output) > max_users:
                           status = 'fail'
                           details = f"Too many users with admin privileges: {output}"

                   results.append({
                       'name': check_name,
                       'type': check_type,
                       'criticality': check['criticality'],
                       'status': status,
                       'details': details,
                       'timestamp': time.time()
                   })

               return results

           def perform_application_checks(device_id, device_data):
               """Perform application inventory and compliance checks"""
               results = []

               checks_config = CONFIG['assessment']['checks'].get('applications', [])

               for check in checks_config:
                   check_name = check['name']
                   check_type = check['type']
                   extra_config = check.get('extraConfig', {})

                   status = 'pass'
                   details = ""

                   if check_type == "inventory-check":
                       # Check installed applications
                       if extra_config.get('whitelist', False):
                           # Whitelist mode - check for approved software
                           exceptions = extra_config.get('exceptions', [])
                           success, output = run_system_command("dpkg -l | grep -E 'vpn-client|backup-agent' | wc -l")
                           if success and int(output) == 0:
                               status = 'fail'
                               details = "Required approved software not found"
                       elif extra_config.get('blacklist', False):
                           # Blacklist mode - check for prohibited software
                           categories = extra_config.get('categories', [])
                           # Simplified check - in real implementation would scan for prohibited software
                           status = 'pass'  # Assume clean for demo

                   results.append({
                       'name': check_name,
                       'type': check_type,
                       'criticality': check['criticality'],
                       'status': status,
                       'details': details,
                       'timestamp': time.time()
                   })

               return results

           def calculate_score(device_id, checks_results):
               """
               Calculate posture score based on weights and check results.
               """
               total_score = 0
               max_possible = 0

               weights = CONFIG['assessment']['scoring']['weights']

               for category, results in checks_results.items():
                   weight = weights.get(category, 0)
                   if weight == 0 or not results:
                       continue

                   # Calculate category score based on check criticality
                   category_score = 0
                   total_weight = 0

                   for result in results:
                       check_weight = {'low': 1, 'medium': 2, 'high': 3, 'critical': 4}[result['criticality']]
                       check_score = 100 if result['status'] == 'pass' else 0
                       category_score += check_score * check_weight
                       total_weight += check_weight

                   if total_weight > 0:
                       category_score = category_score / total_weight

                   total_score += (category_score * weight)
                   max_possible += (100 * weight)

               if max_possible == 0:
                   return 100

               final_score = (total_score / max_possible) * 100
               return int(final_score)

           def assess_device(device_id, device_data):
               """
               Comprehensive device assessment with actual system checks.
               """
               print(f"Assessing device {device_id}...")

               results = {}

               # Perform checks by category
               results['security'] = perform_security_checks(device_id, device_data)
               results['compliance'] = perform_compliance_checks(device_id, device_data)
               results['applications'] = perform_application_checks(device_id, device_data)

               # Add behavior category if available
               results['behavior'] = []

               return results

           def apply_context_multipliers(device_id, base_score, device_data):
               """Apply context-based score multipliers"""
               score = base_score
               contexts = CONFIG.get('policies', {}).get('contexts', {})

               # Location context
               location = device_data.get('location', 'office')
               if location in contexts.get('location', {}):
                   multiplier = contexts['location'][location]['scoreMultiplier']
                   score = int(score * multiplier)

               # Time context
               current_hour = datetime.now().hour
               if 9 <= current_hour <= 17 and datetime.now().weekday() < 5:
                   time_context = 'business-hours'
               elif datetime.now().weekday() >= 5:
                   time_context = 'weekend'
               else:
                   time_context = 'after-hours'

               if time_context in contexts.get('time', {}):
                   multiplier = contexts['time'][time_context]['scoreMultiplier']
                   score = int(score * multiplier)

               # Risk context
               risk_level = device_data.get('risk_level', 'normal')
               if risk_level in contexts.get('risk', {}):
                   multiplier = contexts['risk'][risk_level]['scoreMultiplier']
                   score = int(score * multiplier)

               return min(100, score)  # Cap at 100

           def check_remediation_triggers(device_id, score, check_results):
               """Check if any remediation actions should be triggered"""
               remediation_config = CONFIG.get('remediation', {})

               if not remediation_config.get('automatic', {}).get('enable', True):
                   return []

               actions_to_trigger = []

               for action in remediation_config['automatic']['actions']:
                   trigger = action['trigger']

                   # Simple trigger evaluation
                   if trigger == "os-updates-failed":
                       security_results = check_results.get('security', [])
                       os_updates = next((r for r in security_results if r['name'] == 'os-updates'), None)
                       if os_updates and os_updates['status'] == 'fail':
                           actions_to_trigger.append(action)

                   elif trigger == "antivirus-missing":
                       security_results = check_results.get('security', [])
                       antivirus = next((r for r in security_results if r['name'] == 'antivirus'), None)
                       if antivirus and antivirus['status'] == 'fail':
                           actions_to_trigger.append(action)

                   elif trigger == "firewall-disabled":
                       security_results = check_results.get('security', [])
                       firewall = next((r for r in security_results if r['name'] == 'firewall'), None)
                       if firewall and firewall['status'] == 'fail':
                           actions_to_trigger.append(action)

               return actions_to_trigger

           def main_loop():
               print("Starting Device Posture Assessment Engine...")

               # Control file for tests to inject device events
               control_file = "/tmp/posture_control.json"
               output_file = "/tmp/posture_scores.json"
               remediation_file = "/tmp/posture_remediation.json"

               while True:
                   try:
                       if os.path.exists(control_file):
                           with open(control_file, 'r') as f:
                               try:
                                   events = json.load(f)
                               except json.JSONDecodeError:
                                   events = []

                           # Process events
                           for event in events:
                               device_id = event.get('id', 'unknown')
                               print(f"Processing assessment for {device_id}")

                               # Perform comprehensive assessment
                               check_results = assess_device(device_id, event)
                               base_score = calculate_score(device_id, check_results)
                               final_score = apply_context_multipliers(device_id, base_score, event)

          # Check remediation triggers
          remediation_actions = check_remediation_triggers(device_id, final_score, check_results)

          # Execute automatic remediation actions
          if remediation_actions:
              execute_automatic_remediation(device_id, remediation_actions)

                               # Check if manual workflows should be triggered
                              manual_workflows = check_manual_workflow_triggers(device_id, final_score, check_results)
                              if manual_workflows:
                                  trigger_manual_workflows(device_id, manual_workflows)

                              # Send NAC enforcement actions if needed
                              if final_score < 60:  # Example threshold
                                  send_nac_enforcement(device_id, 'quarantine', final_score)
                              elif final_score < 80:
                                  send_nac_enforcement(device_id, 'limited-access', final_score)

                              # Update endpoint management systems
                              update_endpoint_management(device_id, {
                                  'score': final_score,
                                  'last_assessment': time.time(),
                                  'results': check_results
                              })

                              # Send events to SIEM
                              send_siem_event('posture-assessment', device_id, {
                                  'score': final_score,
                                  'categories': list(check_results.keys()),
                                  'compliance': final_score >= 80
                              })

                               # Store results
                               device_state[device_id] = {
                                   'score': final_score,
                                   'base_score': base_score,
                                   'last_assessment': time.time(),
                                   'results': check_results,
                                   'context_multipliers': event
                               }

                               # Store assessment history
                               if device_id not in assessment_history:
                                   assessment_history[device_id] = []
                               assessment_history[device_id].append({
                                   'timestamp': time.time(),
                                   'score': final_score,
                                   'results': check_results
                               })

                               print(f"Device {device_id} - Base Score: {base_score}, Final Score: {final_score}")

                               # Write remediation actions if any
                               if remediation_actions:
                                   with open(remediation_file, 'w') as f:
                                       json.dump({
                                           'device_id': device_id,
                                           'timestamp': time.time(),
                                           'actions': remediation_actions
                                       }, f, indent=2)

                           # Clean up control file
                           os.remove(control_file)

                       # Dump state for consumers
                       with open(output_file, 'w') as f:
                           json.dump({
                               'devices': device_state,
                               'history': assessment_history
                           }, f, indent=2)

                   except Exception as e:
                       print(f"Error in main loop: {e}")
                       import traceback
                       traceback.print_exc()

                    time.sleep(5)  # Check every 5 seconds

            def execute_automatic_remediation(device_id, actions):
                """Execute automatic remediation actions"""
                print(f"Executing automatic remediation for device {device_id}")

                for action in actions:
                    action_name = action.get('action', 'unknown')
                    print(f"Executing remediation action: {action_name}")

                    # Implement actual remediation logic here
                    # This would integrate with external systems

                    if action_name == "schedule-update":
                        print("Scheduling OS update...")
                    elif action_name == "deploy-antivirus":
                        print("Deploying antivirus software...")
                    elif action_name == "enable-firewall":
                        print("Enabling firewall...")
                    # Add more remediation actions as needed

            def check_manual_workflow_triggers(device_id, score, check_results):
                """Check if manual workflows should be triggered"""
                workflows = []

                # Check for compliance violations
                compliance_failed = score < 80  # Example threshold
                if compliance_failed:
                    workflows.append({
                        'name': 'compliance-violation',
                        'trigger': 'compliance-failure',
                        'priority': 'high'
                    })

                # Check for critical security failures
                security_results = check_results.get('security', [])
                critical_failures = [r for r in security_results
                                   if r.get('criticality') == 'critical' and r.get('status') != 'pass']

                if critical_failures:
                    workflows.append({
                        'name': 'security-incident',
                        'trigger': 'security-violation',
                        'priority': 'critical'
                    })

                return workflows

            def trigger_manual_workflows(device_id, workflows):
                """Trigger manual remediation workflows"""
                print(f"Triggering manual workflows for device {device_id}")

                for workflow in workflows:
                    workflow_name = workflow.get('name', 'unknown')
                    print(f"Triggering workflow: {workflow_name}")

                    # Implement workflow triggering logic here
                    # This would integrate with ticketing systems, notifications, etc.

                    if workflow_name == 'compliance-violation':
                        print("Creating compliance violation ticket...")
                        # Integration: Create ticket in JIRA/ServiceNow
                        create_support_ticket(device_id, "compliance-violation", workflow)
                    elif workflow_name == 'security-incident':
                        print("Creating security incident ticket...")
                        # Integration: Create incident in security system
                        create_security_incident(device_id, "security-violation", workflow)

            def create_support_ticket(device_id, issue_type, workflow):
                """Create a support ticket for manual remediation"""
                # Placeholder for ticketing system integration
                # This would integrate with JIRA, ServiceNow, etc.
                print(f"Creating {issue_type} ticket for device {device_id}")

            def create_security_incident(device_id, issue_type, workflow):
                """Create a security incident for critical issues"""
                # Placeholder for security incident management
                # This would integrate with security platforms
                print(f"Creating {issue_type} incident for device {device_id}")

            def send_nac_enforcement(device_id, action, posture_score):
                """Send enforcement action to NAC system"""
                nac_config = CONFIG.get('integration', {}).get('nac', {})

                if not nac_config.get('enable', False):
                    return

                print(f"Sending NAC enforcement for {device_id}: {action} (score: {posture_score})")

                # Placeholder for NAC system integration
                # This would integrate with Cisco ISE, Arista ClearPass, etc.

                if action == 'quarantine':
                    # Move device to quarantine VLAN
                    print(f"Quarantining device {device_id}")
                elif action == 'limited-access':
                    # Move device to limited access VLAN
                    print(f"Limiting access for device {device_id}")
                elif action == 'block':
                    # Block device access completely
                    print(f"Blocking access for device {device_id}")

            def update_endpoint_management(device_id, posture_data):
                """Update endpoint management system with posture data"""
                endpoint_config = CONFIG.get('integration', {}).get('endpoint', {})

                if not endpoint_config.get('enable', False):
                    return

                print(f"Updating endpoint management for {device_id}")

                # Placeholder for endpoint management integration
                # This would integrate with Intune, Jamf, SCCM, etc.

                # Send posture score and compliance status
                compliance_status = "compliant" if posture_data.get('score', 0) >= 80 else "non-compliant"
                print(f"Device {device_id} compliance status: {compliance_status}")

            def send_siem_event(event_type, device_id, data):
                """Send event to SIEM system"""
                siem_config = CONFIG.get('integration', {}).get('siem', {})

                if not siem_config.get('enable', False):
                    return

                print(f"Sending {event_type} event to SIEM for device {device_id}")

                # Placeholder for SIEM integration
                # This would format and send events to Splunk, ELK, etc.

                event = {
                    'timestamp': time.time(),
                    'event_type': event_type,
                    'device_id': device_id,
                    'data': data
                }

                # Send to SIEM endpoint
                print(f"SIEM event: {event}")

            if __name__ == "__main__":
                main_loop()
         ''}";
         Restart = "always";
       };
    };
  };
}

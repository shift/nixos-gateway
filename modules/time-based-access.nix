{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.gateway.timeBasedAccess;

  # Python script to evaluate schedules
  scheduleChecker = pkgs.writeScriptBin "check-schedule" ''
    #!${pkgs.python3}/bin/python3
    import sys
    import json
    import datetime
    import zoneinfo
    import os
    import argparse

    def load_config():
        config_path = os.environ.get('ACCESS_CONFIG', '/etc/gateway/time-access.json')
        try:
            with open(config_path, 'r') as f:
                return json.load(f)
        except Exception as e:
            print(f"Error loading config: {e}", file=sys.stderr)
            sys.exit(1)

    def get_current_time(timezone_name="UTC"):
        # Allow overriding time for testing
        test_time = os.environ.get('TEST_CURRENT_TIME')
        if test_time:
            # Expected format: YYYY-MM-DDTHH:MM:SS
            # We assume the test time is in the target timezone already if no offset provided,
            # or we handle it simply. 
            dt = datetime.datetime.fromisoformat(test_time)
            if dt.tzinfo is None:
                 tz = zoneinfo.ZoneInfo(timezone_name)
                 dt = dt.replace(tzinfo=tz)
            return dt
            
        try:
            tz = zoneinfo.ZoneInfo(timezone_name)
        except Exception:
            tz = zoneinfo.ZoneInfo('UTC')
        return datetime.datetime.now(tz)

    def check_schedule(schedule_config, current_time=None):
        schedule_type = schedule_config.get('type', 'recurring')
        
        # Determine Timezone
        tz_name = 'UTC'
        if schedule_type == 'recurring':
            tz_name = schedule_config.get('pattern', {}).get('timezone', 'UTC')
            
        if current_time is None:
            current_time = get_current_time(tz_name)
        else:
            # Ensure current_time is in the schedule's timezone
            try:
                tz = zoneinfo.ZoneInfo(tz_name)
                current_time = current_time.astimezone(tz)
            except Exception:
                pass

        current_date_str = current_time.strftime('%Y-%m-%d')

        # 1. Check Exceptions (Holidays/Specific Dates)
        # Exceptions in the schedule config (e.g., closed on holidays)
        # We need to know if the exception implies "Closed" (deny) or "Open" (allow).
        # The schema in the prompt implies exceptions are for "closed" dates in a business schedule?
        # "{ date = "2024-12-25"; type = "closed"; }"
        
        exceptions = schedule_config.get('exceptions', [])
        for exc in exceptions:
            if exc.get('date') == current_date_str:
                exc_type = exc.get('type', 'closed')
                if exc_type == 'closed':
                    return False # Explicitly closed
                elif exc_type == 'open':
                    return True # Explicitly open

        # 2. Check Recurring Pattern
        if schedule_type == 'recurring':
            pattern = schedule_config.get('pattern', {})
            
            # Day check
            current_day = current_time.strftime('%A')
            allowed_days = pattern.get('days', [])
            if allowed_days and current_day not in allowed_days:
                return False
                
            # Time check
            current_hm = current_time.strftime('%H:%M')
            time_range = pattern.get('time', {})
            start_time = time_range.get('start', '00:00')
            end_time = time_range.get('end', '23:59')
            
            if not (start_time <= current_hm <= end_time):
                return False
                
            return True

        # 3. Check Scheduled (Specific Dates)
        elif schedule_type == 'scheduled':
            dates = schedule_config.get('dates', [])
            for item in dates:
                if item.get('date') == current_date_str:
                    # Check time if present
                    time_range = item.get('time', {})
                    if not time_range:
                        return True
                        
                    current_hm = current_time.strftime('%H:%M')
                    start_time = time_range.get('start', '00:00')
                    end_time = time_range.get('end', '23:59')
                    
                    if start_time <= current_hm <= end_time:
                        return True
            return False

        return False

    def main():
        parser = argparse.ArgumentParser(description='Check access schedules')
        parser.add_argument('--schedule', help='Check a specific schedule')
        parser.add_argument('--policy', help='Check a specific policy')
        args = parser.parse_args()

        config = load_config()
        schedules = config.get('schedules', {})
        policies = config.get('policies', [])

        if args.schedule:
            if args.schedule not in schedules:
                print(f"Schedule {args.schedule} not found", file=sys.stderr)
                sys.exit(2)
            
            if check_schedule(schedules[args.schedule]):
                print("ALLOWED")
                sys.exit(0)
            else:
                print("DENIED")
                sys.exit(1)

        if args.policy:
            # Find policy
            policy = next((p for p in policies if p['name'] == args.policy), None)
            if not policy:
                print(f"Policy {args.policy} not found", file=sys.stderr)
                sys.exit(2)
            
            schedule_name = policy.get('schedule')
            if not schedule_name or schedule_name not in schedules:
                 # If no schedule, assume deny or handle "24/7" special case if we want
                 if schedule_name == "24/7":
                     print("ALLOWED") # Always allow
                     sys.exit(0)
                 print(f"Schedule {schedule_name} not found for policy", file=sys.stderr)
                 sys.exit(2)

            is_active = check_schedule(schedules[schedule_name])
            action = policy.get('action', 'allow')
            
            if action == 'allow':
                if is_active:
                    print("ALLOWED")
                    sys.exit(0)
                else:
                    print("DENIED")
                    sys.exit(1)
            elif action == 'deny':
                if is_active:
                    print("DENIED")
                    sys.exit(1)
                else:
                    print("ALLOWED")
                    sys.exit(0)

        parser.print_help()
        sys.exit(1)

    if __name__ == '__main__':
        main()
  '';

in
{
  options.services.gateway.timeBasedAccess = {
    enable = mkEnableOption "Time-Based Access Controls";

    schedules = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            type = mkOption {
              type = types.enum [
                "recurring"
                "scheduled"
                "calendar"
              ];
              default = "recurring";
              description = "Type of schedule";
            };

            pattern = mkOption {
              type = types.nullOr (types.submodule {
                options = {
                  days = mkOption {
                    type = types.nullOr (types.listOf types.str);
                    default = null;
                    description = "Days of the week (e.g., Monday)";
                  };
                  time = mkOption {
                    type = types.nullOr (types.submodule {
                      options = {
                        start = mkOption {
                          type = types.str;
                          description = "Start time (HH:MM)";
                        };
                        end = mkOption {
                          type = types.str;
                          description = "End time (HH:MM)";
                        };
                      };
                    });
                    default = null;
                    description = "Time range (HH:MM)";
                  };
                  timezone = mkOption {
                    type = types.str;
                    default = "UTC";
                    description = "Timezone for the schedule";
                  };
                };
              });
              default = null;
              description = "Recurring pattern configuration";
            };

            exceptions = mkOption {
              type = types.listOf (
                types.submodule {
                  options = {
                    date = mkOption {
                      type = types.str;
                      description = "YYYY-MM-DD";
                    };
                    type = mkOption {
                      type = types.enum [
                        "closed"
                        "open"
                        "extended"
                        "modified"
                      ];
                      default = "closed";
                      description = "Exception type";
                    };
                    time = mkOption {
                      type = types.nullOr (types.submodule {
                        options = {
                          start = mkOption {
                            type = types.str;
                            description = "Modified start time";
                          };
                          end = mkOption {
                            type = types.str;
                            description = "Modified end time";
                          };
                        };
                      });
                      default = null;
                      description = "Modified time range";
                    };
                  };
                }
              );
              default = [ ];
              description = "Exceptions to the schedule (holidays, etc)";
            };

            dates = mkOption {
              type = types.listOf (
                types.submodule {
                  options = {
                    date = mkOption {
                      type = types.str;
                      description = "YYYY-MM-DD";
                    };
                    time = mkOption {
                      type = types.nullOr (types.submodule {
                        options = {
                          start = mkOption {
                            type = types.str;
                            description = "Start time (HH:MM)";
                          };
                          end = mkOption {
                            type = types.str;
                            description = "End time (HH:MM)";
                          };
                        };
                      });
                      default = null;
                      description = "Time range for specific date";
                    };
                  };
                }
              );
              default = [ ];
              description = "Specific dates for 'scheduled' type";
            };
          };
        }
      );
      default = {
        businessHours = {
          type = "recurring";
          pattern = {
            days = [ "Monday" "Tuesday" "Wednesday" "Thursday" "Friday" ];
            time = { start = "08:00"; end = "18:00"; };
            timezone = "America/New_York";
          };
          exceptions = [
            { date = "2024-12-25"; type = "closed"; }
            { date = "2024-07-04"; type = "closed"; }
          ];
        };

        afterHours = {
          type = "recurring";
          pattern = {
            days = [ "Monday" "Tuesday" "Wednesday" "Thursday" "Friday" ];
            time = { start = "18:01"; end = "07:59"; };
            timezone = "America/New_York";
          };
        };

        weekends = {
          type = "recurring";
          pattern = {
            days = [ "Saturday" "Sunday" ];
            time = { start = "00:00"; end = "23:59"; };
            timezone = "America/New_York";
          };
        };
      };
      description = "Defined schedules";
    };

    policies = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            name = mkOption {
              type = types.str;
              description = "Policy name";
            };
            subjects = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "Subjects this policy applies to";
            };
            resources = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "Resources this policy controls";
            };
            schedule = mkOption {
              type = types.str;
              description = "Schedule name this policy uses";
            };
            action = mkOption {
              type = types.enum [
                "allow"
                "deny"
                "restrict"
              ];
              default = "allow";
              description = "Action to take during schedule";
            };
            restrictions = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "Additional restrictions when policy is active";
            };
            requirements = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "Additional requirements when policy is active";
            };
            exceptions = mkOption {
              type = types.listOf (
                types.submodule {
                  options = {
                    subjects = mkOption {
                      type = types.listOf types.str;
                      description = "Exception subjects";
                    };
                    schedule = mkOption {
                      type = types.str;
                      description = "Exception schedule";
                    };
                    resources = mkOption {
                      type = types.nullOr (types.listOf types.str);
                      default = null;
                      description = "Exception resources";
                    };
                    action = mkOption {
                      type = types.nullOr (types.enum [ "allow" "deny" "restrict" ]);
                      default = null;
                      description = "Exception action";
                    };
                  };
                }
              );
              default = [ ];
              description = "Policy exceptions";
            };
          };
        }
      );
      default = [
        {
          name = "employee-access";
          subjects = [ "group:employees" ];
          resources = [ "network:lan" "service:internet" ];
          schedule = "businessHours";
          action = "allow";
          exceptions = [
            {
              subjects = [ "group:it-staff" ];
              schedule = "afterHours";
              resources = [ "network:lan" "service:admin" ];
            }
          ];
        }
        {
          name = "guest-access";
          subjects = [ "group:guests" ];
          resources = [ "service:internet" ];
          schedule = "businessHours";
          action = "allow";
          restrictions = [ "bandwidth-limit" "content-filter" ];
        }
        {
          name = "admin-access";
          subjects = [ "group:admins" ];
          resources = [ "*" ];
          schedule = "24/7";
          action = "allow";
          requirements = [ "mfa" "audit-log" ];
        }
      ];
      description = "Access policies linked to schedules";
    };

    enforcement = mkOption {
      type = types.submodule {
        options = {
          network = mkOption {
            type = types.submodule {
              options = {
                enable = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Enable network-level enforcement";
                };

                methods = mkOption {
                  type = types.listOf (types.enum [ "firewall-rules" "vlan-isolation" "acl" ]);
                  default = [ "firewall-rules" ];
                  description = "Network enforcement methods";
                };

                firewall = mkOption {
                  type = types.submodule {
                    options = {
                      chain = mkOption {
                        type = types.str;
                        default = "TIME_BASED";
                        description = "Firewall chain name";
                      };

                      priority = mkOption {
                        type = types.int;
                        default = 100;
                        description = "Firewall rule priority";
                      };

                      defaultAction = mkOption {
                        type = types.enum [ "allow" "deny" ];
                        default = "deny";
                        description = "Default action for unmatched traffic";
                      };
                    };
                  };
                  default = { };
                  description = "Firewall enforcement configuration";
                };
              };
            };
            default = { };
            description = "Network-level enforcement";
          };

          application = mkOption {
            type = types.submodule {
              options = {
                enable = mkOption {
                  type = types.bool;
                  default = false;
                  description = "Enable application-level enforcement";
                };

                methods = mkOption {
                  type = types.listOf (types.enum [ "reverse-proxy" "application-gateway" ]);
                  default = [ "reverse-proxy" ];
                  description = "Application enforcement methods";
                };
              };
            };
            default = { };
            description = "Application-level enforcement";
          };

          vpn = mkOption {
            type = types.submodule {
              options = {
                enable = mkOption {
                  type = types.bool;
                  default = false;
                  description = "Enable VPN enforcement";
                };

                timeout = mkOption {
                  type = types.attrsOf types.str;
                  default = {
                    businessHours = "8h";
                    afterHours = "2h";
                    weekends = "4h";
                  };
                  description = "VPN session timeouts by schedule";
                };
              };
            };
            default = { };
            description = "VPN enforcement";
          };
        };
      };
      default = { };
      description = "Policy enforcement configuration";
    };

    exceptions = mkOption {
      type = types.submodule {
        options = {
          emergency = mkOption {
            type = types.submodule {
              options = {
                enable = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Enable emergency overrides";
                };

                approvers = mkOption {
                  type = types.listOf types.str;
                  default = [ "security-team" "management" ];
                  description = "Emergency override approvers";
                };

                duration = mkOption {
                  type = types.str;
                  default = "24h";
                  description = "Maximum emergency override duration";
                };

                audit = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Audit emergency overrides";
                };
              };
            };
            default = { };
            description = "Emergency override configuration";
          };

          temporary = mkOption {
            type = types.submodule {
              options = {
                enable = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Enable temporary access grants";
                };

                maxDuration = mkOption {
                  type = types.str;
                  default = "7d";
                  description = "Maximum temporary access duration";
                };

                autoExpiration = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Automatically expire temporary access";
                };

                notification = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Send expiration notifications";
                };
              };
            };
            default = { };
            description = "Temporary access configuration";
          };
        };
      };
      default = { };
      description = "Exception handling configuration";
    };

    monitoring = mkOption {
      type = types.submodule {
        options = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Enable time-based access monitoring";
          };

          logging = mkOption {
            type = types.submodule {
              options = {
                accessAttempts = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Log access attempts";
                };

                policyViolations = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Log policy violations";
                };

                scheduleChanges = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Log schedule changes";
                };

                exceptionGrants = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Log exception grants";
                };
              };
            };
            default = { };
            description = "Logging configuration";
          };

          alerts = mkOption {
            type = types.attrsOf (
              types.submodule {
                options = {
                  severity = mkOption {
                    type = types.enum [ "info" "warning" "error" "critical" ];
                    default = "warning";
                    description = "Alert severity";
                  };
                };
              }
            );
            default = {
              policyViolation = { severity = "warning"; };
              emergencyOverride = { severity = "high"; };
              unusualAccess = { severity = "medium"; };
              scheduleConflict = { severity = "low"; };
            };
            description = "Alert configuration";
          };
        };
      };
      default = { };
      description = "Monitoring configuration";
    };
  };

  config = mkIf cfg.enable {
    # Export config to a JSON file
    environment.etc."gateway/time-access.json".source = pkgs.writeText "time-access.json" (
      builtins.toJSON {
        schedules = cfg.schedules;
        policies = cfg.policies;
        enforcement = cfg.enforcement;
        exceptions = cfg.exceptions;
        monitoring = cfg.monitoring;
      }
    );

    environment.systemPackages = [ scheduleChecker ];

    # Time-based access control service
    systemd.services.gateway-time-based-access = {
      description = "Gateway time-based access control service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.python3}/bin/python3 ${pkgs.writeText "time-access.py" ''
          import time
          import json
          import os
          import subprocess
          from datetime import datetime, timezone, timedelta

          # Configuration injected via Nix
          CONFIG_FILE = "${pkgs.writeText "time-access-config.json" (builtins.toJSON cfg)}"
          with open(CONFIG_FILE, 'r') as f:
              CONFIG = json.load(f)

          # State files
          POLICY_STATE_FILE = "/run/gateway/time-access-policies.json"
          LOG_FILE = "/var/log/gateway/time-access.log"

          def log(message):
              timestamp = datetime.now().isoformat()
              with open(LOG_FILE, 'a') as f:
                  f.write(f"[{timestamp}] {message}\n")
              print(message)

          def get_current_time_info():
              """Get current time information"""
              now = datetime.now()
              return {
                  'year': now.year,
                  'month': now.month,
                  'day': now.day,
                  'hour': now.hour,
                  'minute': now.minute,
                  'second': now.second,
                  'day_of_week': now.strftime('%A'),
                  'timestamp': now.timestamp()
              }

          def is_in_schedule(schedule_name, current_time):
              """Check if current time is within the specified schedule"""
              if schedule_name not in CONFIG.get('schedules', {}):
                  return False

              schedule = CONFIG['schedules'][schedule_name]

              # Handle special "24/7" schedule
              if schedule_name == "24/7":
                  return True

              if schedule['type'] == 'recurring':
                  pattern = schedule.get('pattern')
                  if not pattern:
                      return False

                  # Check day of week
                  schedule_days = pattern.get('days', [])
                  if schedule_days and current_time['day_of_week'] not in schedule_days:
                      return False

                  # Check time range
                  time_range = pattern.get('time')
                  if not time_range:
                      return True  # No time restriction

                  start_time = time_range['start']
                  end_time = time_range['end']

                  current_minutes = current_time['hour'] * 60 + current_time['minute']
                  start_minutes = int(start_time.split(':')[0]) * 60 + int(start_time.split(':')[1])
                  end_minutes = int(end_time.split(':')[0]) * 60 + int(end_time.split(':')[1])

                  if start_minutes <= end_minutes:
                      return start_minutes <= current_minutes <= end_minutes
                  else:
                      # Handle overnight schedules
                      return current_minutes >= start_minutes or current_minutes <= end_minutes

              elif schedule['type'] == 'scheduled':
                  # Check specific dates
                  current_date = f"{current_time['year']}-{current_time['month']:02d}-{current_time['day']:02d}"
                  for date_entry in schedule.get('dates', []):
                      if date_entry['date'] == current_date:
                          time_range = date_entry.get('time')
                          if not time_range:
                              return True

                          start_time = time_range['start']
                          end_time = time_range['end']

                          current_minutes = current_time['hour'] * 60 + current_time['minute']
                          start_minutes = int(start_time.split(':')[0]) * 60 + int(start_time.split(':')[1])
                          end_minutes = int(end_time.split(':')[0]) * 60 + int(end_time.split(':')[1])

                          if start_minutes <= end_minutes:
                              return start_minutes <= current_minutes <= end_minutes
                          else:
                              return current_minutes >= start_minutes or current_minutes <= end_minutes

                  return False

              return False

          def evaluate_policies():
              """Evaluate all policies and return current access state"""
              current_time = get_current_time_info()
              access_state = {}

              for policy in CONFIG.get('policies', []):
                  policy_name = policy['name']
                  schedule_name = policy['schedule']

                  in_schedule = is_in_schedule(schedule_name, current_time)
                  action = policy['action'] if in_schedule else 'deny'

                  # Check exceptions
                  for exception in policy.get('exceptions', []):
                      if any(subject in policy['subjects'] for subject in exception.get('subjects', [])):
                          exception_schedule = exception.get('schedule')
                          if exception_schedule and is_in_schedule(exception_schedule, current_time):
                              action = exception.get('action', action)

                  access_state[policy_name] = {
                      'in_schedule': in_schedule,
                      'action': action,
                      'subjects': policy['subjects'],
                      'resources': policy['resources'],
                      'restrictions': policy.get('restrictions', []),
                      'requirements': policy.get('requirements', [])
                  }

              return access_state

          def update_firewall_rules(access_state):
              """Update firewall rules based on current access state"""
              enforcement = CONFIG.get('enforcement', {}).get('network', {})
              if not enforcement.get('enable', False):
                  return

              methods = enforcement.get('methods', ['firewall-rules'])
              firewall_config = enforcement.get('firewall', {})
              chain_name = firewall_config.get('chain', 'TIME_BASED')

              if 'firewall-rules' in methods:
                  update_iptables_rules(access_state, chain_name)

              if 'vlan-isolation' in methods:
                  update_vlan_isolation(access_state)

              if 'acl' in methods:
                  update_acl_rules(access_state)

          def update_iptables_rules(access_state, chain_name):
              """Update iptables rules for time-based access control"""
              try:
                  # Create chain if it doesn't exist
                  subprocess.run(['iptables', '-N', chain_name], check=False, capture_output=True)

                  # Clear existing rules
                  subprocess.run(['iptables', '-F', chain_name], check=False, capture_output=True)

                  # Add rules based on policies
                  for policy_name, policy_state in access_state.items():
                      subjects = policy_state.get('subjects', [])
                      resources = policy_state.get('resources', [])
                      action = policy_state.get('action', 'deny')
                      restrictions = policy_state.get('restrictions', [])

                      # Convert action to iptables action
                      iptables_action = '-j ACCEPT' if action == 'allow' else '-j DROP'

                      # Add rules for each subject-resource combination
                      for subject in subjects:
                          for resource in resources:
                              # Parse subject (e.g., "group:employees" -> group employees)
                              if ':' in subject:
                                  subject_type, subject_value = subject.split(':', 1)
                              else:
                                  subject_type, subject_value = 'ip', subject

                              # Parse resource (e.g., "network:lan" -> network lan)
                              if ':' in resource:
                                  resource_type, resource_value = resource.split(':', 1)
                              else:
                                  resource_type, resource_value = 'ip', resource

                              # Build iptables rule
                              rule_parts = ['iptables', '-A', chain_name]

                              # Add subject matching
                              if subject_type == 'ip':
                                  rule_parts.extend(['-s', subject_value])
                              elif subject_type == 'group':
                                  # For groups, we'd need integration with user/group databases
                                  # This is a simplified placeholder
                                  log(f"Group-based rules not fully implemented for {subject}")
                                  continue

                              # Add resource matching
                              if resource_type == 'network':
                                  if resource_value == 'lan':
                                      rule_parts.extend(['-d', '192.168.1.0/24'])  # Example subnet
                                  elif resource_value == 'internet':
                                      rule_parts.extend(['! -d', '192.168.0.0/16'])  # Not local networks
                              elif resource_type == 'service':
                                  if resource_value == 'internet':
                                      rule_parts.extend(['-p', 'tcp', '--dport', '80,443'])
                                  elif resource_value == 'admin':
                                      rule_parts.extend(['-p', 'tcp', '--dport', '22,443'])

                              # Add restrictions
                              for restriction in restrictions:
                                  if restriction == 'bandwidth-limit':
                                      # Bandwidth limiting would require tc or similar
                                      log(f"Bandwidth limiting not implemented for {policy_name}")
                                  elif restriction == 'content-filter':
                                      # Content filtering would require squid or similar
                                      log(f"Content filtering not implemented for {policy_name}")

                              # Add the action
                              rule_parts.append(iptables_action)

                              # Execute the rule
                              try:
                                  subprocess.run(rule_parts, check=True, capture_output=True)
                                  log(f"Added iptables rule for {policy_name}: {' '.join(rule_parts[3:])}")
                              except subprocess.CalledProcessError as e:
                                  log(f"Failed to add iptables rule for {policy_name}: {e}")

                  # Add default policy
                  default_action = firewall_config.get('defaultAction', 'deny')
                  if default_action == 'deny':
                      subprocess.run(['iptables', '-A', chain_name, '-j', 'DROP'], check=False, capture_output=True)
                  else:
                      subprocess.run(['iptables', '-A', chain_name, '-j', 'ACCEPT'], check=False, capture_output=True)

              except Exception as e:
                  log(f"Error updating iptables rules: {e}")

          def update_vlan_isolation(access_state):
              """Update VLAN isolation settings"""
              # Placeholder for VLAN isolation
              # This would integrate with switch management APIs
              log("VLAN isolation updates not implemented")

          def update_acl_rules(access_state):
              """Update Access Control List rules"""
              # Placeholder for ACL updates
              # This would integrate with network device management
              log("ACL rule updates not implemented")

          def check_emergency_overrides():
              """Check for active emergency overrides"""
              exceptions = CONFIG.get('exceptions', {}).get('emergency', {})
              if not exceptions.get('enable', False):
                  return False

              # Check for active emergency override files
              override_file = "/run/gateway/emergency-override.json"
              if os.path.exists(override_file):
                  try:
                      with open(override_file, 'r') as f:
                          override_data = json.load(f)

                      # Check if override is still valid
                      granted_at = override_data.get('granted_at', 0)
                      duration_str = exceptions.get('duration', '24h')

                      # Parse duration
                      duration_seconds = parse_duration(duration_str)
                      expires_at = granted_at + duration_seconds

                      if time.time() < expires_at:
                          approvers = override_data.get('approvers', [])
                          required_approvers = exceptions.get('approvers', [])

                          # Check if all required approvers have approved
                          if all(approver in approvers for approver in required_approvers):
                              log(f"Emergency override active until {datetime.fromtimestamp(expires_at).isoformat()}")
                              return True
                          else:
                              log("Emergency override missing required approvals")
                      else:
                          log("Emergency override expired")
                          os.remove(override_file)
                  except Exception as e:
                      log(f"Error checking emergency override: {e}")

              return False

          def process_temporary_access():
              """Process temporary access grants"""
              exceptions = CONFIG.get('exceptions', {}).get('temporary', {})
              if not exceptions.get('enable', False):
                  return

              temp_access_file = "/run/gateway/temporary-access.json"
              if os.path.exists(temp_access_file):
                  try:
                      with open(temp_access_file, 'r') as f:
                          temp_access = json.load(f)

                      current_time = time.time()
                      expired_grants = []

                      for grant_id, grant in temp_access.items():
                          expires_at = grant.get('expires_at', 0)

                          if current_time > expires_at:
                              # Grant expired
                              expired_grants.append(grant_id)
                              log(f"Temporary access grant {grant_id} expired")

                              # Send notification if enabled
                              if exceptions.get('notification', False):
                                  notify_access_expiry(grant)
                          else:
                              # Grant still active - apply it
                              apply_temporary_access(grant)

                      # Remove expired grants
                      for grant_id in expired_grants:
                          del temp_access[grant_id]

                      # Save updated grants
                      with open(temp_access_file, 'w') as f:
                          json.dump(temp_access, f, indent=2)

                  except Exception as e:
                      log(f"Error processing temporary access: {e}")

          def parse_duration(duration_str):
              """Parse duration string to seconds"""
              import re
              match = re.match(r'(\d+)([smhd])', duration_str)
              if not match:
                  return 3600  # Default 1 hour

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

          def apply_temporary_access(grant):
              """Apply a temporary access grant"""
              # This would modify the current access state to include temporary permissions
              log(f"Applying temporary access grant: {grant.get('id', 'unknown')}")

          def notify_access_expiry(grant):
              """Send notification for expired access"""
              # This would integrate with notification systems
              log(f"Sending expiry notification for grant: {grant.get('id', 'unknown')}")

          def request_emergency_override(reason, requester):
              """Request an emergency override"""
              exceptions = CONFIG.get('exceptions', {}).get('emergency', {})
              if not exceptions.get('enable', False):
                  return False

              override_request = {
                  'reason': reason,
                  'requester': requester,
                  'requested_at': time.time(),
                  'approvers': [],
                  'status': 'pending'
              }

              # Save request for approval
              request_file = f"/run/gateway/emergency-request-{int(time.time())}.json"
              with open(request_file, 'w') as f:
                  json.dump(override_request, f, indent=2)

              log(f"Emergency override requested by {requester}: {reason}")
              return True

          def grant_temporary_access(subject, resources, duration, reason):
              """Grant temporary access"""
              exceptions = CONFIG.get('exceptions', {}).get('temporary', {})
              if not exceptions.get('enable', False):
                  return False

              max_duration = parse_duration(exceptions.get('maxDuration', '7d'))
              requested_duration = parse_duration(duration)

              if requested_duration > max_duration:
                  log(f"Requested duration {duration} exceeds maximum {exceptions['maxDuration']}")
                  return False

              grant = {
                  'id': f"temp-{int(time.time())}",
                  'subject': subject,
                  'resources': resources,
                  'granted_at': time.time(),
                  'expires_at': time.time() + requested_duration,
                  'reason': reason,
                  'auto_expiration': exceptions.get('autoExpiration', True)
              }

              # Save grant
              temp_access_file = "/run/gateway/temporary-access.json"
              try:
                  if os.path.exists(temp_access_file):
                      with open(temp_access_file, 'r') as f:
                          temp_access = json.load(f)
                  else:
                      temp_access = {}

                  temp_access[grant['id']] = grant

                  with open(temp_access_file, 'w') as f:
                      json.dump(temp_access, f, indent=2)

                  log(f"Temporary access granted to {subject} for {duration}: {reason}")
                  return True
              except Exception as e:
                  log(f"Error granting temporary access: {e}")
                  return False

          def send_alerts(access_state):
              """Send alerts for policy violations and unusual activity"""
              monitoring = CONFIG.get('monitoring', {})
              if not monitoring.get('enable', False):
                  return

              alerts = monitoring.get('alerts', {})

              for policy_name, policy_state in access_state.items():
                  if policy_state['action'] == 'deny':
                      # Log policy violation
                      log(f"Policy violation: {policy_name} denied access")

                      # Send alert if configured
                      if 'policyViolation' in alerts:
                          severity = alerts['policyViolation']['severity']
                          log(f"ALERT [{severity}]: Policy violation in {policy_name}")

              # Check for unusual access patterns
              check_unusual_activity(access_state)

          def check_unusual_activity(access_state):
              """Check for unusual access patterns"""
              # This would analyze access patterns for anomalies
              # Placeholder implementation
              pass

          def log_access_attempt(subject, resource, action, policy_name):
              """Log access attempts for compliance"""
              logging = CONFIG.get('monitoring', {}).get('logging', {})
              if not logging.get('accessAttempts', True):
                  return

              log_entry = {
                  'timestamp': time.time(),
                  'subject': subject,
                  'resource': resource,
                  'action': action,
                  'policy': policy_name,
                  'result': 'allowed' if action in ['allow', 'restrict'] else 'denied'
              }

              # Write to access log
              access_log_file = "/var/log/gateway/time-access.log"
              try:
                  with open(access_log_file, 'a') as f:
                      f.write(json.dumps(log_entry) + '\n')
              except Exception as e:
                  log(f"Error writing access log: {e}")

          def generate_compliance_report():
              """Generate compliance reports"""
              # This would generate periodic compliance reports
              # Placeholder implementation
              pass

          def audit_schedule_changes():
              """Audit changes to schedules and policies"""
              # This would track changes to time-based access configurations
              # Placeholder implementation
              pass

          def check_schedule_conflicts():
              """Check for conflicting schedules"""
              schedules = CONFIG.get('schedules', {})
              conflicts = []

              # Check for overlapping schedules
              # This is a simplified check
              for name1, sched1 in schedules.items():
                  for name2, sched2 in schedules.items():
                      if name1 != name2 and sched1.get('type') == 'recurring' and sched2.get('type') == 'recurring':
                          # Check if they have overlapping days and times
                          days1 = set(sched1.get('pattern', {}).get('days', []))
                          days2 = set(sched2.get('pattern', {}).get('days', []))
                          if days1 & days2:  # Overlapping days
                              time1 = sched1.get('pattern', {}).get('time', {})
                              time2 = sched2.get('pattern', {}).get('time', {})
                              if time1 and time2:
                                  # Simple overlap check
                                  start1 = time1.get('start', '00:00')
                                  end1 = time1.get('end', '23:59')
                                  start2 = time2.get('start', '00:00')
                                  end2 = time2.get('end', '23:59')

                                  if not (end1 <= start2 or end2 <= start1):
                                      conflicts.append(f"Schedule conflict between {name1} and {name2}")

              if conflicts:
                  for conflict in conflicts:
                      log(f"SCHEDULE CONFLICT: {conflict}")

                  # Send alert if configured
                  alerts = CONFIG.get('monitoring', {}).get('alerts', {})
                  if 'scheduleConflict' in alerts:
                      severity = alerts['scheduleConflict']['severity']
                      log(f"ALERT [{severity}]: Schedule conflicts detected")

              return conflicts

          def main_loop():
              log("Starting Time-Based Access Control service...")

              os.makedirs(os.path.dirname(POLICY_STATE_FILE), exist_ok=True)
              os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)

              while True:
                  try:
                      # Check for emergency overrides
                      if check_emergency_overrides():
                          log("Emergency override active - allowing all access")
                          time.sleep(60)
                          continue

                      # Process temporary access
                      process_temporary_access()

                      # Evaluate current policies
                      access_state = evaluate_policies()

                      # Update enforcement (firewall rules, etc.)
                      update_firewall_rules(access_state)

                      # Send alerts for violations
                      send_alerts(access_state)

                      # Check for schedule conflicts
                      check_schedule_conflicts()

                      # Generate compliance reports (daily)
                      current_time = get_current_time_info()
                      if current_time['hour'] == 6 and current_time['minute'] == 0:  # 6 AM daily
                          generate_compliance_report()

                      # Audit configuration changes
                      audit_schedule_changes()

                      # Save current state
                      with open(POLICY_STATE_FILE, 'w') as f:
                          json.dump({
                              'timestamp': time.time(),
                              'access_state': access_state
                          }, f, indent=2)

                      log(f"Updated access policies - {len(access_state)} policies evaluated")

                  except Exception as e:
                      log(f"Error in main loop: {e}")
                      import traceback
                      traceback.print_exc()

                  time.sleep(60)  # Check every minute

          if __name__ == "__main__":
              main_loop()
        ''}";
        User = "root";
        Group = "root";
        PrivateTmp = true;
        ProtectSystem = "strict";
        ReadWritePaths = [
          "/run/gateway"
          "/var/log/gateway"
        ];
      };
    };

    # Timer for periodic policy updates
    systemd.timers.gateway-time-based-access = {
      description = "Timer for time-based access control updates";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* *:*:00";  # Every minute
        Persistent = true;
      };
    };

    # Ensure required directories exist
    systemd.tmpfiles.rules = [
      "d /run/gateway 0755 root root - -"
      "d /var/log/gateway 0755 root root - -"
    ];
  };
}

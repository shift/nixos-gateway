{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.gateway.policyRouting;
  policyLib = import ../lib/policy-routing.nix { inherit lib; };

  inherit (lib)
    mkOption
    types
    optionalAttrs
    concatStringsSep
    mapAttrsToList
    filterAttrs
    mapAttrs
    ;

  # Collect all unique priorities from enabled rules for state management
  allRules = lib.flatten (mapAttrsToList (_: policy: policy.rules or [ ]) cfg.policies);
  enabledRules = builtins.filter (rule: rule.enabled) allRules;
  uniquePriorities = lib.unique (map (rule: rule.action.priority) enabledRules);

  # Validate policy routing configuration
  policyValidation = policyLib.generatePolicyConfig cfg;

  # Generate routing table definitions
  rtTablesConfig = mapAttrsToList (name: table: ''
    if ! grep -q "^${toString table.priority} ${name}$" /etc/iproute2/rt_tables 2>/dev/null; then
      echo "${toString table.priority} ${name}" >> /etc/iproute2/rt_tables
    fi
  '') cfg.routingTables;

  # Generate nftables marking rules for complex policies
  nftablesRules = lib.flatten (
    mapAttrsToList (
      policyName: policy:
      lib.imap0 (
        index: rule:
        let
          nftRule = policyLib.generateNftablesRule rule index;
        in
        if nftRule != null then
          [
            ''
              # Policy rule: ${rule.name}
              ${nftRule}
            ''
          ]
        else
          [ ]
      ) (policy.rules or [ ])
    ) cfg.policies
  );

  # Generate route configuration
  routeConfigs = mapAttrsToList (name: table: ''
    # Flush table ${name} to ensure clean state
    ip route flush table ${name} || true

    # Add routes to table ${name}
    ${lib.concatMapStringsSep "\n" (route: ''
      ip route replace ${route} table ${name}
    '') table.routes}

    ${lib.optionalString (table.defaultRoute != null) ''
      # Default route for table ${name}
      ip route replace default via ${table.defaultRoute} table ${name}
    ''}
  '') cfg.routingTables;

  # Generate policy rules
  policyRuleConfigs = lib.flatten (
    mapAttrsToList (
      policyName: policy:
      lib.imap0 (
        index: rule:
        let
          ruleCommands = policyLib.generateIpRule rule index;
        in
        ''
          # Policy rule: ${rule.name} (${rule.description})
          ${lib.optionalString rule.enabled (
            lib.concatMapStringsSep "\n" (cmd: ''
              ip rule add ${cmd}
            '') ruleCommands
          )}
        ''
      ) (policy.rules or [ ])
    ) cfg.policies
  );

  # Generate multipath routes
  multipathConfigs = lib.flatten (
    mapAttrsToList (
      policyName: policy:
      map (rule: ''
        ${lib.optionalString (rule.enabled && rule.action.action == "multipath") ''
          # Multipath route for ${rule.name}
          ip route replace default ${
            policyLib.generateMultipathRoute rule.action.tables rule.action.weights (
              lib.listToAttrs (
                map (tableName: {
                  name = tableName;
                  value = cfg.routingTables.${tableName}.defaultRoute;
                }) rule.action.tables
              )
            )
          }
        ''}
      '') (policy.rules or [ ])
    ) cfg.policies
  );

  # Generate monitoring configuration
  monitoringConfig = lib.optionalString cfg.monitoring.enable ''
    # Policy routing monitoring
    cat > /etc/prometheus/policy-routing.rules << 'EOF'
    # Policy routing metrics
    policy_routing_rules_total ${
      toString (lib.length (lib.flatten (mapAttrsToList (_: p: p.rules or [ ]) cfg.policies)))
    }
    policy_routing_tables_total ${toString (lib.length (lib.attrNames cfg.routingTables))}

    ${lib.concatMapStringsSep "\n" (tableName: ''
      policy_routing_table_info{table="${tableName}",name="${cfg.routingTables.${tableName}.name}"} 1
    '') (lib.attrNames cfg.routingTables)}
    EOF
  '';

  # Generate policy routing setup script
  setupScript = pkgs.writeShellScript "policy-routing-setup" ''
    set -euo pipefail

    echo "Setting up policy-based routing..."

    # Create iproute2 table definitions
    mkdir -p /etc/iproute2
    # Check if the tables already exist to avoid "File exists" error or partial state
    # We'll just append missing ones or recreate from scratch if we want full control
    # For now, let's just make sure we don't fail if they exist
    touch /etc/iproute2/rt_tables || true

    ${lib.concatStringsSep "\n" rtTablesConfig}

    # Clean up prior to adding new rules to ensure idempotency.
    # We flush rules by priority to ensure a clean slate for the priorities we manage,
    # without blowing away system default rules (prio 0, 32766, 32767).
    # Note: 'ip rule del priority X' deletes ALL rules with that priority.
    ${lib.concatMapStringsSep "\n" (prio: ''
      while ip rule show priority ${toString prio} >/dev/null 2>&1; do
        ip rule del priority ${toString prio} 2>/dev/null || break
      done
    '') uniquePriorities}

    # Apply policy rules
    ${lib.concatStringsSep "\n" policyRuleConfigs}

    # Add routes
    ${lib.concatStringsSep "\n" routeConfigs}

    # Setup multipath routes
    ${lib.concatStringsSep "\n" multipathConfigs}

    # Enable IP forwarding if not already enabled
    sysctl -w net.ipv4.ip_forward=1 || true
    sysctl -w net.ipv6.conf.all.forwarding=1 || true

    # Enable Proxy ARP on internal interfaces if configured
    # This helps when clients have routes that might need to be proxied
    ${lib.optionalString (cfg.enableProxyArp or false) ''
      for iface in ${lib.concatStringsSep " " (cfg.internalInterfaces or [ ])}; do
        if [ -d "/proc/sys/net/ipv4/conf/$iface" ]; then
          sysctl -w net.ipv4.conf.$iface.proxy_arp=1 || true
        fi
      done
    ''}

    echo "Policy-based routing setup completed"

  '';

  # Generate policy routing cleanup script
  cleanupScript = pkgs.writeShellScript "policy-routing-cleanup" ''
    set -euo pipefail

    echo "Cleaning up policy-based routing..."

    # Flush all policy rules
    ip rule flush || true

    # Flush custom routing tables
    ${lib.concatMapStringsSep "\n" (tableName: ''
      ip route flush table ${tableName} || true
    '') (lib.attrNames cfg.routingTables)}

    # Remove custom table definitions
    if [ -f /etc/iproute2/rt_tables ]; then
      grep -v "^#" /etc/iproute2/rt_tables | awk '$2 ~ /^[0-9]+$/ {print $2}' | while read table; do
        sed -i "/^[0-9]\\+[[:space:]]\\+$table[[:space:]]*$/d" /etc/iproute2/rt_tables || true
      done
    fi

    echo "Policy-based routing cleanup completed"
  '';

  # Generate policy routing status script
  statusScript = pkgs.writeScriptBin "policy-routing-status" ''
    #!${pkgs.runtimeShell}
    set -euo pipefail

    echo "=== Policy Routing Status ==="
    echo

    echo "Routing Tables:"
    cat /etc/iproute2/rt_tables 2>/dev/null || echo "No custom routing tables defined"
    echo

    echo "Policy Rules:"
    ip rule list || echo "No policy rules defined"
    echo

    echo "Custom Table Routes:"
    ${lib.concatMapStringsSep "\n" (tableName: ''
      echo "--- Table ${tableName} (${cfg.routingTables.${tableName}.name}) ---"
      ip route show table ${tableName} 2>/dev/null || echo "No routes in table ${tableName}"
      echo
    '') (lib.attrNames cfg.routingTables)}

    ${lib.optionalString cfg.monitoring.enable ''
      echo "=== Monitoring Metrics ==="
      if [ -f /etc/prometheus/policy-routing.rules ]; then
        cat /etc/prometheus/policy-routing.rules
      else
        echo "No monitoring metrics available"
      fi
      echo
    ''}
  '';

in
{
  options.services.gateway.policyRouting = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable policy-based routing";
    };

    routingTables = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Human-readable table name";
            };

            priority = lib.mkOption {
              type = lib.types.int;
              default = 100;
              description = "Table priority for ordering";
            };

            routes = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Routes in this table";
            };

            defaultRoute = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Default route gateway for this table";
            };
          };
        }
      );
      default = { };
      description = "Routing tables configuration";
      example = {
        table100 = {
          name = "ISP1";
          priority = 100;
          defaultRoute = "192.168.100.1";
        };
        table200 = {
          name = "ISP2";
          priority = 200;
          defaultRoute = "192.168.200.1";
        };
      };
    };

    policies = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            priority = lib.mkOption {
              type = lib.types.int;
              default = 1000;
              description = "Policy priority (lower = higher priority)";
            };

            rules = lib.mkOption {
              type = lib.types.listOf (
                lib.types.submodule {
                  options = {
                    name = lib.mkOption {
                      type = lib.types.str;
                      description = "Policy rule name";
                    };

                    description = lib.mkOption {
                      type = lib.types.str;
                      default = "";
                      description = "Policy rule description";
                    };

                    enabled = lib.mkOption {
                      type = lib.types.bool;
                      default = true;
                      description = "Whether this policy rule is enabled";
                    };

                    priority = lib.mkOption {
                      type = lib.types.int;
                      default = 1000;
                      description = "Policy priority (lower = higher priority)";
                    };

                    match = lib.mkOption {
                      type = lib.types.submodule {
                        options = {
                          time = lib.mkOption {
                            type = lib.types.nullOr (
                              lib.types.submodule {
                                options = {
                                  start = lib.mkOption {
                                    type = lib.types.str;
                                    description = "Start time (HH:MM:SS)";
                                    example = "08:00:00";
                                  };
                                  end = lib.mkOption {
                                    type = lib.types.str;
                                    description = "End time (HH:MM:SS)";
                                    example = "17:00:00";
                                  };
                                  days = lib.mkOption {
                                    type = lib.types.nullOr (lib.types.listOf lib.types.str);
                                    default = null;
                                    description = "Days of week (Mon,Tue,Wed,Thu,Fri,Sat,Sun)";
                                    example = [
                                      "Mon"
                                      "Fri"
                                    ];
                                  };
                                };
                              }
                            );
                            default = null;
                            description = "Time-based matching (requires nftables)";
                          };

                          sourceAddress = lib.mkOption {
                            type = lib.types.nullOr lib.types.str;
                            default = null;
                            description = "Source address or network (CIDR notation)";
                          };

                          destinationAddress = lib.mkOption {
                            type = lib.types.nullOr lib.types.str;
                            default = null;
                            description = "Destination address or network (CIDR notation)";
                          };

                          protocol = lib.mkOption {
                            type = lib.types.nullOr (
                              lib.types.enum [
                                "tcp"
                                "udp"
                                "icmp"
                                "all"
                              ]
                            );
                            default = null;
                            description = "IP protocol";
                          };

                          sourcePort = lib.mkOption {
                            type = lib.types.nullOr (lib.types.either lib.types.int (lib.types.listOf lib.types.int));
                            default = null;
                            description = "Source port or list of ports";
                          };

                          destinationPort = lib.mkOption {
                            type = lib.types.nullOr (lib.types.either lib.types.int (lib.types.listOf lib.types.int));
                            default = null;
                            description = "Destination port or list of ports";
                          };

                          inputInterface = lib.mkOption {
                            type = lib.types.nullOr lib.types.str;
                            default = null;
                            description = "Input interface name";
                          };

                          outputInterface = lib.mkOption {
                            type = lib.types.nullOr lib.types.str;
                            default = null;
                            description = "Output interface name";
                          };

                          fwmark = lib.mkOption {
                            type = lib.types.nullOr lib.types.int;
                            default = null;
                            description = "Firewall mark value";
                          };

                          dscp = lib.mkOption {
                            type = lib.types.nullOr lib.types.int;
                            default = null;
                            description = "DSCP value (0-63)";
                          };

                          tos = lib.mkOption {
                            type = lib.types.nullOr lib.types.int;
                            default = null;
                            description = "Type of Service value";
                          };
                        };
                      };
                      description = "Match criteria for this policy";
                    };

                    action = lib.mkOption {
                      type = lib.types.submodule {
                        options = {
                          action = lib.mkOption {
                            type = lib.types.enum [
                              "route"
                              "multipath"
                              "blackhole"
                              "prohibit"
                              "unreachable"
                            ];
                            description = "Action to take when rule matches";
                          };

                          table = lib.mkOption {
                            type = lib.types.nullOr lib.types.str;
                            default = null;
                            description = "Routing table name (for route action)";
                          };

                          tables = lib.mkOption {
                            type = lib.types.listOf lib.types.str;
                            default = [ ];
                            description = "List of routing tables (for multipath action)";
                          };

                          weights = lib.mkOption {
                            type = lib.types.attrsOf lib.types.int;
                            default = { };
                            description = "Weight for each table in multipath (table -> weight)";
                          };

                          priority = lib.mkOption {
                            type = lib.types.int;
                            default = 1000;
                            description = "Rule priority (lower = higher priority)";
                          };
                        };
                      };
                      description = "Action to take when rule matches";
                    };
                  };
                }
              );
              default = [ ];
              description = "Policy rules";
            };
          };
        }
      );
      default = { };
      description = "Policy rules configuration";
      example = {
        "voip-traffic" = {
          priority = 1000;
          rules = [
            {
              name = "sip-protocol";
              description = "Route SIP traffic via ISP1";
              enabled = true;
              priority = 1000;
              match = {
                protocol = "udp";
                destinationPort = 5060;
              };
              action = {
                action = "route";
                table = "table100";
                priority = 1000;
              };
            }
          ];
        };
        "load-balance" = {
          priority = 2000;
          rules = [
            {
              name = "web-traffic";
              description = "Load balance web traffic";
              enabled = true;
              priority = 2000;
              match = {
                protocol = "tcp";
                destinationPort = [
                  80
                  443
                ];
              };
              action = {
                action = "multipath";
                tables = [
                  "table100"
                  "table200"
                ];
                weights = {
                  table100 = 70;
                  table200 = 30;
                };
                priority = 2000;
              };
            }
          ];
        };
      };
    };

    monitoring = lib.mkOption {
      type = lib.types.submodule {
        options = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable policy routing monitoring";
          };

          metrics = lib.mkOption {
            type = lib.types.attrsOf lib.types.bool;
            default = {
              policyHits = true;
              trafficByPolicy = true;
              tableUtilization = true;
            };
            description = "Monitoring metrics to enable";
          };
        };
      };
      default = { };
      description = "Monitoring configuration";
    };

    enableProxyArp = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Proxy ARP on internal interfaces to assist with routing";
    };

    internalInterfaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "List of internal interfaces where Proxy ARP should be enabled";
    };
  };

  config = lib.mkIf cfg.enable {

    # Validate policy routing configuration
    assertions = [
      {
        assertion = policyValidation.valid;
        message = "Policy routing validation failed: ${lib.concatStringsSep "; " policyValidation.errors}";
      }
    ];

    # Enable nftables if we have complex rules
    networking.nftables.enable = lib.mkIf (nftablesRules != [ ]) true;

    # Add required packages
    environment.systemPackages = with pkgs; [
      iproute2
      iptables
      statusScript
    ];

    # Create systemd service for policy routing
    systemd.services.policy-routing = {
      description = "Policy-Based Routing Setup";
      wantedBy = [ "network.target" ];
      after = [ "network.target" ];
      before = [ "network-online.target" ];

      path = with pkgs; [
        iproute2
        iptables
        procps
        coreutils
        gnugrep
        gawk
        gnused
      ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = setupScript;
        ExecStop = cleanupScript;
        ExecReload = setupScript;
        Restart = "on-failure";
        RestartSec = 5;
      };

      # Add dependencies on network interfaces
      unitConfig = {
        # These services are dynamically generated by networkd or scripting, and might not match this exact naming in a VM test environment.
        # We'll use network-online.target instead which is already in 'before'.
        # If we really need interface specific targets, we should check if they exist.
        # For now, let's relax this to just network.target which is already in 'after'.
      };
    };

    # Create status script
    environment.shellAliases = {
      # Alias for backward compatibility if needed, or just removed if the bin is preferred
      policy-routing-status = "policy-routing-status";
    };

    # Add monitoring configuration
    services.prometheus = lib.mkIf cfg.monitoring.enable {
      exporters = {
        node = {
          enabledCollectors = [
            "netdev"
            "netstat"
            "sockstat"
            "wifi"
            "hwmon"
            "diskstats"
            "filesystem"
            "filefd"
            "time"
            "uname"
            "cpufreq"
            "meminfo"
            "entropy"
            "stat"
            "vmstat"
          ];
          enable = true;
        };
      };
    };

    # Configure nftables for complex policy routing
    networking.nftables.tables = lib.mkIf (nftablesRules != [ ]) {
      policy-routing = {
        family = "inet";
        content = ''
          chain prerouting {
            type filter hook prerouting priority mangle; policy accept;
            ${lib.concatStringsSep "\n" nftablesRules}
          }
        '';
      };
    };

    # Log policy routing configuration
    environment.etc."policy-routing-config.txt" = {
      text = ''
        Policy-Based Routing Configuration:
        Enabled: ${lib.boolToString cfg.enable}
        Routing Tables: ${lib.concatStringsSep ", " (lib.attrNames cfg.routingTables)}
        Policies: ${lib.concatStringsSep ", " (lib.attrNames cfg.policies)}
        Monitoring: ${lib.boolToString cfg.monitoring.enable}

        ${lib.optionalString (!policyValidation.valid) ''
          Validation Errors:
          ${lib.concatStringsSep "\n" policyValidation.errors}
        ''}

        ${lib.optionalString (policyValidation.warnings != [ ]) ''
          Validation Warnings:
          ${lib.concatStringsSep "\n" policyValidation.warnings}
        ''}
      '';
    };

    # Add network configuration reload support
    systemd.services.policy-routing-reload = {
      description = "Reload Policy-Based Routing Configuration";
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.systemd}/bin/systemctl reload policy-routing";
        RemainAfterExit = true;
      };
    };
  };
}

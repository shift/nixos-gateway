{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    mkOption
    types
    mkIf
    mkEnableOption
    ;
  cfg = config.services.gateway.haCluster;

  clusterLib = import ../lib/cluster-manager.nix { inherit lib pkgs; };

  clusterManagerBin = pkgs.writeScriptBin "cluster-manager" ''
    #!${pkgs.python3}/bin/python3
    ${clusterLib.clusterScript}
  '';

  configFile = pkgs.writeText "cluster-config.json" (builtins.toJSON cfg);

in
{
  options.services.gateway.haCluster = {
    enable = mkEnableOption "High Availability Clustering";

    cluster = {
      name = mkOption {
        type = types.str;
        default = "gateway-cluster";
        description = "Name of the cluster";
      };

      nodes = mkOption {
        type = types.listOf types.attrs;
        default = [ ];
        description = "List of nodes in the cluster (name, address, role, priority)";
        example = [
          {
            name = "gw-01";
            address = "192.168.1.10";
            role = "active";
            priority = 100;
          }
          {
            name = "gw-02";
            address = "192.168.1.11";
            role = "standby";
            priority = 90;
          }
        ];
      };

      quorum = mkOption {
        type = types.attrs;
        default = {
          method = "majority";
          minimum = 2;
          timeout = "30s";
        };
        description = "Quorum configuration for cluster decisions";
      };

      communication = mkOption {
        type = types.attrs;
        default = {
          protocol = "tcp";
          port = 7946;
          encryption = true;
          heartbeat = {
            interval = "1s";
            timeout = "5s";
            retries = 3;
          };
        };
        description = "Cluster communication settings";
      };
    };

    loadBalancing = {
      enable = mkEnableOption "Load balancing for cluster services";

      algorithm = mkOption {
        type = types.enum [ "round-robin" "weighted-round-robin" "least-connections" "source-hash" ];
        default = "weighted-round-robin";
        description = "Load balancing algorithm";
      };

      virtualServices = mkOption {
        type = types.listOf types.attrs;
        default = [ ];
        description = "Virtual services configuration";
        example = [
          {
            name = "web-service";
            virtualIp = "192.168.1.100";
            port = 443;
            protocol = "tcp";
            realServers = [
              { address = "192.168.1.10"; port = 443; weight = 1; }
              { address = "192.168.1.11"; port = 443; weight = 1; }
            ];
            healthCheck = {
              enable = true;
              method = "http-get";
              path = "/health";
              interval = "10s";
              timeout = "3s";
              retries = 3;
            };
          }
        ];
      };

      persistence = mkOption {
        type = types.attrs;
        default = {
          enable = true;
          timeout = "300s";
          method = "source-ip";
        };
        description = "Session persistence configuration";
      };
    };

    services = {
      dns = {
        enable = mkEnableOption "DNS service clustering";

        type = mkOption {
          type = types.enum [ "active-passive" "active-active" ];
          default = "active-passive";
          description = "DNS clustering type";
        };

        virtualIp = mkOption {
          type = types.str;
          default = "192.168.1.1";
          description = "Virtual IP for DNS service";
        };

        port = mkOption {
          type = types.int;
          default = 53;
          description = "DNS service port";
        };

        failover = mkOption {
          type = types.attrs;
          default = {
            detection = "health-check";
            timeout = "10s";
            promotion = "automatic";
          };
          description = "DNS failover configuration";
        };

        synchronization = mkOption {
          type = types.attrs;
          default = {
            enable = true;
            type = "database-replication";
            primary = "gw-01";
            secondaries = [ "gw-02" "gw-03" ];
            method = "streaming";
            compression = true;
            encryption = true;
          };
          description = "DNS data synchronization";
        };
      };

      dhcp = {
        enable = mkEnableOption "DHCP service clustering";

        type = mkOption {
          type = types.enum [ "active-passive" "active-active" ];
          default = "active-passive";
          description = "DHCP clustering type";
        };

        virtualIp = mkOption {
          type = types.str;
          default = "192.168.1.1";
          description = "Virtual IP for DHCP service";
        };

        port = mkOption {
          type = types.int;
          default = 67;
          description = "DHCP service port";
        };

        failover = mkOption {
          type = types.attrs;
          default = {
            detection = "health-check";
            timeout = "15s";
            promotion = "automatic";
          };
          description = "DHCP failover configuration";
        };

        synchronization = mkOption {
          type = types.attrs;
          default = {
            enable = true;
            type = "database-replication";
            primary = "gw-01";
            secondaries = [ "gw-02" "gw-03" ];
            method = "synchronous";
            consistency = "strong";
          };
          description = "DHCP data synchronization";
        };
      };

      firewall = {
        enable = mkEnableOption "Firewall state clustering";

        type = mkOption {
          type = types.enum [ "active-active" ];
          default = "active-active";
          description = "Firewall clustering type";
        };

        synchronization = mkOption {
          type = types.attrs;
          default = {
            enable = true;
            type = "state-synchronization";
            connections = true;
            nat = true;
            rules = true;
            method = "multicast";
            group = "224.0.0.1";
            port = 3780;
          };
          description = "Firewall state synchronization";
        };
      };

      ids = {
        enable = mkEnableOption "IDS clustering";

        type = mkOption {
          type = types.enum [ "active-active" ];
          default = "active-active";
          description = "IDS clustering type";
        };

        loadBalancing = mkOption {
          type = types.attrs;
          default = {
            enable = true;
            method = "hash-based";
            fields = [ "src-ip" "dst-ip" "protocol" ];
            distribution = "uniform";
          };
          description = "IDS load balancing";
        };

        synchronization = mkOption {
          type = types.attrs;
          default = {
            enable = true;
            type = "alert-sharing";
            alerts = true;
            statistics = true;
            signatures = true;
            method = "tcp";
            port = 9390;
          };
          description = "IDS data synchronization";
        };
      };
    };

    failover = {
      detection = mkOption {
        type = types.attrs;
        default = {
          methods = [
            {
              name = "health-check";
              type = "service";
              interval = "5s";
              timeout = "10s";
              retries = 3;
            }
            {
              name = "heartbeat";
              type = "node";
              interval = "1s";
              timeout = "5s";
              retries = 3;
            }
            {
              name = "quorum";
              type = "cluster";
              interval = "10s";
              timeout = "30s";
            }
          ];
          scoring = {
            nodeHealth = 40;
            serviceHealth = 35;
            networkHealth = 25;
          };
          thresholds = {
            healthy = 90;
            warning = 70;
            critical = 50;
            failed = 30;
          };
        };
        description = "Failover detection configuration";
      };

      procedures = mkOption {
        type = types.listOf types.attrs;
        default = [
          {
            name = "service-failover";
            trigger = "service.health < critical";
            steps = [
              { type = "demote-service"; }
              { type = "promote-backup"; }
              { type = "update-virtual-ip"; }
              { type = "verify-service"; }
              { type = "notify-admins"; }
            ];
            timeout = "30s";
            rollback = true;
          }
          {
            name = "node-failover";
            trigger = "node.health < failed";
            steps = [
              { type = "isolate-node"; }
              { type = "redistribute-services"; }
              { type = "update-cluster"; }
              { type = "verify-cluster"; }
              { type = "notify-admins"; }
            ];
            timeout = "60s";
            rollback = false;
          }
        ];
        description = "Automated failover procedures";
      };
    };

    synchronization = {
      configuration = mkOption {
        type = types.attrs;
        default = {
          enable = true;
          type = "file-based";
          paths = [
            "/etc/nixos"
            "/etc/gateway"
            "/var/lib/gateway"
          ];
          method = "rsync";
          interval = "5m";
          compression = true;
          encryption = true;
          validation = {
            enable = true;
            method = "checksum";
            algorithm = "sha256";
          };
        };
        description = "Configuration synchronization";
      };

      database = mkOption {
        type = types.attrs;
        default = {
          enable = true;
          dns = {
            type = "postgresql-replication";
            method = "streaming";
            primary = "gw-01";
            secondaries = [ "gw-02" "gw-03" ];
            consistency = "eventual";
            conflictResolution = "last-writer";
          };
          dhcp = {
            type = "postgresql-replication";
            method = "streaming";
            primary = "gw-01";
            secondaries = [ "gw-02" "gw-03" ];
            consistency = "strong";
            failover = "automatic";
          };
        };
        description = "Database synchronization";
      };

      state = mkOption {
        type = types.attrs;
        default = {
          enable = true;
          firewall = {
            type = "connection-tracking";
            method = "multicast";
            group = "224.0.0.2";
            port = 3781;
            interval = "1s";
          };
          ids = {
            type = "alert-sharing";
            method = "tcp";
            port = 9391;
            compression = true;
            encryption = true;
          };
        };
        description = "State synchronization";
      };
    };

    monitoring = {
      enable = mkEnableOption "Cluster monitoring and alerting";

      metrics = mkOption {
        type = types.attrs;
        default = {
          clusterHealth = true;
          nodeStatus = true;
          serviceStatus = true;
          failoverEvents = true;
        };
        description = "Metrics to collect";
      };

      alerts = mkOption {
        type = types.attrs;
        default = {
          nodeFailure = { severity = "critical"; };
          serviceFailure = { severity = "high"; };
          splitBrain = { severity = "critical"; };
          quorumLoss = { severity = "critical"; };
        };
        description = "Alert configurations";
      };

      dashboard = mkOption {
        type = types.attrs;
        default = {
          enable = true;
          panels = [
            { title = "Cluster Status"; type = "overview"; }
            { title = "Node Health"; type = "grid"; }
            { title = "Service Distribution"; type = "chart"; }
            { title = "Failover History"; type = "timeline"; }
          ];
        };
        description = "Monitoring dashboard configuration";
      };
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ clusterManagerBin ];

    systemd.tmpfiles.rules = [
      "d /var/lib/ha-cluster 0755 root root -"
      "d /var/log/gateway 0755 root root -"
      "d /var/lib/cluster 0755 root root -"
    ];

    # Cluster manager service
    systemd.services.ha-cluster-manager = {
      description = "Gateway HA Cluster Manager";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        ExecStart = "${clusterManagerBin}/bin/cluster-manager init ${configFile}";
        Restart = "always";
        RestartSec = "5s";
        User = "root";
        Group = "root";
      };
    };

    # Load balancer service (using keepalived)
    services.keepalived = mkIf cfg.loadBalancing.enable {
      enable = true;
      vrrpInstances = builtins.map (node: {
        name = "${node.name}-vip";
        interface = "eth0";
        virtualRouterId = 51; # Use different IDs for different services
        priority = node.priority or 50;
        virtualIps = builtins.concatMap (service:
          if service ? virtualIp then [ "${service.virtualIp}/24" ] else []
        ) [cfg.services.dns cfg.services.dhcp];
        trackInterfaces = [ "eth0" ];
      }) cfg.cluster.nodes;

      virtualServers = builtins.map (vs: {
        ip = vs.virtualIp;
        port = vs.port;
        delayLoop = 6;
        lbAlgo = if cfg.loadBalancing.algorithm == "round-robin" then "rr"
                 else if cfg.loadBalancing.algorithm == "weighted-round-robin" then "wrr"
                 else if cfg.loadBalancing.algorithm == "least-connections" then "lc"
                 else "sh";
        lbKind = "NAT";
        protocol = vs.protocol;
        realServers = builtins.map (rs: {
          ip = rs.address;
          port = rs.port;
        }) vs.realServers;
        healthCheckers = if vs.healthCheck.method == "tcp" then {
          TCP_CHECK = {
            connectTimeout = 3;
            nbGetRetry = 3;
            delayBeforeRetry = 3;
          };
        } else if vs.healthCheck.method == "http-get" then {
          HTTP_GET = {
            url = {
              path = vs.healthCheck.path;
              statusCode = 200;
            };
            connectTimeout = 3;
            nbGetRetry = 3;
            delayBeforeRetry = 3;
          };
        } else {};
      }) cfg.loadBalancing.virtualServices;
    };

    # Configuration synchronization service
    systemd.services.ha-cluster-config-sync = mkIf cfg.synchronization.configuration.enable {
      description = "HA Cluster Configuration Synchronization";
      after = [ "network.target" ];

      serviceConfig = {
        ExecStart = "${pkgs.rsync}/bin/rsync -avz --delete ${lib.concatStringsSep " " cfg.synchronization.configuration.paths} /var/lib/cluster/config/";
        Type = "oneshot";
        User = "root";
      };
    };

    systemd.timers.ha-cluster-config-sync = mkIf cfg.synchronization.configuration.enable {
      description = "Timer for HA Cluster Configuration Synchronization";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*:0/${toString (cfg.synchronization.configuration.interval / 60)}"; # Convert minutes to cron format
        Persistent = true;
      };
    };

    # State synchronization services via etcd
    systemd.services.ha-cluster-dns-sync = mkIf cfg.services.dns.enable {
      description = "HA Cluster DNS State Synchronization via etcd";
      after = [ "network.target" "bind.service" "etcd.service" ];

      serviceConfig = {
        ExecStart = "${pkgs.etcd}/bin/etcdctl put /cluster/dns/state \"$(date -Iseconds)\"";
        Type = "oneshot";
        User = "root";
      };
    };

    systemd.timers.ha-cluster-dns-sync = mkIf cfg.services.dns.enable {
      description = "Timer for HA Cluster DNS Synchronization";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*:0/1"; # Every minute
        Persistent = true;
      };
    };

    systemd.services.ha-cluster-dhcp-sync = mkIf cfg.services.dhcp.enable {
      description = "HA Cluster DHCP State Synchronization via etcd";
      after = [ "network.target" "dhcpd.service" "etcd.service" ];

      serviceConfig = {
        ExecStart = "${pkgs.etcd}/bin/etcdctl put /cluster/dhcp/state \"$(date -Iseconds)\"";
        Type = "oneshot";
        User = "root";
      };
    };

    systemd.timers.ha-cluster-dhcp-sync = mkIf cfg.services.dhcp.enable {
      description = "Timer for HA Cluster DHCP Synchronization";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*:0/1"; # Every minute
        Persistent = true;
      };
    };

    # Monitoring service
    systemd.services.ha-cluster-monitoring = mkIf cfg.monitoring.enable {
      description = "HA Cluster Monitoring and Alerting";
      after = [ "network.target" ];

      serviceConfig = {
        ExecStart = "${clusterManagerBin}/bin/cluster-manager status ${configFile}";
        Type = "oneshot";
        User = "root";
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };

    systemd.timers.ha-cluster-monitoring = mkIf cfg.monitoring.enable {
      description = "Timer for HA Cluster Monitoring";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*:0/30"; # Every 30 seconds
        Persistent = true;
      };
    };

    # Firewall rules for cluster communication
    networking.firewall.allowedUDPPorts = [ 7946 ]; # Cluster communication port
    networking.firewall.allowedTCPPorts = [ 7946 9390 ]; # Cluster and sync ports
  };
}

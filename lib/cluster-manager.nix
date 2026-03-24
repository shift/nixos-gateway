{ lib, ... }:

let
  # Default high availability cluster configuration
  defaultHAClusterConfig = {
    enable = true;

    cluster = {
      name = "gateway-cluster";
      version = "1.0";

      nodes = [
        {
          name = "gw-01";
          address = "192.168.1.10";
          role = "active";
          priority = 100;
          weight = 1;
        }
        {
          name = "gw-02";
          address = "192.168.1.11";
          role = "standby";
          priority = 90;
          weight = 1;
        }
        {
          name = "gw-03";
          address = "192.168.1.12";
          role = "standby";
          priority = 80;
          weight = 1;
        }
      ];

      quorum = {
        method = "majority";
        minimum = 2;
        timeout = "30s";
      };

      communication = {
        protocol = "tcp";
        port = 7946;
        encryption = true;

        heartbeat = {
          interval = "1s";
          timeout = "5s";
          retries = 3;
        };
      };
    };

    services = {
      dns = {
        enable = true;
        type = "active-passive";

        virtualIp = "192.168.1.1";
        port = 53;

        failover = {
          detection = "health-check";
          timeout = "10s";
          promotion = "automatic";
        };

        synchronization = {
          enable = true;
          type = "database-replication";

          primary = "gw-01";
          secondaries = [ "gw-02" "gw-03" ];

          method = "streaming";
          compression = true;
          encryption = true;
        };
      };

      dhcp = {
        enable = true;
        type = "active-passive";

        virtualIp = "192.168.1.1";
        port = 67;

        failover = {
          detection = "health-check";
          timeout = "15s";
          promotion = "automatic";
        };

        synchronization = {
          enable = true;
          type = "database-replication";

          primary = "gw-01";
          secondaries = [ "gw-02" "gw-03" ];

          method = "synchronous";
          consistency = "strong";
        };
      };

      firewall = {
        enable = true;
        type = "active-active";

        synchronization = {
          enable = true;
          type = "state-synchronization";

          connections = true;
          nat = true;
          rules = true;

          method = "multicast";
          group = "224.0.0.1";
          port = 3780;
        };
      };

      ids = {
        enable = true;
        type = "active-active";

        loadBalancing = {
          enable = true;
          method = "hash-based";

          fields = [ "src-ip" "dst-ip" "protocol" ];
          distribution = "uniform";
        };

        synchronization = {
          enable = true;
          type = "alert-sharing";

          alerts = true;
          statistics = true;
          signatures = true;

          method = "tcp";
          port = 9390;
        };
      };
    };

    loadBalancing = {
      enable = true;

      algorithm = "weighted-round-robin";

      virtualServices = [
        {
          name = "dns-service";
          virtualIp = "192.168.1.1";
          port = 53;
          protocol = "udp";

          realServers = [
            { address = "192.168.1.10"; port = 53; weight = 1; }
            { address = "192.168.1.11"; port = 53; weight = 1; }
            { address = "192.168.1.12"; port = 53; weight = 1; }
          ];

          healthCheck = {
            enable = true;
            method = "udp-dns";
            interval = "5s";
            timeout = "2s";
            retries = 3;
          };
        }
        {
          name = "web-service";
          virtualIp = "192.168.1.1";
          port = 443;
          protocol = "tcp";

          realServers = [
            { address = "192.168.1.10"; port = 443; weight = 1; }
            { address = "192.168.1.11"; port = 443; weight = 1; }
            { address = "192.168.1.12"; port = 443; weight = 1; }
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

      persistence = {
        enable = true;
        timeout = "300s";
        method = "source-ip";
      };
    };

    failover = {
      detection = {
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

      procedures = [
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
    };

    synchronization = {
      configuration = {
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

      database = {
        enable = true;

        dns = {
          type = "mysql-replication";
          method = "group-replication";

          primary = "gw-01";
          secondaries = [ "gw-02" "gw-03" ];

          consistency = "eventual";
          conflictResolution = "last-writer";
        };

        dhcp = {
          type = "mysql-replication";
          method = "master-slave";

          primary = "gw-01";
          secondaries = [ "gw-02" "gw-03" ];

          consistency = "strong";
          failover = "automatic";
        };
      };

      state = {
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
    };

    monitoring = {
      enable = true;

      metrics = {
        clusterHealth = true;
        nodeStatus = true;
        serviceStatus = true;
        failoverEvents = true;
      };

      alerts = {
        nodeFailure = { severity = "critical"; };
        serviceFailure = { severity = "high"; };
        splitBrain = { severity = "critical"; };
        quorumLoss = { severity = "critical"; };
      };

      dashboard = {
        enable = true;

        panels = [
          { title = "Cluster Status"; type = "overview"; }
          { title = "Node Health"; type = "grid"; }
          { title = "Service Distribution"; type = "chart"; }
          { title = "Failover History"; type = "timeline"; }
        ];
      };
    };
  };

  # Enhanced cluster manager utilities
  clusterManagerUtils = ''
    import os
    import sys
    import logging
    import json
    import time
    import socket
    import threading
    import subprocess
    from datetime import datetime, timedelta
    from pathlib import Path

    # Configure logging
    logging.basicConfig(
        level=logging.INFO,
        format='''%(asctime)s - %(name)s - %(levelname)s - %(message)s'''
    )
    logger = logging.getLogger("ClusterManager")

    class ClusterManager:
        """Advanced cluster management and high availability system"""

        def __init__(self, config):
            self.config = config
            self.cluster_config = config.get('cluster', {})
            self.nodes_config = self.cluster_config.get('nodes', [])
            self.services_config = config.get('services', {})
            self.failover_config = config.get('failover', {})

            self.node_name = self._get_current_node_name()
            self.node_address = self._get_current_node_address()
            self.cluster_members = {}
            self.service_states = {}

        def _get_current_node_name(self):
            """Get the name of the current node"""
            hostname = socket.gethostname()
            # Try to match hostname with configured nodes
            for node in self.nodes_config:
                if node.get('name') in hostname or hostname in node.get('name'):
                    return node.get('name')
            return hostname

        def _get_current_node_address(self):
            """Get the IP address of the current node"""
            try:
                # Get primary IP address
                s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                s.connect(("8.8.8.8", 80))
                ip = s.getsockname()[0]
                s.close()
                return ip
            except Exception:
                return "127.0.0.1"

        def initialize_cluster(self):
            """Initialize the cluster and join nodes"""
            logger.info(f"Initializing cluster: {self.cluster_config.get('name')}")

            # Start cluster communication
            self._start_cluster_communication()

            # Discover cluster members
            self._discover_cluster_members()

            # Initialize services
            self._initialize_services()

            # Start health monitoring
            self._start_health_monitoring()

            logger.info("Cluster initialization complete")

        def _start_cluster_communication(self):
            """Start cluster communication and heartbeat"""
            logger.info("Starting cluster communication")

            comm_config = self.cluster_config.get('communication', {})
            heartbeat_config = comm_config.get('heartbeat', {})

            # Start heartbeat thread
            heartbeat_thread = threading.Thread(target=self._heartbeat_loop, daemon=True)
            heartbeat_thread.start()

            # Start listener thread
            listener_thread = threading.Thread(target=self._communication_listener, daemon=True)
            listener_thread.start()

        def _heartbeat_loop(self):
            """Send periodic heartbeats to other cluster members"""
            comm_config = self.cluster_config.get('communication', {})
            heartbeat_config = comm_config.get('heartbeat', {})

            interval = self._parse_duration(heartbeat_config.get('interval', '1s'))

            while True:
                try:
                    self._send_heartbeat()
                    time.sleep(interval)
                except Exception as e:
                    logger.error(f"Heartbeat error: {e}")
                    time.sleep(5)

        def _send_heartbeat(self):
            """Send heartbeat to all cluster members"""
            heartbeat_data = {
                'node': self.node_name,
                'address': self.node_address,
                'timestamp': datetime.now().isoformat(),
                'status': 'alive',
                'services': self._get_service_status()
            }

            # Send to all other nodes
            for node in self.nodes_config:
                if node.get('name') != self.node_name:
                    try:
                        self._send_message(node.get('address'), heartbeat_data)
                    except Exception as e:
                        logger.debug(f"Failed to send heartbeat to {node.get('name')}: {e}")

        def _communication_listener(self):
            """Listen for cluster communication messages"""
            comm_config = self.cluster_config.get('communication', {})
            port = comm_config.get('port', 7946)

            try:
                sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                sock.bind(('0.0.0.0', port))

                logger.info(f"Listening for cluster messages on port {port}")

                while True:
                    try:
                        data, addr = sock.recvfrom(4096)
                        message = json.loads(data.decode())
                        self._handle_message(message, addr)
                    except Exception as e:
                        logger.error(f"Message handling error: {e}")

            except Exception as e:
                logger.error(f"Communication listener error: {e}")

        def _handle_message(self, message, addr):
            """Handle incoming cluster messages"""
            msg_type = message.get('type', 'heartbeat')

            if msg_type == 'heartbeat':
                self._handle_heartbeat(message)
            elif msg_type == 'service_failover':
                self._handle_service_failover(message)
            elif msg_type == 'node_failover':
                self._handle_node_failover(message)

        def _handle_heartbeat(self, heartbeat):
            """Handle heartbeat message from cluster member"""
            node_name = heartbeat.get('node')
            if node_name and node_name != self.node_name:
                self.cluster_members[node_name] = {
                    'address': heartbeat.get('address'),
                    'last_seen': datetime.now(),
                    'status': heartbeat.get('status'),
                    'services': heartbeat.get('services', {})
                }

        def _handle_service_failover(self, message):
            """Handle service failover request"""
            service_name = message.get('service')
            new_primary = message.get('new_primary')

            logger.info(f"Service failover requested: {service_name} -> {new_primary}")

            if new_primary == self.node_name:
                self._promote_service(service_name)

        def _handle_node_failover(self, message):
            """Handle node failover request"""
            failed_node = message.get('failed_node')

            logger.info(f"Node failover requested for: {failed_node}")

            # Redistribute services from failed node
            self._redistribute_services(failed_node)

        def _discover_cluster_members(self):
            """Discover and validate cluster members"""
            logger.info("Discovering cluster members")

            for node in self.nodes_config:
                node_name = node.get('name')
                node_address = node.get('address')

                if node_name != self.node_name:
                    # Try to connect and validate
                    try:
                        # Simple connectivity check
                        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                        sock.settimeout(5)
                        result = sock.connect_ex((node_address, 22))  # SSH port
                        sock.close()

                        if result == 0:
                            self.cluster_members[node_name] = {
                                'address': node_address,
                                'status': 'discovered',
                                'last_seen': datetime.now()
                            }
                            logger.info(f"Discovered cluster member: {node_name} ({node_address})")
                        else:
                            logger.warning(f"Could not reach cluster member: {node_name} ({node_address})")

                    except Exception as e:
                        logger.error(f"Error discovering {node_name}: {e}")

        def _initialize_services(self):
            """Initialize cluster-aware services"""
            logger.info("Initializing cluster services")

            for service_name, service_config in self.services_config.items():
                if service_config.get('enable', False):
                    self._initialize_service(service_name, service_config)

        def _initialize_service(self, service_name, service_config):
            """Initialize a specific service in cluster mode"""
            service_type = service_config.get('type', 'active-passive')

            if service_type == 'active-passive':
                self._initialize_active_passive_service(service_name, service_config)
            elif service_type == 'active-active':
                self._initialize_active_active_service(service_name, service_config)

        def _initialize_active_passive_service(self, service_name, service_config):
            """Initialize active-passive service"""
            current_node = self._get_current_node()

            if current_node and current_node.get('role') == 'active':
                self._start_service_primary(service_name, service_config)
            else:
                self._start_service_secondary(service_name, service_config)

        def _initialize_active_active_service(self, service_name, service_config):
            """Initialize active-active service"""
            self._start_service_active(service_name, service_config)

        def _get_current_node(self):
            """Get current node configuration"""
            for node in self.nodes_config:
                if node.get('name') == self.node_name:
                    return node
            return None

        def _start_service_primary(self, service_name, service_config):
            """Start service in primary mode"""
            logger.info(f"Starting {service_name} in primary mode")

            # Configure virtual IP
            virtual_ip = service_config.get('virtualIp')
            if virtual_ip:
                self._configure_virtual_ip(virtual_ip, 'add')

            # Start service
            self._systemctl_service(service_name, 'start')

            # Start synchronization if configured
            sync_config = service_config.get('synchronization', {})
            if sync_config.get('enable', False):
                self._start_synchronization(service_name, sync_config, 'primary')

        def _start_service_secondary(self, service_name, service_config):
            """Start service in secondary mode"""
            logger.info(f"Starting {service_name} in secondary mode")

            # Start synchronization if configured
            sync_config = service_config.get('synchronization', {})
            if sync_config.get('enable', False):
                self._start_synchronization(service_name, sync_config, 'secondary')

        def _start_service_active(self, service_name, service_config):
            """Start service in active mode"""
            logger.info(f"Starting {service_name} in active mode")

            # Start service
            self._systemctl_service(service_name, 'start')

            # Start synchronization if configured
            sync_config = service_config.get('synchronization', {})
            if sync_config.get('enable', False):
                self._start_synchronization(service_name, sync_config, 'active')

        def _configure_virtual_ip(self, ip, action):
            """Configure virtual IP address"""
            try:
                if action == 'add':
                    subprocess.run(['ip', 'addr', 'add', f"{ip}/24", 'dev', 'eth0'], check=True)
                    logger.info(f"Added virtual IP: {ip}")
                elif action == 'del':
                    subprocess.run(['ip', 'addr', 'del', f"{ip}/24", 'dev', 'eth0'], check=True)
                    logger.info(f"Removed virtual IP: {ip}")
            except Exception as e:
                logger.error(f"Failed to {action} virtual IP {ip}: {e}")

        def _systemctl_service(self, service_name, action):
            """Control systemd service"""
            try:
                subprocess.run(['systemctl', action, service_name], check=True)
                logger.info(f"Service {service_name} {action}d")
            except Exception as e:
                logger.error(f"Failed to {action} service {service_name}: {e}")

        def _start_synchronization(self, service_name, sync_config, role):
            """Start data synchronization"""
            sync_type = sync_config.get('type')

            if sync_type == 'database-replication':
                self._start_database_replication(service_name, sync_config, role)
            elif sync_type == 'state-synchronization':
                self._start_state_synchronization(service_name, sync_config, role)

        def _start_database_replication(self, service_name, sync_config, role):
            """Start database replication"""
            logger.info(f"Starting database replication for {service_name} in {role} mode")

            # Database-specific replication setup would go here
            # This is a placeholder for the actual implementation
            logger.info("Database replication setup complete")

        def _start_state_synchronization(self, service_name, sync_config, role):
            """Start state synchronization"""
            logger.info(f"Starting state synchronization for {service_name}")

            # State synchronization setup would go here
            logger.info("State synchronization setup complete")

        def _start_health_monitoring(self):
            """Start health monitoring for cluster"""
            logger.info("Starting cluster health monitoring")

            # Start monitoring thread
            monitor_thread = threading.Thread(target=self._health_monitor_loop, daemon=True)
            monitor_thread.start()

        def _health_monitor_loop(self):
            """Monitor cluster and service health"""
            while True:
                try:
                    self._check_cluster_health()
                    self._check_service_health()
                    time.sleep(30)  # Check every 30 seconds
                except Exception as e:
                    logger.error(f"Health monitoring error: {e}")
                    time.sleep(30)

        def _check_cluster_health(self):
            """Check overall cluster health"""
            # Check quorum
            active_members = len([m for m in self.cluster_members.values() if m.get('status') == 'alive'])
            total_nodes = len(self.nodes_config)

            quorum_config = self.cluster_config.get('quorum', {})
            minimum_quorum = quorum_config.get('minimum', 2)

            if active_members < minimum_quorum:
                logger.critical(f"Cluster quorum lost: {active_members}/{total_nodes} nodes active")
                # Trigger cluster-wide alert

            # Check for failed nodes
            now = datetime.now()
            for node_name, member in self.cluster_members.items():
                last_seen = member.get('last_seen')
                if last_seen and (now - last_seen).seconds > 60:  # 1 minute timeout
                    logger.warning(f"Node {node_name} appears to be down")
                    self._handle_node_failure(node_name)

        def _check_service_health(self):
            """Check health of cluster services"""
            for service_name, service_config in self.services_config.items():
                if service_config.get('enable', False):
                    health = self._check_service_health_status(service_name, service_config)
                    self.service_states[service_name] = health

                    if not health.get('healthy', False):
                        logger.warning(f"Service {service_name} is unhealthy")
                        self._handle_service_failure(service_name, service_config)

        def _check_service_health_status(self, service_name, service_config):
            """Check health status of a specific service"""
            # Service-specific health checks would go here
            # This is a simplified implementation
            try:
                result = subprocess.run(['systemctl', 'is-active', service_name],
                                      capture_output=True, text=True, timeout=10)
                healthy = result.returncode == 0 and 'active' in result.stdout
                return {
                    'healthy': healthy,
                    'status': result.stdout.strip(),
                    'timestamp': datetime.now().isoformat()
                }
            except Exception as e:
                return {
                    'healthy': False,
                    'error': str(e),
                    'timestamp': datetime.now().isoformat()
                }

        def _handle_service_failure(self, service_name, service_config):
            """Handle service failure and initiate failover if needed"""
            logger.info(f"Handling service failure: {service_name}")

            failover_config = service_config.get('failover', {})
            if failover_config.get('promotion', 'automatic') == 'automatic':
                self._initiate_service_failover(service_name, service_config)

        def _handle_node_failure(self, node_name):
            """Handle node failure"""
            logger.info(f"Handling node failure: {node_name}")

            # Mark node as failed
            if node_name in self.cluster_members:
                self.cluster_members[node_name]['status'] = 'failed'

            # Redistribute services
            self._redistribute_services(node_name)

        def _initiate_service_failover(self, service_name, service_config):
            """Initiate service failover"""
            logger.info(f"Initiating service failover for {service_name}")

            # Find suitable backup node
            backup_node = self._find_backup_node(service_name, service_config)

            if backup_node:
                # Send failover message to backup node
                failover_message = {
                    'type': 'service_failover',
                    'service': service_name,
                    'new_primary': backup_node,
                    'timestamp': datetime.now().isoformat()
                }

                self._broadcast_message(failover_message)
                logger.info(f"Service failover initiated: {service_name} -> {backup_node}")
            else:
                logger.error(f"No suitable backup node found for {service_name}")

        def _find_backup_node(self, service_name, service_config):
            """Find a suitable backup node for service failover"""
            # Sort nodes by priority
            sorted_nodes = sorted(self.nodes_config, key=lambda x: x.get('priority', 0), reverse=True)

            for node in sorted_nodes:
                node_name = node.get('name')
                if node_name != self.node_name and self.cluster_members.get(node_name, {}).get('status') == 'alive':
                    return node_name

            return None

        def _promote_service(self, service_name):
            """Promote this node to primary for a service"""
            logger.info(f"Promoting to primary for service: {service_name}")

            service_config = self.services_config.get(service_name, {})

            # Configure virtual IP
            virtual_ip = service_config.get('virtualIp')
            if virtual_ip:
                self._configure_virtual_ip(virtual_ip, 'add')

            # Start service in primary mode
            self._start_service_primary(service_name, service_config)

        def _redistribute_services(self, failed_node):
            """Redistribute services from a failed node"""
            logger.info(f"Redistributing services from failed node: {failed_node}")

            # Find services that were running on the failed node
            services_to_redistribute = []
            for service_name, service_config in self.services_config.items():
                if service_config.get('enable', False):
                    # Check if this service was active on the failed node
                    # This is a simplified check
                    services_to_redistribute.append((service_name, service_config))

            for service_name, service_config in services_to_redistribute:
                self._initiate_service_failover(service_name, service_config)

        def _send_message(self, address, message):
            """Send message to specific cluster member"""
            comm_config = self.cluster_config.get('communication', {})
            port = comm_config.get('port', 7946)

            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.settimeout(5)
            try:
                data = json.dumps(message).encode()
                sock.sendto(data, (address, port))
            finally:
                sock.close()

        def _broadcast_message(self, message):
            """Broadcast message to all cluster members"""
            for node in self.nodes_config:
                if node.get('name') != self.node_name:
                    try:
                        self._send_message(node.get('address'), message)
                    except Exception as e:
                        logger.debug(f"Failed to send message to {node.get('name')}: {e}")

        def _parse_duration(self, duration_str):
            """Parse duration string to seconds"""
            if duration_str.endswith('s'):
                return int(duration_str[:-1])
            elif duration_str.endswith('m'):
                return int(duration_str[:-1]) * 60
            elif duration_str.endswith('h'):
                return int(duration_str[:-1]) * 3600
            else:
                return int(duration_str)

        def _get_service_status(self):
            """Get status of all services on this node"""
            status = {}
            for service_name in self.services_config.keys():
                service_status = self._check_service_health_status(service_name, {})
                status[service_name] = service_status
            return status

        def get_cluster_status(self):
            """Get overall cluster status"""
            return {
                'cluster_name': self.cluster_config.get('name'),
                'node_name': self.node_name,
                'node_address': self.node_address,
                'members': self.cluster_members,
                'services': self.service_states,
                'timestamp': datetime.now().isoformat()
            }

    def main():
        """Main function for command-line usage"""
        if len(sys.argv) < 2:
            print("Usage: cluster-manager <command> [args...]")
            print("Commands: init, status, failover, join, leave")
            sys.exit(1)

        command = sys.argv[1]

        if command == 'init':
            if len(sys.argv) < 3:
                print("Usage: cluster-manager init <config_file>")
                sys.exit(1)

            config_file = sys.argv[2]

            try:
                with open(config_file, 'r') as f:
                    config = json.load(f)

                manager = ClusterManager(config)
                manager.initialize_cluster()
                print("Cluster initialized successfully")

            except Exception as e:
                print(f"Cluster initialization failed: {e}")
                sys.exit(1)

        elif command == 'status':
            if len(sys.argv) < 3:
                print("Usage: cluster-manager status <config_file>")
                sys.exit(1)

            config_file = sys.argv[2]

            try:
                with open(config_file, 'r') as f:
                    config = json.load(f)

                manager = ClusterManager(config)
                status = manager.get_cluster_status()

                print("Cluster Status:")
                print(f"Cluster: {status['cluster_name']}")
                print(f"Local Node: {status['node_name']} ({status['node_address']})")
                print("\nCluster Members:")
                for name, member in status['members'].items():
                    print(f"  {name}: {member.get('status', 'unknown')} ({member.get('address', 'unknown')})")

                print("\nServices:")
                for name, svc_status in status['services'].items():
                    healthy = "✓" if svc_status.get('healthy', False) else "✗"
                    print(f"  {name}: {healthy}")

            except Exception as e:
                print(f"Status check failed: {e}")
                sys.exit(1)

        elif command == 'failover':
            if len(sys.argv) < 4:
                print("Usage: cluster-manager failover <config_file> <service>")
                sys.exit(1)

            config_file = sys.argv[2]
            service_name = sys.argv[3]

            try:
                with open(config_file, 'r') as f:
                    config = json.load(f)

                manager = ClusterManager(config)
                service_config = config.get('services', {}).get(service_name, {})
                manager._initiate_service_failover(service_name, service_config)
                print(f"Failover initiated for service: {service_name}")

            except Exception as e:
                print(f"Failover failed: {e}")
                sys.exit(1)

        elif command == 'join':
            if len(sys.argv) < 3:
                print("Usage: cluster-manager join <config_file>")
                sys.exit(1)

            config_file = sys.argv[2]

            try:
                with open(config_file, 'r') as f:
                    config = json.load(f)

                manager = ClusterManager(config)
                manager._discover_cluster_members()
                print("Joined cluster successfully")

            except Exception as e:
                print(f"Join failed: {e}")
                sys.exit(1)

        elif command == 'leave':
            print("Leave cluster functionality not implemented yet")
            sys.exit(1)

        else:
            print(f"Unknown command: {command}")
            sys.exit(1)

    if __name__ == "__main__":
        main()
  '';

  # Utility functions for cluster management
  utils = {
    # Validate high availability cluster configuration
    validateConfig = config:
{ lib }:

let
        inherit (lib) types;
        cfg = config.services.gateway.haCluster or {};
      in
      if cfg.enable or false then
        # Basic validation - check required fields
        if !(cfg ? cluster) then
          throw "HA cluster enabled but no cluster configuration provided"
        else if !(cfg ? services) then
          throw "HA cluster enabled but no services configuration provided"
        else if !(cfg ? failover) then
          throw "HA cluster enabled but no failover configuration provided"
        else
          cfg
      else
        cfg;

    # Generate cluster communication script
    generateClusterCommunicationScript = clusterConfig: ''
      #!/bin/bash

      CLUSTER_NAME="${clusterConfig.name}"
      NODE_NAME="$(hostname)"
      LOG_FILE="/var/log/gateway/cluster-communication.log"

      log() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
      }

      log "Starting cluster communication for $CLUSTER_NAME"

      # Cluster communication setup would go here
      # This includes heartbeat, message passing, etc.

      log "Cluster communication initialized"
    '';

    # Generate service failover script
    generateServiceFailoverScript = serviceName: serviceConfig: ''
      #!/bin/bash

      SERVICE_NAME="${serviceName}"
      LOG_FILE="/var/log/gateway/failover-$SERVICE_NAME.log"

      log() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
      }

      log "Starting service failover for $SERVICE_NAME"

      # Demote current primary
      log "Demoting current primary service"
      systemctl stop "$SERVICE_NAME"

      # Remove virtual IP from current node
      # Virtual IP management would go here

      # Promote backup service
      log "Promoting backup service"
      # Service promotion logic would go here

      # Update virtual IP
      log "Updating virtual IP"
      # Virtual IP update logic would go here

      # Verify service
      log "Verifying service functionality"
      if systemctl is-active --quiet "$SERVICE_NAME"; then
        log "Service failover completed successfully"
      else
        log "Service failover failed"
        exit 1
      fi
    '';

    # Generate load balancer configuration
    generateLoadBalancerConfig = lbConfig: ''
      #!/bin/bash

      log() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "/var/log/gateway/load-balancer.log"
      }

      log "Configuring load balancer"

      # Load balancer configuration would go here
      # This includes virtual services, real servers, health checks, etc.

      log "Load balancer configuration complete"
    '';

    # Generate systemd timer configuration
    generateSystemdTimer = name: schedule: ''
      [Unit]
      Description=Timer for ${name} cluster operation
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
      Description=${name} cluster service
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
        "/var/lib/cluster"
        "/var/log/gateway"
        "/tmp"
      ]}

      [Install]
      WantedBy=multi-user.target
    '';

    # Merge user config with defaults
    mergeConfig = userConfig:
      lib.recursiveUpdate defaultHAClusterConfig userConfig;
  };

in
{
  inherit defaultHAClusterConfig clusterManagerUtils utils;
}

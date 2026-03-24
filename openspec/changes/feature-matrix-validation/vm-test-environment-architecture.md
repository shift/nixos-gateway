# VM Test Environment Architecture Design

## Multi-Node Test Topology Design

### Core Test Topology Architecture

```nix
# lib/test-topology.nix
{ lib, ... }:

let
  # Base node configuration
  baseNodeConfig = {
    virtualisation.memorySize = 2048;  # 2GB RAM minimum
    virtualisation.cores = 2;          # 2 CPU cores
    virtualisation.diskSize = 10240;   # 10GB disk

    # Common test utilities
    environment.systemPackages = with pkgs; [
      curl
      dnsutils
      iputils
      tcpdump
      htop
      jq
      stress-ng
      iperf3
    ];

    # Enable systemd services for testing
    services.journald.rateLimitBurst = 10000;
    services.journald.rateLimitInterval = "30s";
  };

  # Gateway node configuration
  gatewayNode = featureConfig: lib.recursiveUpdate baseNodeConfig {
    networking.primaryIPAddress = "192.168.1.1";

    # Feature-specific configuration
    services.gateway = featureConfig;

    # Monitoring and metrics collection
    services.prometheus.exporters.node.enable = true;
    services.prometheus.exporters.node.port = 9100;

    # Test result collection
    systemd.services.test-result-collector = {
      description = "Collect test results and metrics";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "/bin/sh -c 'mkdir -p /tmp/test-results && echo \"Test environment ready\" > /tmp/test-results/environment-status.txt'";
      };
    };
  };

  # Client node configurations
  clientNode1 = {
    networking.useDHCP = true;
    networking.nameservers = [ "192.168.1.1" ];

    # Client-side testing tools
    environment.systemPackages = with pkgs; [
      curl
      wget
      openssh
      dhcpcd
      tcpdump
      apacheHttpd  # For ab testing
    ];

    # SSH key for gateway access
    systemd.services.generate-ssh-key = {
      description = "Generate SSH key for testing";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        mkdir -p /root/.ssh
        ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519 -N ""
        cat /root/.ssh/id_ed25519.pub >> /root/.ssh/authorized_keys
      '';
    };
  };

  clientNode2 = lib.recursiveUpdate clientNode1 {
    # Additional client for multi-client testing
    networking.hostName = "client2";

    systemd.services.client-load-generator = {
      description = "Generate background load for testing";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "/bin/sh -c 'while true; do curl -s http://gateway/ > /dev/null 2>&1; sleep 1; done'";
      };
    };
  };

  # External node for internet simulation
  externalNode = {
    networking.useDHCP = true;

    # Simulate external services
    services.httpd.enable = true;
    services.httpd.adminAddr = "admin@example.com";
    services.httpd.documentRoot = "/tmp/httpd-docs";

    systemd.services.setup-external-services = {
      description = "Setup external test services";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        mkdir -p /tmp/httpd-docs
        echo "<html><body><h1>External Test Service</h1><p>IP: $(hostname -I)</p></body></html>" > /tmp/httpd-docs/index.html

        # Setup DNS server simulation
        echo "127.0.0.1 example.com" >> /etc/hosts
      '';
    };
  };

  # Monitoring node for centralized metrics
  monitoringNode = {
    services.prometheus.enable = true;
    services.prometheus.scrapeConfigs = [
      {
        job_name = "gateway";
        static_configs = [{ targets = [ "gateway:9100" ]; }];
      }
      {
        job_name = "client1";
        static_configs = [{ targets = [ "client1:9100" ]; }];
      }
    ];

    services.grafana.enable = true;
    services.grafana.settings.server.http_port = 3000;

    # Test result aggregation
    systemd.services.test-aggregator = {
      description = "Aggregate test results from all nodes";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "/bin/sh -c 'mkdir -p /tmp/aggregated-results'";
      };
    };
  };

in {
  # Test topology configurations
  topologies = {
    # Basic 2-node topology (gateway + client)
    basic = {
      gateway = gatewayNode;
      client1 = clientNode1;
    };

    # Standard 3-node topology (gateway + 2 clients)
    standard = {
      gateway = gatewayNode;
      client1 = clientNode1;
      client2 = clientNode2;
    };

    # Full test topology (gateway + clients + external + monitoring)
    full = {
      gateway = gatewayNode;
      client1 = clientNode1;
      client2 = clientNode2;
      external = externalNode;
      monitoring = monitoringNode;
    };

    # High-load topology (gateway + multiple clients)
    highLoad = {
      gateway = gatewayNode;
      client1 = clientNode1;
      client2 = clientNode2;
      client3 = lib.recursiveUpdate clientNode1 { networking.hostName = "client3"; };
      client4 = lib.recursiveUpdate clientNode1 { networking.hostName = "client4"; };
      client5 = lib.recursiveUpdate clientNode1 { networking.hostName = "client5"; };
    };

    # Network segmentation topology
    segmented = {
      gateway = gatewayNode;

      # LAN segment
      lanClient1 = clientNode1;
      lanClient2 = clientNode2;

      # DMZ segment
      dmzServer = {
        networking.interfaces.eth1.ipv4.addresses = [ { address = "192.168.2.10"; prefixLength = 24; } ];
        services.httpd.enable = true;
      };

      # Guest network segment
      guestClient = lib.recursiveUpdate clientNode1 {
        networking.hostName = "guest";
        networking.interfaces.eth1.useDHCP = true;
      };
    };

    # VPN topology
    vpn = {
      gateway = gatewayNode;

      # Internal client
      internalClient = clientNode1;

      # External client connecting via VPN
      vpnClient = lib.recursiveUpdate clientNode1 {
        networking.hostName = "vpn-client";
        # VPN client configuration would be added here
      };
    };

    # Failover topology
    failover = {
      primaryGateway = gatewayNode;
      backupGateway = lib.recursiveUpdate gatewayNode {
        networking.hostName = "backup-gateway";
        networking.interfaces.eth1.ipv4.addresses = [ { address = "192.168.1.2"; prefixLength = 24; } ];
      };
      client1 = clientNode1;
    };
  };

  # Network isolation configurations
  networkConfigs = {
    # Isolated test networks
    isolated = {
      vlans = {
        "1" = { };  # Internal network
        "2" = { };  # External simulation
        "3" = { };  # DMZ network
      };
    };

    # Internet-connected (for external service testing)
    internet = {
      vlans = {
        "1" = { };  # Internal network
      };
      # Allow internet access for external service testing
      virtualisation.forwardPorts = [
        { from = "host"; host.port = 8080; guest.port = 80; }
      ];
    };

    # Multi-segment enterprise simulation
    enterprise = {
      vlans = {
        "10" = { };  # Management network
        "20" = { };  # User network
        "30" = { };  # Server network
        "40" = { };  # Guest network
        "50" = { };  # DMZ
      };
    };
  };

  # Test scenario configurations
  scenarios = {
    # Basic functionality test
    basic = {
      topology = "standard";
      network = "isolated";
      duration = 300;  # 5 minutes
      checks = [ "functional" "performance" ];
    };

    # Comprehensive validation
    comprehensive = {
      topology = "full";
      network = "isolated";
      duration = 1800;  # 30 minutes
      checks = [ "functional" "performance" "security" "resource" "error-handling" ];
    };

    # Load testing
    load = {
      topology = "highLoad";
      network = "isolated";
      duration = 900;  # 15 minutes
      checks = [ "performance" "resource" ];
    };

    # Security testing
    security = {
      topology = "standard";
      network = "internet";
      duration = 600;  # 10 minutes
      checks = [ "security" "error-handling" ];
    };

    # Network topology testing
    network = {
      topology = "segmented";
      network = "enterprise";
      duration = 1200;  # 20 minutes
      checks = [ "functional" "security" "error-handling" ];
    };

    # VPN testing
    vpn = {
      topology = "vpn";
      network = "isolated";
      duration = 600;  # 10 minutes
      checks = [ "functional" "security" "performance" ];
    };

    # Failover testing
    failover = {
      topology = "failover";
      network = "isolated";
      duration = 900;  # 15 minutes
      checks = [ "error-handling" "functional" ];
    };
  };
}
```

## Network Isolation Implementation

```nix
# lib/network-isolation.nix
{ lib, ... }:

let
  # VLAN configuration helpers
  mkVlanNetwork = vlanId: {
    name = "vlan${vlanId}";
    address = "192.168.${vlanId}.0/24";
    gateway = "192.168.${vlanId}.1";
  };

  # Firewall isolation rules
  isolationRules = vlanId: ''
    # Isolate VLAN ${vlanId} from other networks
    iptables -A FORWARD -i vlan${vlanId} -o vlan${vlanId} -j ACCEPT
    iptables -A FORWARD -i vlan${vlanId} ! -o vlan${vlanId} -j DROP
    iptables -A FORWARD ! -i vlan${vlanId} -o vlan${vlanId} -j DROP
  '';

in {
  # Network isolation configurations
  isolation = {
    # Complete isolation (no inter-VLAN communication)
    complete = vlans: lib.concatMapStrings (vlan: ''
      # Setup VLAN ${vlan}
      ip link add link eth0 name vlan${vlan} type vlan id ${vlan}
      ip link set vlan${vlan} up
      ip addr add ${mkVlanNetwork vlan}.gateway/24 dev vlan${vlan}

      ${isolationRules vlan}
    '') vlans;

    # Controlled communication (allow specific traffic)
    controlled = vlans: rules: lib.concatMapStrings (vlan: ''
      # Setup VLAN ${vlan} with controlled access
      ip link add link eth0 name vlan${vlan} type vlan id ${vlan}
      ip link set vlan${vlan} up
      ip addr add ${mkVlanNetwork vlan}.gateway/24 dev vlan${vlan}

      # Apply custom rules
      ${rules vlan}
    '') vlans;

    # Bridge mode (transparent forwarding)
    bridge = vlans: lib.concatMapStrings (vlan: ''
      # Setup VLAN ${vlan} in bridge mode
      ip link add br${vlan} type bridge
      ip link set br${vlan} up
      ip link add link eth0 name vlan${vlan} type vlan id ${vlan}
      ip link set vlan${vlan} master br${vlan}
      ip link set vlan${vlan} up
    '') vlans;
  };

  # Traffic shaping for test conditions
  trafficShaping = {
    # Simulate network congestion
    congestion = interface: rate: ''
      tc qdisc add dev ${interface} root tbf rate ${rate}mbit burst 32kbit latency 400ms
    '';

    # Simulate packet loss
    packetLoss = interface: percentage: ''
      tc qdisc add dev ${interface} root netem loss ${percentage}%
    '';

    # Simulate latency
    latency = interface: delay: ''
      tc qdisc add dev ${interface} root netem delay ${delay}ms
    '';

    # Clear traffic shaping
    clear = interface: ''
      tc qdisc del dev ${interface} root 2>/dev/null || true
    '';
  };

  # Network monitoring setup
  monitoring = {
    # Packet capture setup
    packetCapture = interface: filter: ''
      tcpdump -i ${interface} -w /tmp/capture.pcap ${filter} &
      echo $! > /tmp/tcpdump.pid
    '';

    # Stop packet capture
    stopCapture = ''
      if [ -f /tmp/tcpdump.pid ]; then
        kill $(cat /tmp/tcpdump.pid) 2>/dev/null || true
        rm -f /tmp/tcpdump.pid
      fi
    '';

    # Network statistics collection
    collectStats = interface: ''
      # Collect interface statistics
      ip -s link show ${interface} > /tmp/${interface}-stats.txt
      # Collect routing table
      ip route show > /tmp/routing-table.txt
      # Collect ARP table
      ip neigh show > /tmp/arp-table.txt
    '';
  };
}
```

## Automated Test Orchestration

```bash
#!/usr/bin/env bash
# scripts/run-test-orchestration.sh

set -euo pipefail

COMBINATION="$1"
SCENARIO="$2"
CONFIG_FILE="$3"
RESULTS_DIR="results/$COMBINATION"

echo "Running orchestrated test for $COMBINATION using $SCENARIO scenario"

# Load test topology configuration
TOPOLOGY_CONFIG="lib/test-topology.nix"
NETWORK_CONFIG="lib/network-isolation.nix"

# Generate comprehensive test
cat > "tests/${COMBINATION}-${SCENARIO}-orchestrated.nix" << EOF
{ pkgs, lib, ... }:

let
  testTopology = import $TOPOLOGY_CONFIG { inherit lib; };
  networkIsolation = import $NETWORK_CONFIG { inherit lib; };

  scenario = testTopology.scenarios.${SCENARIO};
  topology = testTopology.topologies.\${scenario.topology};
  network = testTopology.networkConfigs.\${scenario.network};

  # Apply feature configuration to gateway
  featureConfig = import "$CONFIG_FILE";
  configuredTopology = topology // {
    gateway = topology.gateway featureConfig;
  };

in

pkgs.testers.nixosTest {
  name = "${COMBINATION}-${SCENARIO}-orchestrated";

  nodes = configuredTopology;

  testScript = ''
    start_all()

    # Setup network isolation
    gateway.succeed("
      ${networkIsolation.isolation.complete network.vlans}
    ")

    # Initialize monitoring
    gateway.succeed("
      mkdir -p /tmp/test-monitoring
      echo "Test started at $(date)" > /tmp/test-monitoring/start-time.txt
    ")

    # Run validation checks based on scenario
    \${lib.concatMapStrings (check: ''
      # Run ${check} validation
      \${import ../lib/\${check}-checks.nix { inherit lib; }}.\${check}.\${check}Test.testScript}
    '') scenario.checks}

    # Collect comprehensive results
    mkdir -p /tmp/test-results
    cp -r /tmp/validation-results/* /tmp/test-results/ 2>/dev/null || true
    cp -r /tmp/performance-metrics/* /tmp/test-results/ 2>/dev/null || true
    cp -r /tmp/security-results/* /tmp/test-results/ 2>/dev/null || true
    cp -r /tmp/resource-metrics/* /tmp/test-results/ 2>/dev/null || true
    cp -r /tmp/error-metrics/* /tmp/test-results/ 2>/dev/null || true
    cp -r /tmp/test-monitoring/* /tmp/test-results/ 2>/dev/null || true

    # Generate test summary
    cat > /tmp/test-results/test-summary.json << EOF
    {
      "combination": "$COMBINATION",
      "scenario": "$SCENARIO",
      "topology": "\${scenario.topology}",
      "duration_seconds": \${scenario.duration},
      "checks_run": \${lib.length scenario.checks},
      "timestamp": "$(date -Iseconds)",
      "nodes_tested": \${lib.length (lib.attrNames configuredTopology)}
    }
    EOF
  '';
}
EOF

# Run the orchestrated test
echo "Executing orchestrated test..."
if nix build ".#checks.x86_64-linux.${COMBINATION}-${SCENARIO}-orchestrated"; then
  echo "✅ Orchestrated test completed successfully"

  # Extract and organize results
  mkdir -p "$RESULTS_DIR/$SCENARIO"
  cp result/test-results/* "$RESULTS_DIR/$SCENARIO/" 2>/dev/null || true

  # Generate orchestration summary
  cat > "$RESULTS_DIR/${SCENARIO}-orchestration-summary.json" << EOF
  {
    "combination": "$COMBINATION",
    "scenario": "$SCENARIO",
    "execution_time": "$(date -Iseconds)",
    "status": "completed",
    "results_location": "$RESULTS_DIR/$SCENARIO"
  }
  EOF

else
  echo "❌ Orchestrated test failed"
  exit 1
fi
```

## Result Collection and Analysis Framework

```bash
#!/usr/bin/env bash
# scripts/collect-test-results.sh

COMBINATION="$1"
SCENARIO="$2"
RESULTS_DIR="results/$COMBINATION/$SCENARIO"

echo "Collecting and analyzing test results for $COMBINATION ($SCENARIO)"

# Initialize results structure
mkdir -p "$RESULTS_DIR/analysis"

# Collect all result files
find "$RESULTS_DIR" -name "*.json" -exec cp {} "$RESULTS_DIR/analysis/" \;

# Generate comprehensive analysis
cat > "$RESULTS_DIR/analysis/comprehensive-analysis.json" << EOF
{
  "combination": "$COMBINATION",
  "scenario": "$SCENARIO",
  "analysis_timestamp": "$(date -Iseconds)",
  "categories_analyzed": [
    "functional",
    "performance",
    "security",
    "resource",
    "error-handling"
  ],
  "files_analyzed": $(find "$RESULTS_DIR/analysis" -name "*.json" | wc -l)
}
EOF

# Run individual analysis scripts
./scripts/analyze-functional-results.sh "$COMBINATION" "$RESULTS_DIR" > "$RESULTS_DIR/analysis/functional-analysis.txt"
./scripts/analyze-performance-results.sh "$COMBINATION" "$RESULTS_DIR" > "$RESULTS_DIR/analysis/performance-analysis.txt"
./scripts/analyze-security-results.sh "$COMBINATION" "$RESULTS_DIR" > "$RESULTS_DIR/analysis/security-analysis.txt"
./scripts/analyze-resource-results.sh "$COMBINATION" "$RESULTS_DIR" > "$RESULTS_DIR/analysis/resource-analysis.txt"
./scripts/analyze-error-handling-results.sh "$COMBINATION" "$RESULTS_DIR" > "$RESULTS_DIR/analysis/error-handling-analysis.txt"

# Generate final support recommendation
./scripts/generate-support-recommendation.sh "$COMBINATION" "$RESULTS_DIR" > "$RESULTS_DIR/analysis/support-recommendation.json"

echo "Test result collection and analysis completed"
echo "Results available in: $RESULTS_DIR/analysis/"
```

This VM test environment architecture provides a comprehensive, automated framework for testing feature combinations in isolated, controlled environments with full monitoring and result collection capabilities.
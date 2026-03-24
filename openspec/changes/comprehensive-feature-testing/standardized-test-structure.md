# Standardized Test Structure with Evidence Collection

## Test Framework Architecture

```nix
# lib/standardized-test-framework.nix
{ lib, ... }:

let
  # Standardized test wrapper
  mkStandardTest = {
    name,
    description,
    feature,
    category,
    nodes,
    testScript,
    evidenceCollectors ? [],
    timeout ? 600,
    tags ? []
  }: {
    inherit name description feature category timeout tags;

    # Enhanced test with evidence collection
    test = pkgs.testers.nixosTest {
      inherit name;
      inherit nodes;

      testScript = ''
        # Initialize evidence collection
        ${initializeEvidenceCollection name}

        try {
          # Run the actual test
          ${testScript}

          # Mark test as passed
          ${recordTestResult name "passed"}

        } catch (error) {
          # Mark test as failed
          ${recordTestResult name "failed" error}

          # Still collect evidence on failure
          throw error;
        } finally {
          # Collect all evidence
          ${collectAllEvidence name evidenceCollectors}
        }
      '';
    };
  };

  # Evidence collection functions
  initializeEvidenceCollection = testName: ''
    # Create evidence directories
    mkdir -p /tmp/evidence/${testName}/{logs,metrics,outputs,screenshots}

    # Record test start
    echo '{"test": "${testName}", "start_time": "'$(date -Iseconds)'", "status": "running"}' > /tmp/evidence/${testName}/test-metadata.json
  '';

  recordTestResult = testName: status: error: ''
    # Update test metadata
    jq '.status = "${status}" | .end_time = "'$(date -Iseconds)'" ${if error != null then '| .error = "${error}"' else ''} /tmp/evidence/${testName}/test-metadata.json > /tmp/evidence/${testName}/test-metadata-new.json
    mv /tmp/evidence/${testName}/test-metadata-new.json /tmp/evidence/${testName}/test-metadata.json
  '';

  collectAllEvidence = testName: collectors: ''
    # Run all evidence collectors
    ${lib.concatMapStrings (collector: ''
      echo "Running evidence collector: ${collector.name}"
      ${collector.script testName}
    '') collectors}

    # Package evidence
    tar -czf /tmp/${testName}-evidence.tar.gz -C /tmp/evidence/${testName} .
  '';

  # Standard evidence collectors
  standardCollectors = {
    # System logs collector
    systemLogs = testName: ''
      # Collect all systemd journals
      journalctl --since "1 hour ago" > /tmp/evidence/${testName}/logs/system-journal.log

      # Collect service-specific logs
      for service in $(systemctl list-units --type=service --state=active --no-legend | awk '{print $1}'); do
        journalctl -u "$service" --since "1 hour ago" > "/tmp/evidence/${testName}/logs/service-$service.log" 2>/dev/null || true
      done
    '';

    # System metrics collector
    systemMetrics = testName: ''
      # Collect system performance metrics
      cat > /tmp/evidence/${testName}/metrics/system-info.json << EOF
      {
        "hostname": "$(hostname)",
        "kernel": "$(uname -r)",
        "uptime": "$(uptime)",
        "load_average": "$(uptime | awk -F'load average:' '{ print $2 }')",
        "memory": $(free -m | jq -R -s 'split("\n") | .[1] | split(" ") | map(select(. != "")) | {"total": .[0], "used": .[1], "free": .[2], "shared": .[3], "buff_cache": .[4], "available": .[5]}'),
        "disk": $(df -h / | jq -R -s 'split("\n") | .[1] | split(" ") | map(select(. != "")) | {"filesystem": .[0], "size": .[1], "used": .[2], "avail": .[3], "use_percent": .[4], "mounted": .[5]}'),
        "network_interfaces": $(ip -j addr show | jq 'map({name: .ifname, state: .operstate, addresses: .addr_info | map(.local)})'),
        "timestamp": "$(date -Iseconds)"
      }
      EOF
    '';

    # Service status collector
    serviceStatus = testName: ''
      # Collect service status information
      systemctl list-units --type=service --all --no-legend > /tmp/evidence/${testName}/logs/service-status.txt
      systemctl list-units --type=service --failed --no-legend > /tmp/evidence/${testName}/logs/failed-services.txt

      # Collect service configurations
      mkdir -p /tmp/evidence/${testName}/configs
      for service in $(systemctl list-units --type=service --state=active --no-legend | awk '{print $1}' | sed 's/\.service$//'); do
        systemctl cat "$service" > "/tmp/evidence/${testName}/configs/$service.service" 2>/dev/null || true
      done
    '';

    # Network configuration collector
    networkConfig = testName: ''
      # Collect network configuration
      ip addr show > /tmp/evidence/${testName}/logs/ip-addr.txt
      ip route show > /tmp/evidence/${testName}/logs/ip-routes.txt
      ip neigh show > /tmp/evidence/${testName}/logs/arp-table.txt

      # Collect firewall rules
      iptables -L -n > /tmp/evidence/${testName}/logs/iptables.txt 2>/dev/null || true
      nft list ruleset > /tmp/evidence/${testName}/logs/nftables.txt 2>/dev/null || true

      # Collect DNS configuration
      cat /etc/resolv.conf > /tmp/evidence/${testName}/configs/resolv.conf 2>/dev/null || true
    '';

    # Application-specific evidence collector
    applicationEvidence = apps: testName: lib.concatMapStrings (app: ''
      case "${app}" in
        "dns")
          # DNS-specific evidence
          dig @localhost example.com > /tmp/evidence/${testName}/outputs/dns-query.txt 2>/dev/null || true
          ;;
        "dhcp")
          # DHCP-specific evidence
          ;;
        "web")
          # Web server evidence
          curl -I http://localhost/ > /tmp/evidence/${testName}/outputs/web-response.txt 2>/dev/null || true
          ;;
      esac
    '') apps;
  };

in {
  inherit mkStandardTest standardCollectors;

  # Predefined test templates
  templates = {
    # Basic service test template
    serviceTest = { service, ports ? [], extraConfig ? {}, evidenceCollectors ? [] }:
      mkStandardTest {
        name = "${service}-test";
        description = "Test ${service} service functionality";
        feature = service;
        category = "service";
        nodes = {
          server = { config, pkgs, ... }: {
            services.${service}.enable = true;
            # Apply extra config
          } // extraConfig;
        };
        testScript = ''
          server.wait_for_unit("${service}.service")
          server.succeed("systemctl is-active ${service}.service")

          # Test service functionality
          ${lib.concatMapStrings (port: ''
            server.succeed("ss -tln | grep :${toString port}")
          '') ports}
        '';
        evidenceCollectors = [ standardCollectors.systemLogs standardCollectors.serviceStatus ] ++ evidenceCollectors;
      };

    # Network feature test template
    networkTest = { feature, clientCount ? 1, extraConfig ? {}, evidenceCollectors ? [] }:
      mkStandardTest {
        name = "${feature}-network-test";
        description = "Test ${feature} network functionality";
        feature = feature;
        category = "networking";
        nodes =
          let
            serverNode = {
              services.gateway.enable = true;
              services.gateway.${feature}.enable = true;
            } // extraConfig;

            clientNodes = lib.genAttrs (lib.range 1 clientCount) (i: {
              networking.useDHCP = true;
            });
          in
          { server = serverNode; } // clientNodes;

        testScript = ''
          # Start all nodes
          start_all()

          # Test basic connectivity
          ${lib.concatMapStrings (i: ''
            client${toString i}.wait_for_unit("network-online.target")
            client${toString i}.succeed("ping -c 3 server")
          '') (lib.range 1 clientCount)}

          # Test feature-specific functionality
          # (To be customized per feature)
        '';
        evidenceCollectors = [ standardCollectors.systemLogs standardCollectors.networkConfig ] ++ evidenceCollectors;
      };

    # Security feature test template
    securityTest = { feature, attackVectors ? [], extraConfig ? {}, evidenceCollectors ? [] }:
      mkStandardTest {
        name = "${feature}-security-test";
        description = "Test ${feature} security functionality";
        feature = feature;
        category = "security";
        nodes = {
          server = {
            services.gateway.enable = true;
            services.gateway.${feature}.enable = true;
          } // extraConfig;

          attacker = {
            # Attacker node for testing security
            environment.systemPackages = with pkgs; [ nmap curl ];
          };
        };
        testScript = ''
          start_all()

          # Test security feature is active
          server.succeed("systemctl is-active ${feature}.service")

          # Test attack vectors are blocked
          ${lib.concatMapStrings (vector: ''
            # Test specific attack vector
            attacker.fail("${vector}")
          '') attackVectors}

          # Verify security logs
          server.succeed("journalctl -u ${feature}.service --since '5 minutes ago' | grep -q 'security\\|attack\\|block'")
        '';
        evidenceCollectors = [ standardCollectors.systemLogs standardCollectors.serviceStatus ] ++ evidenceCollectors;
      };
  };
}
```

## Test Execution and Evidence Collection

```bash
#!/usr/bin/env bash
# scripts/run-standardized-test.sh

set -euo pipefail

TEST_FILE="$1"
EVIDENCE_DIR="${2:-evidence/$(basename "$TEST_FILE" .nix)}"

echo "Running standardized test: $TEST_FILE"

# Create evidence directory
mkdir -p "$EVIDENCE_DIR"

# Run the test
if nix build ".#checks.x86_64-linux.$(basename "$TEST_FILE" .nix)"; then
  echo "✅ Test passed"

  # Copy evidence from test result
  if [ -f "result/test-evidence.tar.gz" ]; then
    cp result/test-evidence.tar.gz "$EVIDENCE_DIR/"
    cd "$EVIDENCE_DIR"
    tar -xzf test-evidence.tar.gz
    rm test-evidence.tar.gz
  fi

  # Generate test report
  cat > "$EVIDENCE_DIR/test-report.json" << EOF
  {
    "test_file": "$TEST_FILE",
    "execution_time": "$(date -Iseconds)",
    "result": "passed",
    "evidence_collected": $(find . -type f | wc -l),
    "evidence_size": $(du -sh . | cut -f1)
  }
  EOF

else
  echo "❌ Test failed"

  # Still collect any available evidence
  if [ -f "result/test-evidence.tar.gz" ]; then
    cp result/test-evidence.tar.gz "$EVIDENCE_DIR/"
    cd "$EVIDENCE_DIR"
    tar -xzf test-evidence.tar.gz 2>/dev/null || true
  fi

  # Generate failure report
  cat > "$EVIDENCE_DIR/test-report.json" << EOF
  {
    "test_file": "$TEST_FILE",
    "execution_time": "$(date -Iseconds)",
    "result": "failed",
    "evidence_collected": $(find . -type f 2>/dev/null | wc -l || echo "0"),
    "error_logged": true
  }
  EOF

  exit 1
fi

echo "Evidence collected in: $EVIDENCE_DIR"
```

## Integration with Existing Tests

```bash
#!/usr/bin/env bash
# scripts/wrap-existing-test.sh

set -euo pipefail

ORIGINAL_TEST="$1"
FEATURE_NAME="$2"
CATEGORY="$3"

echo "Wrapping existing test: $ORIGINAL_TEST"

# Create wrapped test
cat > "tests/${FEATURE_NAME}-standardized.nix" << EOF
{ lib, ... }:

let
  standardizedTest = import ../lib/standardized-test-framework.nix { inherit lib; };
  originalTest = import ./${ORIGINAL_TEST};

in
standardizedTest.mkStandardTest {
  name = "${FEATURE_NAME}-standardized";
  description = "Standardized test for ${FEATURE_NAME} with evidence collection";
  feature = "${FEATURE_NAME}";
  category = "${CATEGORY}";
  nodes = originalTest.nodes;
  testScript = originalTest.testScript;
  evidenceCollectors = with standardizedTest.standardCollectors; [
    systemLogs
    systemMetrics
    serviceStatus
    networkConfig
  ];
  tags = [ "standardized" "${CATEGORY}" ];
}
EOF

echo "Created standardized wrapper: tests/${FEATURE_NAME}-standardized.nix"
```

This standardized test framework provides:

1. **Consistent Structure**: All tests follow the same pattern
2. **Evidence Collection**: Automatic gathering of logs, metrics, and outputs
3. **Result Tracking**: Comprehensive pass/fail reporting with metadata
4. **Integration**: Easy wrapping of existing tests
5. **Extensibility**: Custom evidence collectors for specific features
6. **CI/CD Ready**: Structured output for automated processing
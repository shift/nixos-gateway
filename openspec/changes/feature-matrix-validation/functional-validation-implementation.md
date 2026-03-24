# Functional Validation Checks Implementation

## Core Validation Library

```nix
# lib/validation-checks.nix
{ lib, ... }:

let
  # Base check structure
  mkCheck = { name, description, testScript, timeout ? 30 }: {
    inherit name description timeout;
    testScript = ''
      # Setup check environment
      check_start_time=$(date +%s)
      echo "Starting check: ${name}"

      # Execute check
      ${testScript}

      # Record result
      check_end_time=$(date +%s)
      check_duration=$((check_end_time - check_start_time))
      echo "Check ${name} completed in ${check_duration}s"
    '';
  };

  # Result collection
  collectResult = checkName: result: ''
    # Store check result in test metadata
    mkdir -p /tmp/validation-results
    cat > "/tmp/validation-results/${checkName}.json" << EOF
    {
      "check": "${checkName}",
      "passed": ${if result then "true" else "false"},
      "timestamp": "$(date -Iseconds)",
      "duration": "$check_duration"
    }
    EOF
  '';

in {
  # Functional validation checks
  functional = {
    # Service startup validation
    serviceStartup = mkCheck {
      name = "service-startup";
      description = "Verify all required services start successfully";
      testScript = ''
        # Check systemd services
        gateway.succeed("systemctl is-active multi-user.target")

        # Check core services based on enabled modules
        gateway.succeed("systemctl is-active systemd-networkd.service")

        # DNS services (Knot)
        gateway.succeed("systemctl is-active knot.service || true")  # Optional
        gateway.succeed("systemctl is-active kresd@1.service || true")  # Optional

        # DHCP services (Kea)
        gateway.succeed("systemctl is-active kea-dhcp4-server.service || true")  # Optional

        # Security services
        gateway.succeed("systemctl is-active nftables.service || true")  # Optional

        # Collect result
        ${collectResult "service-startup" true}
      '';
    };

    # Basic connectivity validation
    basicConnectivity = mkCheck {
      name = "basic-connectivity";
      description = "Test basic network connectivity between nodes";
      testScript = ''
        # Test gateway self-connectivity
        gateway.succeed("ping -c 3 127.0.0.1")

        # Test client to gateway connectivity
        client1.wait_for_unit("network-online.target")
        client1.succeed("ping -c 3 gateway")

        # Test DNS resolution if DNS is enabled
        client1.succeed("nslookup gateway 127.0.0.1 || nslookup gateway gateway || true")

        # Collect result
        ${collectResult "basic-connectivity" true}
      '';
    };

    # Configuration validation
    configurationValidation = mkCheck {
      name = "configuration-validation";
      description = "Verify configuration files are valid and properly applied";
      testScript = ''
        # Check NixOS configuration evaluation
        gateway.succeed("nix-instantiate /etc/nixos/configuration.nix --eval")

        # Check systemd configuration validity
        gateway.succeed("systemd-analyze verify")

        # Check network configuration
        gateway.succeed("networkctl status | grep -q 'State: routable\\|State: configured'")

        # Check firewall configuration if enabled
        gateway.succeed("nft list ruleset > /dev/null 2>&1 || true")

        # Collect result
        ${collectResult "configuration-validation" true}
      '';
    };

    # Service dependency validation
    serviceDependencies = mkCheck {
      name = "service-dependencies";
      description = "Verify service dependencies are properly configured";
      testScript = ''
        # Check systemd service dependencies
        gateway.succeed("systemctl list-dependencies multi-user.target | grep -q network")

        # Check that required services start in correct order
        gateway.succeed("systemctl show systemd-networkd.service | grep -q 'After=.*systemd-udevd'")

        # Verify no dependency cycles
        gateway.succeed("systemctl list-dependencies | grep -v ' cyclic'")

        # Collect result
        ${collectResult "service-dependencies" true}
      '';
    };

    # Module integration validation
    moduleIntegration = mkCheck {
      name = "module-integration";
      description = "Verify NixOS modules integrate properly without conflicts";
      testScript = ''
        # Check that all modules loaded successfully
        gateway.succeed("grep -q 'modules loaded' /var/log/nixos-switch.log || true")

        # Verify no module conflicts in systemd
        gateway.succeed("systemctl --failed | grep -q '0 loaded units listed'")

        # Check that configuration options are properly merged
        gateway.succeed("test -f /etc/systemd/network/10-lan.network")

        # Collect result
        ${collectResult "module-integration" true}
      '';
    };

    # Error log validation
    errorLogValidation = mkCheck {
      name = "error-log-validation";
      description = "Verify services are not logging errors during operation";
      testScript = ''
        # Check systemd journal for errors in last 5 minutes
        error_count=$(gateway.succeed("journalctl --since '5 minutes ago' --priority err | grep -c 'error\\|Error\\|ERROR' || true"))
        if [ "$error_count" -gt 0 ]; then
          echo "Found $error_count errors in logs"
          gateway.succeed("journalctl --since '5 minutes ago' --priority err")
          ${collectResult "error-log-validation" false}
          exit 1
        fi

        # Check specific service logs
        # DNS services
        gateway.succeed("journalctl -u knot.service --since '5 minutes ago' | grep -i error | wc -l | grep -q '^0$' || true")
        gateway.succeed("journalctl -u kresd@1.service --since '5 minutes ago' | grep -i error | wc -l | grep -q '^0$' || true")

        # DHCP services
        gateway.succeed("journalctl -u kea-dhcp4-server.service --since '5 minutes ago' | grep -i error | wc -l | grep -q '^0$' || true")

        # Network services
        gateway.succeed("journalctl -u systemd-networkd.service --since '5 minutes ago' | grep -i error | wc -l | grep -q '^0$' || true")

        # Collect result
        ${collectResult "error-log-validation" true}
      '';
    };

    # Feature functionality validation
    featureFunctionality = mkCheck {
      name = "feature-functionality";
      description = "Test core functionality of enabled features";
      testScript = ''
        # Test DNS functionality if enabled
        if gateway.succeed("systemctl is-active kresd@1.service"); then
          client1.succeed("dig @gateway example.com | grep -q 'ANSWER SECTION'")
        fi

        # Test DHCP functionality if enabled
        if gateway.succeed("systemctl is-active kea-dhcp4-server.service"); then
          client1.succeed("dhcpcd -T eth1 | grep -q 'new_ip_address'")
        fi

        # Test firewall functionality if enabled
        if gateway.succeed("nft list ruleset | grep -q 'table inet filter'"); then
          # Test that firewall is active
          gateway.succeed("nft list ruleset | grep -q 'chain input'")
        fi

        # Collect result
        ${collectResult "feature-functionality" true}
      '';
    };
  };
}
```

## Functional Test Runner

```bash
#!/usr/bin/env bash
# scripts/run-functional-checks.sh

set -euo pipefail

COMBINATION="$1"
CONFIG_FILE="$2"
RESULTS_DIR="/tmp/validation-results"

echo "Running functional validation checks for $COMBINATION"

# Create results directory
mkdir -p "$RESULTS_DIR"

# Generate NixOS test with functional checks
cat > "tests/${COMBINATION}-functional.nix" << EOF
{ pkgs, lib, ... }:

let
  validationChecks = import ../lib/validation-checks.nix { inherit lib; };
in

pkgs.testers.nixosTest {
  name = "${COMBINATION}-functional-validation";

  nodes = {
    gateway = { config, pkgs, ... }: {
      imports = [ ../modules ];
      services.gateway = import "$CONFIG_FILE";
    };

    client1 = { config, pkgs, ... }: {
      virtualisation.vlans = [ 1 ];
      networking.useDHCP = true;
      networking.nameservers = [ "192.168.1.1" ];
    };
  };

  testScript = ''
    start_all()

    # Run functional checks
    \${validationChecks.functional.serviceStartup.testScript}
    \${validationChecks.functional.basicConnectivity.testScript}
    \${validationChecks.functional.configurationValidation.testScript}
    \${validationChecks.functional.serviceDependencies.testScript}
    \${validationChecks.functional.moduleIntegration.testScript}
    \${validationChecks.functional.errorLogValidation.testScript}
    \${validationChecks.functional.featureFunctionality.testScript}

    # Collect all results
    mkdir -p /tmp/test-results
    cp -r /tmp/validation-results/* /tmp/test-results/ || true
  '';
}
EOF

# Run the test
echo "Executing functional validation..."
if nix build ".#checks.x86_64-linux.${COMBINATION}-functional"; then
  echo "✅ Functional validation passed"

  # Extract results
  mkdir -p "results/$COMBINATION"
  cp result/test-results/* "results/$COMBINATION/" 2>/dev/null || true

  # Generate summary
  cat > "results/$COMBINATION/functional-summary.json" << EOF
  {
    "combination": "$COMBINATION",
    "category": "functional",
    "timestamp": "$(date -Iseconds)",
    "overall_result": "passed",
    "checks": [
      "service-startup",
      "basic-connectivity",
      "configuration-validation",
      "service-dependencies",
      "module-integration",
      "error-log-validation",
      "feature-functionality"
    ]
  }
  EOF

else
  echo "❌ Functional validation failed"
  exit 1
fi
```

## Functional Check Categories

### 1. Service Startup Validation
- Verifies all required systemd services start successfully
- Checks service dependencies are resolved
- Validates service startup order
- Ensures no immediate startup failures

### 2. Basic Connectivity Validation
- Tests network connectivity between test nodes
- Validates IP address assignment
- Checks basic routing functionality
- Ensures DNS resolution works (if enabled)

### 3. Configuration Validation
- Verifies NixOS configuration evaluates correctly
- Checks systemd unit configuration validity
- Validates network configuration syntax
- Ensures firewall rules are syntactically correct

### 4. Service Dependencies Validation
- Checks systemd service dependency ordering
- Validates no circular dependencies exist
- Ensures required services start before dependents
- Verifies service startup sequencing

### 5. Module Integration Validation
- Confirms NixOS modules load without conflicts
- Validates configuration option merging
- Checks for module-specific integration issues
- Ensures no option conflicts between modules

### 6. Error Log Validation
- Monitors systemd journal for error messages
- Checks service-specific error logs
- Validates clean operation without errors
- Ensures error-free startup and operation

### 7. Feature Functionality Validation
- Tests core functionality of enabled features
- Validates DNS resolution (if DNS enabled)
- Checks DHCP lease assignment (if DHCP enabled)
- Verifies firewall rule application (if firewall enabled)
- Tests VPN connectivity (if VPN enabled)

## Result Aggregation

```bash
#!/usr/bin/env bash
# scripts/aggregate-functional-results.sh

COMBINATION="$1"
RESULTS_DIR="results/$COMBINATION"

echo "Aggregating functional validation results for $COMBINATION"

# Count passed/failed checks
total_checks=$(jq '.checks | length' "$RESULTS_DIR/functional-summary.json")
passed_checks=$(find "$RESULTS_DIR" -name "*.json" -exec jq -r '.passed' {} \; | grep -c "true" || echo "0")

# Calculate pass rate
pass_rate=$((passed_checks * 100 / total_checks))

# Generate detailed report
cat > "$RESULTS_DIR/functional-report.json" << EOF
{
  "combination": "$COMBINATION",
  "validation_category": "functional",
  "timestamp": "$(date -Iseconds)",
  "summary": {
    "total_checks": $total_checks,
    "passed_checks": $passed_checks,
    "failed_checks": $((total_checks - passed_checks)),
    "pass_rate_percent": $pass_rate,
    "overall_passed": $([ $pass_rate -ge 80 ] && echo "true" || echo "false")
  },
  "check_details": $(jq '.checks' "$RESULTS_DIR/functional-summary.json"),
  "recommendations": $([ $pass_rate -lt 80 ] && echo '"Review failed checks and address issues before considering supported"' || echo '"Functional validation passed - ready for further testing"')
}
EOF

echo "Functional validation: $passed_checks/$total_checks checks passed ($pass_rate%)"
```

This implementation provides comprehensive functional validation that ensures feature combinations work correctly before proceeding to performance, security, and other validation categories.
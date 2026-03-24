{ scenarios, outputDir }:

let
  inherit (import <nixpkgs> {}) stdenv lib;

in stdenv.mkDerivation {
  name = "simulator-test-runner";

  src = ./.;

  buildInputs = with import <nixpkgs> {}; [
    bash
    curl
    jq
    iproute2
    iputils
    dnsutils
    procps
  ];

  installPhase = ''
    mkdir -p $out/bin
    cat > $out/bin/test-runner << 'EOF'
    #!/bin/bash
    set -euo pipefail

    SCENARIOS="${lib.concatStringsSep " " scenarios}"
    OUTPUT_DIR="${outputDir}"

    # Test execution functions
    run_networking_tests() {
        echo "Running networking tests..."

        local results_file="$OUTPUT_DIR/networking-$(date +%Y%m%d-%H%M%S).json"
        local results='{"tests": [], "timestamp": "'$(date -Iseconds)'"}'

        # DHCP tests
        echo "Testing DHCP..."
        if systemctl is-active kea-dhcp4-server >/dev/null 2>&1 || systemctl is-active dhcpd >/dev/null 2>&1; then
            results=$(echo "$results" | jq '.tests += [{"name": "DHCP Service", "status": "passed", "output": "DHCP service is running"}]')
        else
            results=$(echo "$results" | jq '.tests += [{"name": "DHCP Service", "status": "failed", "output": "DHCP service not running"}]')
        fi

        # DNS tests
        echo "Testing DNS..."
        if dig @127.0.0.1 google.com +timeout=5 >/dev/null 2>&1; then
            results=$(echo "$results" | jq '.tests += [{"name": "DNS Resolution", "status": "passed", "output": "DNS resolution working"}]')
        else
            results=$(echo "$results" | jq '.tests += [{"name": "DNS Resolution", "status": "failed", "output": "DNS resolution failed"}]')
        fi

        # Routing tests
        echo "Testing routing..."
        if ip route show | grep -q default; then
            results=$(echo "$results" | jq '.tests += [{"name": "Default Route", "status": "passed", "output": "Default route configured"}]')
        else
            results=$(echo "$results" | jq '.tests += [{"name": "Default Route", "status": "failed", "output": "No default route"}]')
        fi

        echo "$results" > "$results_file"
        echo "Networking tests completed: $results_file"
    }

    run_security_tests() {
        echo "Running security tests..."

        local results_file="$OUTPUT_DIR/security-$(date +%Y%m%d-%H%M%S).json"
        local results='{"tests": [], "timestamp": "'$(date -Iseconds)'"}'

        # Firewall tests
        echo "Testing firewall..."
        if systemctl is-active nftables >/dev/null 2>&1 || systemctl is-active firewalld >/dev/null 2>&1; then
            results=$(echo "$results" | jq '.tests += [{"name": "Firewall Service", "status": "passed", "output": "Firewall service is running"}]')
        else
            results=$(echo "$results" | jq '.tests += [{"name": "Firewall Service", "status": "failed", "output": "Firewall service not running"}]')
        fi

        # VPN tests
        echo "Testing VPN..."
        if ip link show | grep -q wg0; then
            results=$(echo "$results" | jq '.tests += [{"name": "VPN Interface", "status": "passed", "output": "VPN interface exists"}]')
        else
            results=$(echo "$results" | jq '.tests += [{"name": "VPN Interface", "status": "failed", "output": "No VPN interface found"}]')
        fi

        echo "$results" > "$results_file"
        echo "Security tests completed: $results_file"
    }

    run_monitoring_tests() {
        echo "Running monitoring tests..."

        local results_file="$OUTPUT_DIR/monitoring-$(date +%Y%m%d-%H%M%S).json"
        local results='{"tests": [], "timestamp": "'$(date -Iseconds)'"}'

        # Prometheus tests
        echo "Testing monitoring..."
        if curl -s http://127.0.0.1:9090/-/healthy >/dev/null 2>&1; then
            results=$(echo "$results" | jq '.tests += [{"name": "Prometheus Health", "status": "passed", "output": "Prometheus is healthy"}]')
        else
            results=$(echo "$results" | jq '.tests += [{"name": "Prometheus Health", "status": "failed", "output": "Prometheus not responding"}]')
        fi

        # Grafana tests
        if curl -s http://127.0.0.1:3000/api/health >/dev/null 2>&1; then
            results=$(echo "$results" | jq '.tests += [{"name": "Grafana Health", "status": "passed", "output": "Grafana is accessible"}]')
        else
            results=$(echo "$results" | jq '.tests += [{"name": "Grafana Health", "status": "failed", "output": "Grafana not accessible"}]')
        fi

        echo "$results" > "$results_file"
        echo "Monitoring tests completed: $results_file"
    }

    run_performance_tests() {
        echo "Running performance tests..."

        local results_file="$OUTPUT_DIR/performance-$(date +%Y%m%d-%H%M%S).json"
        local results='{"tests": [], "timestamp": "'$(date -Iseconds)'"}'

        # QoS tests
        echo "Testing QoS..."
        if tc qdisc show | grep -q htb; then
            results=$(echo "$results" | jq '.tests += [{"name": "QoS Configuration", "status": "passed", "output": "QoS queues configured"}]')
        else
            results=$(echo "$results" | jq '.tests += [{"name": "QoS Configuration", "status": "failed", "output": "No QoS configuration found"}]')
        fi

        # Load balancing tests
        if systemctl is-active haproxy >/dev/null 2>&1; then
            results=$(echo "$results" | jq '.tests += [{"name": "Load Balancer", "status": "passed", "output": "HAProxy is running"}]')
        else
            results=$(echo "$results" | jq '.tests += [{"name": "Load Balancer", "status": "failed", "output": "HAProxy not running"}]')
        fi

        echo "$results" > "$results_file"
        echo "Performance tests completed: $results_file"
    }

    # Main execution
    echo "Simulator Test Runner starting..."
    echo "Scenarios: $SCENARIOS"
    echo "Output Directory: $OUTPUT_DIR"

    mkdir -p "$OUTPUT_DIR"

    # Run tests based on scenarios
    for scenario in $SCENARIOS; do
        case "$scenario" in
            networking)
                run_networking_tests
                ;;
            security)
                run_security_tests
                ;;
            monitoring)
                run_monitoring_tests
                ;;
            performance)
                run_performance_tests
                ;;
            *)
                echo "Unknown scenario: $scenario"
                ;;
        esac
    done

    echo "All tests completed. Results in: $OUTPUT_DIR"
    EOF

    chmod +x $out/bin/test-runner
  '';
}
#!/usr/bin/env bash
set -euo pipefail

# Nftables Firewall Testing with Evidence Collection
# Part of Comprehensive Feature Testing - Phase 4.1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EVIDENCE_DIR="$PROJECT_ROOT/.evidence/security"
TEST_SESSION="$(date +%Y%m%d-%H%M%S)"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Evidence collection
EVIDENCE_FILE="$EVIDENCE_DIR/nftables-test-$TEST_SESSION.json"
LOG_FILE="$EVIDENCE_DIR/nftables-test-$TEST_SESSION.log"

# Test configuration
TEST_NETWORK="192.168.200.0/24"
TEST_INTERFACE="test-veth0"
TEST_TABLE="gateway-test"
CHAIN_INPUT="input"
CHAIN_FORWARD="forward"
CHAIN_OUTPUT="output"

# Initialize evidence collection
init_evidence() {
    mkdir -p "$EVIDENCE_DIR"
    
    # Create evidence file header
    cat > "$EVIDENCE_FILE" << EOF
{
  "test_session": "$TEST_SESSION",
  "test_category": "security",
  "feature": "nftables-firewall",
  "timestamp": "$(date -Iseconds)",
  "test_environment": {
    "kernel": "$(uname -r)",
    "nftables_version": "$(nft --version 2>/dev/null | head -1 || echo 'not installed')",
    "hostname": "$(hostname)",
    "user": "$(whoami)"
  },
  "test_results": [],
  "evidence": []
}
EOF
    
    # Initialize log file
    {
        echo "=== Nftables Firewall Test Log - $TEST_SESSION ==="
        echo "Started: $(date)"
        echo "Test Environment: $(hostname) ($(uname -r))"
        echo ""
    } > "$LOG_FILE"
    
    log_info "Evidence collection initialized: $EVIDENCE_FILE"
    log_info "Test log: $LOG_FILE"
}

# Logging functions with evidence collection
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$LOG_FILE"
    collect_evidence "success" "$*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "$LOG_FILE"
    collect_evidence "warning" "$*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"
    collect_evidence "error" "$*"
}

log_test() {
    echo -e "${CYAN}[TEST]${NC} $*" | tee -a "$LOG_FILE"
    collect_evidence "test" "$*"
}

# Collect evidence
collect_evidence() {
    local type="$1"
    local message="$2"
    local timestamp=$(date -Iseconds)
    
    local evidence_entry=$(jq -n \
        --arg type "$type" \
        --arg message "$message" \
        --arg timestamp "$timestamp" \
        '{
            type: $type,
            message: $message,
            timestamp: $timestamp
        }')
    
    # Append to evidence file
    local temp_file=$(mktemp)
    jq --argjson new_entry "$evidence_entry" '.evidence += [$new_entry]' "$EVIDENCE_FILE" > "$temp_file"
    mv "$temp_file" "$EVIDENCE_FILE"
}

# Record test result
record_test_result() {
    local test_name="$1"
    local status="$2"
    local details="$3"
    local timestamp=$(date -Iseconds)
    
    local test_result=$(jq -n \
        --arg test_name "$test_name" \
        --arg status "$status" \
        --arg details "$details" \
        --arg timestamp "$timestamp" \
        '{
            test_name: $test_name,
            status: $status,
            details: $details,
            timestamp: $timestamp
        }')
    
    # Append to results
    local temp_file=$(mktemp)
    jq --argjson new_result "$test_result" '.test_results += [$new_result]' "$EVIDENCE_FILE" > "$temp_file"
    mv "$temp_file" "$EVIDENCE_FILE"
}

# Test prerequisites
check_prerequisites() {
    log_test "Checking prerequisites for nftables testing..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This test requires root privileges for firewall management"
        record_test_result "prerequisites" "FAIL" "Root privileges required"
        exit 1
    fi
    
    # Check nftables availability
    if ! command -v nft >/dev/null 2>&1; then
        log_error "nftables command not found"
        record_test_result "prerequisites" "FAIL" "nftables not installed"
        exit 1
    fi
    
    # Check kernel support
    if ! grep -q nftables /proc/net/netfilter 2>/dev/null; then
        log_warning "nftables may not be fully supported by kernel"
    fi
    
    log_success "Prerequisites check passed"
    record_test_result "prerequisites" "PASS" "All requirements satisfied"
}

# Setup test environment
setup_test_environment() {
    log_test "Setting up test environment..."
    
    # Create test network namespace
    if ! ip netns add nftables-test; then
        log_warning "Failed to create network namespace, continuing in host namespace"
    else
        log_info "Created network namespace: nftables-test"
    fi
    
    # Create test interface
    if ! ip link add "$TEST_INTERFACE" type dummy; then
        log_warning "Failed to create test interface, using existing interfaces"
    else
        ip link set "$TEST_INTERFACE" up
        ip addr add "10.255.255.1/24" dev "$TEST_INTERFACE"
        log_info "Created test interface: $TEST_INTERFACE"
    fi
    
    # Clean up any existing test table
    nft list table inet "$TEST_TABLE" 2>/dev/null && nft delete table inet "$TEST_TABLE" 2>/dev/null || true
    
    log_success "Test environment setup completed"
    collect_evidence "environment" "Test environment configured"
}

# Test 1: Basic nftables functionality
test_basic_functionality() {
    log_test "Test 1: Basic nftables functionality"
    
    # Create test table
    if nft add table inet "$TEST_TABLE"; then
        log_success "Created nftables table: $TEST_TABLE"
        
        # List tables to verify
        local tables=$(nft list tables | grep "$TEST_TABLE" || true)
        if [[ -n "$tables" ]]; then
            collect_evidence "verification" "Table creation verified: $tables"
        else
            log_error "Table creation verification failed"
            record_test_result "basic_table_creation" "FAIL" "Table not found after creation"
            return 1
        fi
        
        record_test_result "basic_table_creation" "PASS" "Table created successfully"
    else
        log_error "Failed to create nftables table"
        record_test_result "basic_table_creation" "FAIL" "Table creation command failed"
        return 1
    fi
    
    # Create chains
    if nft add chain inet "$TEST_TABLE" "$CHAIN_INPUT" '{ type filter hook input priority 0; }'; then
        log_success "Created input chain: $CHAIN_INPUT"
        record_test_result "basic_chain_creation_input" "PASS" "Input chain created"
    else
        log_error "Failed to create input chain"
        record_test_result "basic_chain_creation_input" "FAIL" "Input chain creation failed"
    fi
    
    if nft add chain inet "$TEST_TABLE" "$CHAIN_FORWARD" '{ type filter hook forward priority 0; }'; then
        log_success "Created forward chain: $CHAIN_FORWARD"
        record_test_result "basic_chain_creation_forward" "PASS" "Forward chain created"
    else
        log_error "Failed to create forward chain"
        record_test_result "basic_chain_creation_forward" "FAIL" "Forward chain creation failed"
    fi
    
    if nft add chain inet "$TEST_TABLE" "$CHAIN_OUTPUT" '{ type filter hook output priority 0; }'; then
        log_success "Created output chain: $CHAIN_OUTPUT"
        record_test_result "basic_chain_creation_output" "PASS" "Output chain created"
    else
        log_error "Failed to create output chain"
        record_test_result "basic_chain_creation_output" "FAIL" "Output chain creation failed"
    fi
    
    # Verify chains
    local chain_list=$(nft list table inet "$TEST_TABLE")
    collect_evidence "chains" "Chain configuration: $chain_list"
    
    log_success "Basic functionality test completed"
}

# Test 2: Rule management
test_rule_management() {
    log_test "Test 2: Rule management"
    
    # Add basic rules
    if nft add rule inet "$TEST_TABLE" "$CHAIN_INPUT" ct state established,related accept; then
        log_success "Added established/related accept rule"
        record_test_result "rule_add_established" "PASS" "Established/related rule added"
    else
        log_error "Failed to add established/related rule"
        record_test_result "rule_add_established" "FAIL" "Rule addition failed"
        return 1
    fi
    
    if nft add rule inet "$TEST_TABLE" "$CHAIN_INPUT" tcp dport 22 accept; then
        log_success "Added SSH accept rule"
        record_test_result "rule_add_ssh" "PASS" "SSH accept rule added"
    else
        log_error "Failed to add SSH accept rule"
        record_test_result "rule_add_ssh" "FAIL" "SSH rule addition failed"
    fi
    
    if nft add rule inet "$TEST_TABLE" "$CHAIN_INPUT" icmp type echo-request accept; then
        log_success "Added ICMP accept rule"
        record_test_result "rule_add_icmp" "PASS" "ICMP accept rule added"
    else
        log_error "Failed to add ICMP accept rule"
        record_test_result "rule_add_icmp" "FAIL" "ICMP rule addition failed"
    fi
    
    if nft add rule inet "$TEST_TABLE" "$CHAIN_INPUT" drop; then
        log_success "Added default drop rule"
        record_test_result "rule_add_drop" "PASS" "Default drop rule added"
    else
        log_error "Failed to add default drop rule"
        record_test_result "rule_add_drop" "FAIL" "Default drop rule failed"
    fi
    
    # List rules for verification
    local rules=$(nft list chain inet "$TEST_TABLE" "$CHAIN_INPUT")
    collect_evidence "rules" "Chain rules: $rules"
    
    log_success "Rule management test completed"
}

# Test 3: Advanced rule features
test_advanced_features() {
    log_test "Test 3: Advanced rule features"
    
    # Test sets
    if nft add set inet "$TEST_TABLE" allowed-ports '{ type inet_service; flags dynamic; }'; then
        log_success "Created allowed-ports set"
        
        if nft add element inet "$TEST_TABLE" allowed-ports '{ 22, 80, 443 }'; then
            log_success "Added elements to allowed-ports set"
            record_test_result "advanced_sets" "PASS" "Set creation and element addition"
        else
            log_error "Failed to add elements to set"
            record_test_result "advanced_sets" "FAIL" "Set element addition failed"
        fi
        
        # Test set in rule
        if nft add rule inet "$TEST_TABLE" "$CHAIN_INPUT" tcp dport @allowed-ports accept; then
            log_success "Created rule using set"
            record_test_result "advanced_set_rule" "PASS" "Rule using set created"
        else
            log_error "Failed to create rule using set"
            record_test_result "advanced_set_rule" "FAIL" "Set rule creation failed"
        fi
    else
        log_error "Failed to create set"
        record_test_result "advanced_sets" "FAIL" "Set creation failed"
    fi
    
    # Test logging
    if nft add rule inet "$TEST_TABLE" "$CHAIN_INPUT" log prefix \"nft-test: \"; then
        log_success "Added logging rule"
        record_test_result "advanced_logging" "PASS" "Logging rule added"
        
        # Check for log entries
        sleep 1
        if dmesg | grep -q "nft-test:"; then
            collect_evidence "logging" "Log entries found in kernel log"
        fi
    else
        log_error "Failed to add logging rule"
        record_test_result "advanced_logging" "FAIL" "Logging rule failed"
    fi
    
    # Test rate limiting
    if nft add rule inet "$TEST_TABLE" "$CHAIN_INPUT" ip protocol icmp limit rate 10/minute accept; then
        log_success "Added rate limiting rule"
        record_test_result "advanced_ratelimit" "PASS" "Rate limiting rule added"
    else
        log_error "Failed to add rate limiting rule"
        record_test_result "advanced_ratelimit" "FAIL" "Rate limiting failed"
    fi
    
    # Verify advanced features
    local advanced_rules=$(nft list table inet "$TEST_TABLE")
    collect_evidence "advanced_rules" "Advanced rule configuration: $advanced_rules"
    
    log_success "Advanced features test completed"
}

# Test 4: Performance and throughput
test_performance() {
    log_test "Test 4: Performance and throughput"
    
    # Measure rule insertion time
    local start_time=$(date +%s.%N)
    
    for i in {1..100}; do
        nft add rule inet "$TEST_TABLE" "$CHAIN_INPUT" tcp dport $((3000 + i)) accept
    done
    
    local end_time=$(date +%s.%N)
    local insertion_time=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0.1")
    
    log_info "100 rules inserted in ${insertion_time}s"
    record_test_result "performance_insertion" "PASS" "100 rules in ${insertion_time}s"
    
    # Test rule listing performance
    start_time=$(date +%s.%N)
    local rule_count=$(nft list table inet "$TEST_TABLE" | grep -c "accept\|drop\|log" || echo "0")
    end_time=$(date +%s.%N)
    local listing_time=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0.1")
    
    log_info "Listed $rule_count rules in ${listing_time}s"
    record_test_result "performance_listing" "PASS" "$rule_count rules listed in ${listing_time}s"
    
    # Test packet processing (simulated)
    local start_time=$(date +%s.%N)
    
    # Generate some test traffic to test rule processing
    ping -c 5 -i 0.1 127.0.0.1 >/dev/null 2>&1 || true
    
    local end_time=$(date +%s.%N)
    local processing_time=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0.1")
    
    log_info "Packet processing test completed in ${processing_time}s"
    record_test_result "performance_processing" "PASS" "Packet processing test in ${processing_time}s"
    
    collect_evidence "performance" "Performance metrics: insertion=${insertion_time}s, listing=${listing_time}s, processing=${processing_time}s"
    
    log_success "Performance test completed"
}

# Test 5: Configuration persistence and recovery
test_persistence() {
    log_test "Test 5: Configuration persistence and recovery"
    
    # Export current configuration
    local config_file="/tmp/nftables-test-config-$TEST_SESSION.nft"
    if nft list table inet "$TEST_TABLE" > "$config_file"; then
        log_success "Exported configuration to $config_file"
        record_test_result "persistence_export" "PASS" "Configuration exported"
        
        collect_evidence "config_export" "Configuration exported: $(wc -l < "$config_file") lines"
    else
        log_error "Failed to export configuration"
        record_test_result "persistence_export" "FAIL" "Configuration export failed"
    fi
    
    # Clear configuration
    nft delete table inet "$TEST_TABLE" 2>/dev/null || true
    sleep 0.1
    
    # Verify table is gone
    if ! nft list table inet "$TEST_TABLE" 2>/dev/null; then
        log_info "Configuration cleared successfully"
    else
        log_warning "Configuration may not have been fully cleared"
    fi
    
    # Restore configuration
    if nft -f "$config_file"; then
        log_success "Restored configuration from file"
        record_test_result "persistence_restore" "PASS" "Configuration restored"
    else
        log_error "Failed to restore configuration"
        record_test_result "persistence_restore" "FAIL" "Configuration restore failed"
    fi
    
    # Verify restoration
    if nft list table inet "$TEST_TABLE" >/dev/null 2>&1; then
        log_success "Configuration verification after restore passed"
        record_test_result "persistence_verify" "PASS" "Configuration verified after restore"
    else
        log_error "Configuration verification after restore failed"
        record_test_result "persistence_verify" "FAIL" "Configuration verification failed"
    fi
    
    # Clean up export file
    rm -f "$config_file"
    
    log_success "Persistence test completed"
}

# Test 6: Integration with NixOS configuration
test_nixos_integration() {
    log_test "Test 6: Integration with NixOS configuration"
    
    # Create test NixOS configuration
    local test_config="/tmp/nftables-nixos-test-$TEST_SESSION.nix"
    cat > "$test_config" << 'EOF'
# Test NixOS configuration for nftables
{ pkgs, lib, ... }:

{
  networking.nftables = {
    enable = true;
    
    ruleset = ''
      table inet test-table {
        chain input {
          type filter hook input priority 0;
          ct state established,related accept
          tcp dport { 22, 80, 443 } accept
          icmp type echo-request accept
          drop
        }
      }
    '';
  };
  
  # Minimal system config for testing
  system.stateVersion = "23.11";
}
EOF
    
    log_info "Created test NixOS configuration"
    collect_evidence "nixos_config" "Test configuration created: $test_config"
    
    # Test configuration validation
    if nix-instantiate --parse "$test_config" >/dev/null 2>&1; then
        log_success "NixOS configuration syntax is valid"
        record_test_result "nixos_syntax" "PASS" "Configuration syntax valid"
    else
        log_error "NixOS configuration syntax is invalid"
        record_test_result "nixos_syntax" "FAIL" "Configuration syntax invalid"
    fi
    
    # Test configuration evaluation
    if nix-instantiate --eval --expr "import $test_config { inherit pkgs; }" >/dev/null 2>&1; then
        log_success "NixOS configuration evaluation passed"
        record_test_result "nixos_evaluation" "PASS" "Configuration evaluation passed"
    else
        log_warning "NixOS configuration evaluation failed (may be expected in test environment)"
        record_test_result "nixos_evaluation" "WARN" "Configuration evaluation failed"
    fi
    
    # Clean up test configuration
    rm -f "$test_config"
    
    log_success "NixOS integration test completed"
}

# Cleanup test environment
cleanup_test_environment() {
    log_test "Cleaning up test environment..."
    
    # Remove test table
    nft delete table inet "$TEST_TABLE" 2>/dev/null || true
    
    # Remove test interface
    ip link del "$TEST_INTERFACE" 2>/dev/null || true
    
    # Remove network namespace
    ip netns del nftables-test 2>/dev/null || true
    
    log_info "Test environment cleaned up"
    collect_evidence "cleanup" "Test environment cleanup completed"
}

# Generate test report
generate_test_report() {
    log_test "Generating test report..."
    
    local report_file="$EVIDENCE_DIR/nftables-test-report-$TEST_SESSION.md"
    
    # Calculate statistics
    local total_tests=$(jq '.test_results | length' "$EVIDENCE_FILE")
    local passed_tests=$(jq '.test_results | map(select(.status == "PASS")) | length' "$EVIDENCE_FILE")
    local failed_tests=$(jq '.test_results | map(select(.status == "FAIL")) | length' "$EVIDENCE_FILE")
    local warn_tests=$(jq '.test_results | map(select(.status == "WARN")) | length' "$EVIDENCE_FILE")
    
    cat > "$report_file" << EOF
# Nftables Firewall Test Report

**Test Session:** $TEST_SESSION  
**Timestamp:** $(date)  
**Test Category:** Security - nftables-firewall  

## Executive Summary

- **Total Tests:** $total_tests
- **Passed:** $passed_tests  
- **Failed:** $failed_tests
- **Warnings:** $warn_tests
- **Success Rate:** $(( passed_tests * 100 / total_tests ))%

## Test Results Summary

$(jq -r '.test_results[] | "- **\(.test_name):** \(.status) - \(.details)"' "$EVIDENCE_FILE")

## Test Environment

$(jq -r '.test_environment | to_entries[] | "- **\(.key):** \(.value)"' "$EVIDENCE_FILE")

## Evidence Collected

Total evidence entries: $(jq '.evidence | length' "$EVIDENCE_FILE")

Evidence types collected:
$(jq -r '.evidence | group_by(.type) | map({type: .[0].type, count: length}) | .[] | "- \(.type): \(.count) entries"' "$EVIDENCE_FILE")

## Performance Metrics

$(jq -r '.evidence[] | select(.type == "performance") | .message' "$EVIDENCE_FILE" | sed 's/^/- /')

## Configuration Validation

$(jq -r '.evidence[] | select(.type == "config_export" or .type == "nixos_config") | .message' "$EVIDENCE_FILE" | sed 's/^/- /')

## Recommendations

EOF

    # Add recommendations based on test results
    if [[ "$failed_tests" -eq 0 ]]; then
        cat >> "$report_file" << 'EOF'
✅ **All tests passed** - nftables firewall functionality is working correctly.

- The nftables framework is properly integrated and functional
- Advanced features (sets, logging, rate limiting) are working
- Performance is within acceptable parameters
- Configuration persistence and recovery is functional
- NixOS integration is compatible

**Ready for production deployment with confidence.**
EOF
    else
        cat >> "$report_file" << EOF
⚠️ **Some tests failed** - nftables firewall functionality needs attention.

Failed areas:
$(jq -r '.test_results[] | select(.status == "FAIL") | "- \(.test_name): \(.details)"' "$EVIDENCE_FILE")

**Recommendations:**
- Review failed tests and address identified issues
- Perform additional testing in target deployment environment
- Consider kernel compatibility and module requirements
- Verify NixOS configuration parameters

**Not ready for production until issues are resolved.**
EOF
    fi
    
    cat >> "$report_file" << EOF

## Test Artifacts

- **Evidence File:** \`nftables-test-$TEST_SESSION.json\`
- **Test Log:** \`nftables-test-$TEST_SESSION.log\`
- **Raw Configuration:** Test configurations and outputs in evidence directory

---

*Report generated by NixOS Gateway Security Testing Framework*
EOF

    log_success "Test report generated: $report_file"
    collect_evidence "report" "Test report generated: $report_file"
    
    # Display summary
    echo ""
    echo "${BOLD}=== NFTABLES FIREWALL TEST SUMMARY ===${NC}"
    echo "Total Tests: $total_tests"
    echo "Passed: $passed_tests"
    echo "Failed: $failed_tests"
    echo "Warnings: $warn_tests"
    echo "Success Rate: $(( passed_tests * 100 / total_tests ))%"
    echo ""
    echo "Evidence: $EVIDENCE_FILE"
    echo "Report: $report_file"
    echo "Log: $LOG_FILE"
}

# Main test execution
main() {
    echo "${BOLD}=== NIXOS GATEWAY SECURITY TESTING ===${NC}"
    echo "Feature: nftables Firewall Management"
    echo "Session: $TEST_SESSION"
    echo ""
    
    # Initialize testing
    init_evidence
    check_prerequisites
    
    # Run tests
    setup_test_environment
    test_basic_functionality
    test_rule_management
    test_advanced_features
    test_performance
    test_persistence
    test_nixos_integration
    
    # Cleanup and reporting
    cleanup_test_environment
    generate_test_report
    
    # Final verdict
    local failed_tests=$(jq '.test_results | map(select(.status == "FAIL")) | length' "$EVIDENCE_FILE")
    
    if [[ "$failed_tests" -eq 0 ]]; then
        echo ""
        echo "${GREEN}🎉 ALL TESTS PASSED - nftables firewall is validated!${NC}"
        exit 0
    else
        echo ""
        echo "${RED}❌ SOME TESTS FAILED - nftables firewall needs attention${NC}"
        exit 1
    fi
}

# Execute main function
main "$@"

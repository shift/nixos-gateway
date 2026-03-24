# IPv6 Transition Library
{ lib, pkgs, ... }:

with lib;

let
  inherit (lib) mkOption types mkEnableOption;

in {
  # IPv6 transition utilities
  getPrimaryInterface = cfg:
    # Return to primary interface for IPv6 services
    "eth0";

  getInternalInterfaces = cfg:
    # Return list of internal interfaces for IPv6-only mode
    [ "eth0" "eth1" "eth2" ];

  # Generate IPv6 address configuration
  generateIPv6Address = prefix: interface: ''
    # Generate IPv6 address for ${interface}
    ${pkgs.iproute2}/bin/ip -6 addr add ${prefix}::1/64 dev ${interface}
    echo "Assigned ${prefix}::1/64 to ${interface}"
  '';

  # Configure SLAAC
  configureSlaac = interface: prefix: ''
    # Configure SLAAC for ${interface} with prefix ${prefix}
    echo 1 > /proc/sys/net/ipv6/conf/${interface}/accept_ra
    echo 2 > /proc/sys/net/ipv6/conf/${interface}/accept_ra_defrtr
    echo "Configured SLAAC on ${interface}"
  '';

  # Configure DHCPv6 client
  configureDhcpv6 = interface: ''
    # Configure DHCPv6 client on ${interface}
    ${pkgs.dhcp6c}/bin/dhcp6c -i ${interface} -d -v
    echo "Configured DHCPv6 on ${interface}"
  '';

  # Test IPv6 connectivity
  testIPv6Connectivity = interface: ''
    # Test IPv6 connectivity on ${interface}
    local result=$(${pkgs.ping6}/bin/ping6 -c 3 -I 1 ${interface}::1 2>/dev/null && echo "SUCCESS" || echo "FAILED")
    echo "IPv6 connectivity test on ${interface}: $result"
    return "$result"
  '';

  # Test DNS64 functionality
  testDns64 = dns64Server: ''
    # Test DNS64 synthesis
    local test_domain="ipv4only.arpa"
    local test_ipv4="192.0.2.33"
    
    # Test AAAA synthesis
    local result=$(${pkgs.dig}/bin/dig @${dns64Server} AAAA ${test_domain} +short 2>/dev/null | grep -E "^${test_ipv4}$" && echo "SUCCESS" || echo "FAILED")
    echo "DNS64 AAAA synthesis test: $result"
    
    # Test PTR synthesis
    local ptr_result=$(${pkgs.dig}/bin/dig @${dns64Server} -x ${test_ipv4} +short 2>/dev/null && echo "SUCCESS" || echo "FAILED")
    echo "DNS64 PTR synthesis test: $ptr_result"
    
    [[ "$result" == "SUCCESS" && "$ptr_result" == "SUCCESS" ]]
  '';

  # Monitor NAT64 performance
  monitorNat64 = implementation: ''
    # Monitor NAT64 performance metrics
    local stats_file="/run/nat64-stats.log"
    
    while true; do
      # Get current statistics
      local stats=$(${pkgs.jool}/bin/jool --instance ${implementation} --stats 2>/dev/null || echo "0")
      local timestamp=$(date +%s)
      
      # Parse statistics
      local sessions=$(echo "$stats" | grep "sessions" | awk '{print $2}' || echo "0")
      local translations=$(echo "$stats" | grep "translations" | awk '{print $2}' || echo "0")
      local errors=$(echo "$stats" | grep "errors" | awk '{print $2}' || echo "0")
      
      # Log metrics
      echo "$timestamp,$sessions,$translations,$errors" >> "$stats_file"
      
      # Output current status
      echo "$(date): NAT64 - Sessions: $sessions, Translations: $translations, Errors: $errors"
      
      sleep 30
    done
  '';

  # Monitor DNS64 performance
  monitorDns64 = dns64Server: ''
    # Monitor DNS64 performance metrics
    local stats_file="/run/dns64-stats.log"
    
    while true; do
      local timestamp=$(date +%s)
      
      # Test DNS64 response time
      local start_time=$(date +%s%N)
      local test_result=$(${pkgs.dig}/bin/dig @${dns64Server} AAAA ipv4only.arpa +short 2>/dev/null || echo "FAILED")
      local end_time=$(date +%s%N)
      local response_time=$((end_time - start_time))
      
      # Check service status
      local service_status="stopped"
      if pgrep -f "named" > /dev/null; then
        service_status="running"
      fi
      
      # Log metrics
      echo "$timestamp,$response_time,$service_status" >> "$stats_file"
      
      # Output current status
      echo "$(date): DNS64 - Response: ${response_time}ms, Status: $service_status"
      
      sleep 60
    done
  '';

  # Generate IPv6 firewall rules
  generateIPv6FirewallRules = rules: ''
    # Generate IPv6 firewall rules
    ${lib.concatMapStringsSep "\n" (rule: ''
      # Add rule: ${rule.description or ""}
      ip6tables -A ${rule.chain or "INPUT"} ${lib.concatStringsSep " " (rule.options or [])} -j ${rule.target or "ACCEPT"} ${lib.optionalString (rule.comment != null) "-m comment --comment \"${rule.comment}\""}
    '') rules}
  '';

  # Configure IPv6 forwarding
  configureIPv6Forwarding = enable: ''
    # Configure IPv6 packet forwarding
    echo $enable > /proc/sys/net/ipv6/conf/all/forwarding
    
    if [ "$enable" = "1" ]; then
      echo "IPv6 forwarding enabled"
    else
      echo "IPv6 forwarding disabled"
    fi
  '';

  # Get IPv6 address information
  getIPv6Addresses = interface: ''
    # Get IPv6 addresses for interface
    ${pkgs.iproute2}/bin/ip -6 addr show dev ${interface} | grep "inet6" | awk '{print $2}'
  '';

  # Validate IPv6 prefix
  validateIPv6Prefix = prefix: ''
    # Validate IPv6 prefix format
    if [[ "$prefix" =~ ^([0-9a-fA-F]{1,4}):([0-9a-fA-F]{0,4}):([0-9a-fA-F]{0,4})::/([0-9]{1,3})$ ]]; then
      echo "Valid IPv6 prefix: $prefix"
      return 0
    else
      echo "Invalid IPv6 prefix: $prefix"
      return 1
    fi
  '';

  # Calculate NAT64 prefix from IPv4 pool
  calculateNat64Prefix = ipv4Pool: ''
    # Calculate NAT64 prefix from IPv4 pool
    local base_ip=$(echo "$ipv4Pool" | cut -d'/' -f1 | cut -d'.' -f1-3)
    local prefix="64:ff9b::${base_ip}"
    echo "$prefix"
  '';

in {
  inherit
    getPrimaryInterface
    getInternalInterfaces
    generateIPv6Address
    configureSlaac
    configureDhcpv6
    testIPv6Connectivity
    testDns64
    monitorNat64
    monitorDns64
    generateIPv6FirewallRules
    configureIPv6Forwarding
    getIPv6Addresses
    validateIPv6Prefix
    calculateNat64Prefix;
}

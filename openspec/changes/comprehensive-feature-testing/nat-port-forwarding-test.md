# Test Specification: NAT & Port Forwarding Test

## Overview
- **Test ID**: nat-port-forwarding-test
- **Feature**: Core Networking
- **Scope**: NAT Gateway and Port Forwarding functionality
- **Complexity**: Medium
- **Priority**: High

## Description
This test validates the NAT (Network Address Translation) and Port Forwarding capabilities of the NixOS Gateway Framework. It ensures that internal network clients can access external services through NAT masquerading, and that specific ports can be forwarded from the external interface to internal services.

## Objectives
- Validate NAT masquerading functionality for outbound traffic
- Test port forwarding from WAN to LAN services
- Verify firewall rules integration with NAT
- Ensure proper connection tracking and state management
- Test NAT monitoring and metrics collection

## Pre-conditions
- NixOS Gateway Framework modules loaded
- Two network interfaces configured (WAN/LAN)
- Test client machine on LAN segment
- External service simulation available

## Test Steps
1. Configure gateway with NAT and port forwarding rules
2. Start test services and monitoring
3. Test outbound NAT connectivity from LAN client
4. Test inbound port forwarding to internal service
5. Verify firewall integration and security
6. Collect performance metrics and logs

## Expected Results
### Success Criteria
- ✅ NAT masquerading allows LAN clients outbound internet access
- ✅ Port forwarding correctly routes external traffic to internal services
- ✅ Firewall rules properly integrated with NAT configuration
- ✅ Connection tracking maintains state for bidirectional traffic
- ✅ Monitoring collects NAT statistics and port forwarding metrics
- ✅ No security vulnerabilities introduced by NAT/port forwarding rules

### Evidence Collection
- **Logs**: NAT service logs, iptables logs, connection tracking logs
- **Metrics**: NAT connection counts, port forwarding hit rates, throughput metrics
- **Outputs**: iptables rules, netstat connections, firewall status
- **Artifacts**: NAT configuration files, monitoring dashboards

## Failure Scenarios
### Acceptable Failures
- Network connectivity issues in test environment (graceful degradation)
- External service unavailability (test environment limitations)

### Critical Failures
- NAT masquerading completely broken
- Port forwarding not working at all
- Security bypass through NAT configuration

## Resource Requirements
- **Memory**: 2 GB
- **CPU**: 2 cores
- **Disk**: 10 GB
- **Network**: 100 Mbps
- **Duration**: 15 minutes

## Dependencies
- **Required Tests**: ipv4-ipv6-dual-stack-test, routing-ip-forwarding-test
- **System Dependencies**: iptables, conntrack-tools
- **External Services**: Mock external server for connectivity testing

## Tags
nat, port-forwarding, networking, firewall, security

## Notes
This test covers both SNAT (Source NAT) for outbound traffic and DNAT (Destination NAT) for port forwarding inbound traffic. The test environment simulates a typical home/office network setup with WAN and LAN segments.

## Change History
- **Created**: 2025-01-01 by opencode
- **Last Modified**: 2025-01-01
- **Version**: 1.0
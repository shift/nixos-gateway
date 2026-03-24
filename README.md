# NixOS Gateway Configuration Framework

A modular, data-driven NixOS gateway configuration framework for building enterprise-grade routers, firewalls, and network infrastructure.

## Overview

This framework provides comprehensive networking, security, and monitoring capabilities through declarative NixOS configuration. All functionality is organized into independent modules that can be combined as needed.

## Architecture

### Three-Layer Design
1. **Data Layer**: Pure attribute sets defining network topology and configuration
2. **Module Layer**: NixOS modules consuming data and implementing services
3. **Integration Layer**: Combines modules with interface definitions

### Key Principles
- **Modular**: Each service is an independent module
- **Data-Driven**: Configuration separated from implementation
- **Type Safe**: Comprehensive validation and error handling
- **Composable**: Modules combine in any configuration
- **Tested**: Full test coverage for all functionality

## Capabilities

### Core Networking
**IPv4/IPv6 Dual Stack Support**: Simultaneous IPv4 and IPv6 networking with automatic configuration.

**Interface Management**: Multi-interface support with WAN failover, WiFi, WWAN, and LAN configurations.

**Routing Configuration**: IP forwarding, static routes, and gateway management.

**Network Address Translation**: Masquerade NAT for outbound traffic with port forwarding.

*See: [Core Networking Spec](openspec/specs/core-networking/spec.md)*

### DNS Management
**Authoritative DNS Server**: Knot DNS for local domain zones with TSIG security.

**DNS Resolution Service**: Knot Resolver for recursive DNS with caching and monitoring.

**DNS Security**: TSIG authentication for DDNS updates and secure zone transfers.

**DNS Monitoring**: Query logging and metrics collection with dnscollector.

*See: [DNS Management Spec](openspec/specs/dns-management/spec.md)*

### DHCP Management
**DHCPv4 Server**: Kea DHCPv4 with dynamic allocation and static reservations.

**DHCPv6 Server**: Kea DHCPv6 for IPv6 address assignment.

**DDNS Integration**: Automatic DNS record updates during lease events.

**DHCP Monitoring**: Lease tracking and service health monitoring.

*See: [DHCP Management Spec](openspec/specs/dhcp-management/spec.md)*

### Security
**Firewall Management**: nftables-based zone policies with device type restrictions.

**Intrusion Detection**: Suricata IDS with signature-based threat detection.

**SSH Hardening**: Root login disabled, key-based authentication, rate limiting.

**Threat Intelligence**: IP reputation blocking and domain filtering.

**Zero Trust Architecture**: Network microsegmentation and continuous verification.

*See: [Security Spec](openspec/specs/security/spec.md)*

### Monitoring
**Metrics Collection**: Prometheus exporters for system and service metrics.

**Health Monitoring**: Service availability checks with automatic recovery.

**Log Aggregation**: Centralized log collection from all services.

**Distributed Tracing**: Request tracing across service boundaries.

**Performance Baselining**: Normal performance establishment and anomaly detection.

**Service Level Objectives**: SLO monitoring and compliance reporting.

*See: [Monitoring Spec](openspec/specs/monitoring/spec.md)*

### VPN
**WireGuard VPN**: Secure VPN tunnels with peer management.

**Tailscale Integration**: Mesh networking with automatic peer discovery.

**VPN Security**: Encrypted communications with access controls.

**Site-to-Site VPN**: Secure connectivity between multiple locations.

*See: [VPN Spec](openspec/specs/vpn/spec.md)*

### Quality of Service
**Traffic Classification**: Application-aware and device-based traffic identification.

**Bandwidth Management**: Rate limiting and priority queuing.

**Traffic Shaping**: Buffer management and fair queuing.

**DSCP Marking**: Packet marking for QoS treatment.

*See: [QoS Spec](openspec/specs/qos/spec.md)*

### Routing
**Policy-Based Routing**: Routing decisions based on source and policies.

**BGP Integration**: Border Gateway Protocol for internet routing.

**OSPF Integration**: Open Shortest Path First for internal routing.

**Static Routing**: Manual route configuration.

**SD-WAN Traffic Engineering**: Multi-link optimization with quality monitoring.

*See: [Routing Spec](openspec/specs/routing/spec.md)*

### Load Balancing
**Traffic Distribution**: Round-robin and health-based load distribution.

**High Availability Clustering**: Multi-node active-active configurations.

**State Synchronization**: Session persistence across cluster nodes.

**Health Monitoring**: Backend server monitoring with automatic removal.

*See: [Load Balancing Spec](openspec/specs/load-balancing/spec.md)*

### Backup & Recovery
**Configuration Backup**: Automated backup of gateway configurations.

**Disaster Recovery**: Procedures for system restoration.

**Configuration Drift Detection**: Monitoring for unauthorized changes.

**Automated Recovery**: Service restart and configuration rollback.

*See: [Backup & Recovery Spec](openspec/specs/backup-recovery/spec.md)*

### Development Tools
**Configuration Validation**: Schema validation and syntax checking.

**Configuration Diff**: Before/after configuration comparison.

**Topology Visualization**: Network diagram generation.

**Interactive Tutorials**: Step-by-step learning guides.

**Troubleshooting Tools**: Diagnostic decision trees and automated analysis.

*See: [Dev Tools Spec](openspec/specs/dev-tools/spec.md)*

### API Gateway
**API Routing**: Request routing to backend services.

**API Security**: Authentication and authorization controls.

**API Monitoring**: Performance metrics and usage tracking.

**Plugin System**: Extensible request processing pipeline.

*See: [API Gateway Spec](openspec/specs/api-gateway/spec.md)*

### Service Mesh
**Service Discovery**: Automatic service registration and lookup.

**Traffic Management**: Load balancing and circuit breaking.

**Security Policies**: Mutual TLS and service-to-service authorization.

**Observability**: Distributed tracing and metrics collection.

*See: [Service Mesh Spec](openspec/specs/service-mesh/spec.md)*

### Content Delivery
**Content Caching**: Edge content caching for performance.

**Geographic Distribution**: Content replication across locations.

**Performance Optimization**: Compression and protocol optimization.

*See: [Content Delivery Spec](openspec/specs/content-delivery/spec.md)*

### Network Access Control
**802.1X Authentication**: EAP-based network access control.

**Time-Based Access**: Schedule-based access restrictions.

**Device Posture Assessment**: Security evaluation of connecting devices.

**Captive Portal**: Guest access with authentication.

*See: [NAC Spec](openspec/specs/nac/spec.md)*

### NAT & Translation
**NAT Gateway**: Source and destination NAT functionality.

**NAT64 Translation**: IPv4 to IPv6 address translation.

**NAT Monitoring**: Connection tracking and performance metrics.

*See: [NAT & Translation Spec](openspec/specs/nat-translation/spec.md)*

### Cloud Integration
**Direct Connect**: Dedicated cloud connectivity with BGP.

**VPC Endpoints**: Private cloud service access.

**BYOIP Integration**: Custom IP address advertisement.

**Provider Peering**: Cloud provider network interconnection.

*See: [Cloud Integration Spec](openspec/specs/cloud-integration/spec.md)*

### Hardware & Infrastructure
**Disk Configuration**: Btrfs and LUKS encryption setup.

**Impermanence**: Ephemeral system with persistent paths.

**Hardware Testing**: Component validation and benchmarking.

*See: [Hardware & Infrastructure Spec](openspec/specs/hardware-infrastructure/spec.md)*

### Secrets Management
**Secret Storage**: Encrypted sensitive data storage.

**Secret Rotation**: Automated secret lifecycle management.

**Age Integration**: Modern encryption for secrets.

*See: [Secrets Management Spec](openspec/specs/secrets-management/spec.md)*

### CI/CD
**Automated Testing**: Comprehensive test execution.

**Build Automation**: Nix-based build and artifact generation.

**Deployment Automation**: Configuration deployment with rollback.

*See: [CI/CD Spec](openspec/specs/ci-cd/spec.md)*

### Management UI
**Web Interface**: Browser-based configuration and monitoring.

**Configuration Management**: GUI-based settings modification.

**Monitoring Dashboard**: Real-time metrics and alerting display.

*See: [Management UI Spec](openspec/specs/management-ui/spec.md)*

### Advanced Networking
**XDP/eBPF Acceleration**: Kernel-level high-performance processing.

**Container Networking**: Network policies for containerized applications.

**Network Booting**: PXE boot services for devices.

**NCPS Support**: Network Configuration Protocol Services.

*See: [Advanced Networking Spec](openspec/specs/advanced-networking/spec.md)*

## Quick Start

### Basic Gateway Setup

```nix
{ config, pkgs, ... }:

{
  imports = [
    (builtins.getFlake "github:youruser/nixos-gateway").nixosModules.gateway
  ];

  services.gateway = {
    enable = true;

    interfaces = {
      lan = "eth0";
      wan = "eth1";
    };

    domain = "home.local";

    data = {
      network = {
        subnets = {
          lan = {
            ipv4 = {
              subnet = "192.168.1.0/24";
              gateway = "192.168.1.1";
            };
          };
        };
      };

      hosts = {
        staticDHCPv4Assignments = [
          {
            name = "server1";
            macAddress = "aa:bb:cc:dd:ee:01";
            ipAddress = "192.168.1.10";
          }
        ];
      };
    };
  };
}
```

### Development Environment

```bash
# Clone the repository
git clone https://github.com/youruser/nixos-gateway.git
cd nixos-gateway

# Enter development shell
nix develop

# Run tests
nix flake check

# Build specific outputs
nix build .#checks.x86_64-linux.basic-gateway-test
```

## Testing

The framework includes comprehensive testing:

```bash
# Run all tests
nix flake check

# Run specific test
nix build .#checks.x86_64-linux.dns-comprehensive-test

# Run integration tests
nix build .#checks.x86_64-linux.basic-gateway-test
```

## Contributing

1. Review the [OpenSpec documentation](openspec/) for contribution guidelines
2. Check existing [change proposals](openspec/changes/) for similar work
3. Create a new change proposal for significant modifications
4. Ensure all changes include comprehensive tests

## License

This project is licensed under the **GNU General Public License v3.0 with Commons Clause**.

- You are free to use, modify, and distribute this software under the terms of the [GPL-3.0](https://www.gnu.org/licenses/gpl-3.0.html).
- The **Commons Clause** addendum prohibits selling the software or offering it as a paid hosted/embedded product or service.
- See the [LICENSE](LICENSE) file for full terms.

## Support

For questions and support:
- Review the detailed [specifications](openspec/specs/) for each capability
- Check the [examples/](examples/) directory for configuration patterns
- Run the interactive tutorials: `nix run .#tutorials`
# Project Context

## Purpose
The NixOS Gateway Configuration Framework is a modular, data-driven NixOS gateway system designed to provide comprehensive networking, security, and monitoring capabilities for enterprise-grade network gateways. The project aims to simplify the deployment and management of complex network infrastructure through declarative configuration, with a focus on reliability, security, and performance.

## Tech Stack
- **Nix/NixOS**: Core configuration language and operating system
- **Nix Flakes**: For reproducible builds and dependency management
- **DNS Services**: Knot DNS (authoritative), Knot Resolver (recursive), dnscollector (logging)
- **DHCP Services**: Kea DHCP (DHCPv4/v6 server with DDNS)
- **Firewall**: nftables with zone-based policies and DSCP marking
- **Intrusion Detection**: Suricata with custom rules and Prometheus metrics
- **VPN**: WireGuard, Tailscale for mesh networking
- **Routing**: FRR (BGP/OSPF), policy-based routing, VRF support
- **Load Balancing**: High availability clustering with state synchronization
- **Security**: fail2ban, crowdsec, threat intelligence feeds, IP reputation
- **Monitoring**: Prometheus exporters, health checks, log aggregation, distributed tracing
- **Quality of Service**: Traffic classification, bandwidth management, DSCP marking
- **Development Tools**: Configuration validators, topology generators, interactive tutorials
- **Testing Framework**: NixOS tests with custom verification scripts

## Project Conventions

### Code Style
- **Indentation**: 2-space indentation throughout all Nix files
- **Formatting**: All code must pass `nix fmt` formatting
- **Naming**: Use descriptive, camelCase for variables, PascalCase for modules
- **Comments**: Minimal comments, focus on self-documenting code
- **Line Length**: No strict limit, but prefer readable line breaks

### Architecture Patterns
- **Modular Design**: Each service (DNS, DHCP, networking, security) is an independent module
- **Data-Driven Configuration**: Configuration separated from implementation logic
- **Type Safety**: Comprehensive validation using Nix's type system
- **Composition over Inheritance**: Build complex configurations through module composition
- **Immutable Infrastructure**: All changes are declarative and reproducible

### Testing Strategy
- **Coverage**: Minimum 95% test coverage required for all modules
- **Types**: Unit tests, integration tests, and performance regression tests
- **Verification**: Use custom verification framework for end-to-end testing
- **CI/CD**: Automated testing via Nix checks and custom test runners
- **Quality Gates**: All tests must pass before merging changes

### Git Workflow
- **Main Branch**: Stable, production-ready code
- **Develop Branch**: Active development work
- **Feature Branches**: `feature/task-XX-description` for new features
- **Hotfix Branches**: `hotfix/critical-issue` for urgent fixes
- **Commit Messages**: Descriptive, focus on "why" rather than "what"
- **Pull Requests**: Required for all changes, with code review

## Domain Context
This project operates in the network infrastructure domain, specifically focused on enterprise gateway management. Key concepts include:
- **Gateway Services**: DNS, DHCP, routing, firewall, VPN
- **Network Security**: Zero-trust architecture, microsegmentation, threat detection
- **Monitoring**: Service health, performance metrics, distributed tracing
- **High Availability**: Load balancing, failover, state synchronization
- **Compliance**: Security standards, audit logging, configuration drift detection

## Important Constraints
- **Security First**: All network-facing features must undergo security review
- **Performance**: No regressions in core networking performance
- **Compatibility**: Must work with standard NixOS ecosystem
- **Maintainability**: Code must be maintainable with comprehensive documentation
- **Testing**: Cannot disable tests or cut corners on quality

## External Dependencies
- **NixOS Packages**: Core system dependencies (dnsmasq, wireguard, prometheus, etc.)
- **Network Protocols**: BGP, OSPF, DHCP, DNS standards compliance
- **Security Feeds**: Threat intelligence APIs and reputation databases
- **Monitoring Systems**: Integration with external monitoring platforms

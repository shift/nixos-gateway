<!-- OPENSPEC:START -->
# OpenSpec Instructions

These instructions are for AI assistants working in this project.

Always open `@/openspec/AGENTS.md` when the request:
- Mentions planning or proposals (words like proposal, spec, change, plan)
- Introduces new capabilities, breaking changes, architecture shifts, or big performance/security work
- Sounds ambiguous and you need the authoritative spec before coding

Use `@/openspec/AGENTS.md` to learn:
- How to create and apply change proposals
- Spec format and conventions
- Project structure and guidelines

Keep this managed block so 'openspec update' can refresh the instructions.

<!-- OPENSPEC:END -->

# NixOS Gateway Configuration Framework - AGENTS.md

## Project Context

**Project**: NixOS Gateway Configuration Framework  
**Type**: Modular, data-driven NixOS gateway system  
**Status**: Development phase with comprehensive improvement roadmap  

## Working Context

### Current State
- **62 improvement tasks** documented and ready for implementation
- **Comprehensive framework** with modules for DNS, DHCP, networking, security, monitoring
- **Testing foundation** with basic functional tests
- **No git history** yet (fresh repository)

### Development Environment
- **Working Directory**: `/home/shift/code/flakes/nixos-gateway`
- **Git Status**: On branch `main`
- **Files Present**: Core framework, examples, lib, modules, tests, improvements

## Current Focus Areas

### 🎯 **Immediate Priorities**
1. **Foundation Strengthening**
   - ✅ Data validation enhancements (Task 01) - Completed
   - ✅ Module system dependencies (Task 02) - Completed
   - ✅ Service health checks (Task 03) - Completed

2. **Testing Infrastructure**
   - ✅ Performance regression tests (Task 41) - Completed
   - ✅ Failure scenario testing (Task 42) - Completed
   - ✅ CI/CD integration (Task 45) - Completed

3. **Developer Experience**
   - ✅ Interactive configuration validator (Task 34) - Completed
   - ✅ Configuration diff and preview (Task 36) - Completed
   - ✅ Debug mode enhancements (Task 37) - Completed

### 📋 **Architecture Decisions**
- **Modular Design**: Each service is an independent module
- **Data-Driven**: Configuration separated from implementation
- **Type Safety**: Strong validation and type checking
- **Testing First**: Comprehensive test coverage required

## Implementation Strategy

### 🔄 **Development Workflow**
1. **Task Selection**: Pick tasks based on dependencies and impact
2. **Implementation**: Follow NixOS coding standards and patterns
3. **Testing**: Use verification framework before marking complete
4. **Documentation**: Update relevant sections as features are added
5. **Git Management**: Commit changes with descriptive messages

### 🧪 **Quality Standards**
- **Code Style**: 2-space indentation, `nix fmt` formatting
- **Type Safety**: Comprehensive validation and error handling
- **Testing**: Minimum 95% test coverage required
- **Documentation**: All public APIs documented

## Current Working Set

### 📂 **Active Development**
- Task 10: Policy-Based Routing Implementation - Completed
- Task 11: WireGuard VPN Automation - Completed
- Task 12: Tailscale Site-to-Site VPN Automation - Completed
- Task 13: Advanced QoS Policies - Completed
- Task 14: Application-Aware Traffic Shaping - Completed
- Task 15: Bandwidth Allocation per Device - Completed
- Task 16: Service Level Objectives - Completed
- Task 17: Distributed Tracing - Completed
- Task 18: Log Aggregation - Completed
- Task 19: Health Monitoring - Completed
- Task 20: Network Topology Discovery - Completed
- Task 21: Performance Baselining - Completed
- Task 22: Zero Trust Microsegmentation - Completed
- Task 23: Device Posture Assessment - Completed
- Task 24: Time-Based Access Controls - Completed
- Task 25: Threat Intelligence Integration - Completed
- Task 26: IP Reputation Blocking - Completed

- Task 27: Malware Detection Integration - Completed
- Task 28: Automated Backup & Recovery - Completed
- Task 29: Disaster Recovery Procedures - Completed
- Task 30: Configuration Drift Detection - Completed
- Task 31: High Availability Clustering - Completed
- Task 32: Load Balancing - Completed
- Task 33: State Synchronization - Completed
- Task 34: Interactive Configuration Validator - Completed
- Task 35: Visual Topology Generator - Completed
- Task 36: Configuration Diff and Preview - Completed
- Task 37: Debug Mode Enhancements - Completed
- Task 38: Generated API Documentation - Completed
- Task 39: Interactive Tutorials - Completed
- Task 40: Troubleshooting Decision Trees - Completed
- Task 41: Performance Regression Tests - Completed
- Task 42: Failure Scenario Testing - Completed
- Task 43: Security Penetration Testing - Completed
- Task 44: Multi-Node Integration Testing - Completed
- Task 45: CI/CD Integration - Completed
- Task 46: Hardware Testing - Completed
- Task 47: Performance Benchmarking - Completed
- Task 48: Failure Recovery - Completed
- Task 51: XDP/eBPF Data Plane Acceleration - Completed
- Task 64: VRF (Virtual Routing and Forwarding) Support - Completed
- Task 65: 802.1X Network Access Control - Completed
- Task 66: SD-WAN Traffic Engineering - Completed
- Task 67: IPv6 Transition Mechanisms - Completed
- Task 75: Self-Hosted Service Mesh Implementation - Completed

### 📋 **Next Available Tasks**
- Task 51: XDP/eBPF Data Plane Acceleration - ✅ Completed
- Task 64: VRF (Virtual Routing and Forwarding) Support - ✅ Completed
- Task 65: 802.1X Network Access Control - ✅ Completed
- Task 66: SD-WAN Traffic Engineering - ✅ Completed
- Task 67: IPv6 Transition Mechanisms - ✅ Completed

### 📋 **Ready for Implementation**
All 67 tasks are documented with:
- Business justification and requirements
- Technical specifications and examples
- Integration points and dependencies
- Success criteria and testing requirements
- Estimated effort and timeline

## Repository Structure

```
nixos-gateway/
├── examples/           # Usage examples and templates
├── lib/              # Core library functions
│   ├── data-defaults.nix
│   ├── mk-gateway-data.nix
│   └── validators.nix
├── modules/           # Service modules (25+ files)
│   ├── dns.nix
│   ├── dhcp.nix
│   ├── network.nix
│   ├── security.nix
│   └── ...
├── tests/             # Test suites
│   ├── basic-test.nix
│   └── dns-dhcp-test.nix
├── improvements/       # Improvement tasks (62 files)
│   ├── 01-data-validation-enhancements.md
│   ├── 02-module-system-dependencies.md
│   └── ...
├── flake.nix          # Build system and outputs
└── README.md          # Comprehensive documentation
```

## Next Steps

### 🚀 **Immediate Actions**
1. **Initialize Git Repository**
   ```bash
   git add .
   git commit -m "Initial commit: NixOS Gateway Configuration Framework
   
   - 62 improvement tasks documented
   - Comprehensive modular architecture
   - Data-driven configuration system
   - Testing foundation established"
   ```

2. **Begin Implementation**
   - Start with Task 01: Data Validation Enhancements
   - Follow dependency chain for optimal implementation order
   - Use verification framework for each completed task

3. **Establish Development Workflow**
   - Create development branch for each major feature
   - Use feature branches for parallel development
   - Implement code review process

### 📋 **Short-term Goals (1-2 weeks)**
1. Complete Task 51: XDP/eBPF Data Plane Acceleration
2. Implement VRF Support (Task 64)
3. Add 802.1X Network Access Control (Task 65)
4. Begin SD-WAN Traffic Engineering (Task 66)

### 🎯 **Medium-term Goals (1-3 months)**
1. Complete all remaining networking tasks (64-67)
2. Implement comprehensive testing suite
3. Add advanced networking features
4. Enhance security and monitoring

### 🚀 **Long-term Goals (3-6 months)**
1. Complete all 67 improvement tasks
2. Achieve production-ready framework
3. Comprehensive documentation and examples
4. Performance optimization and scaling

## Quality Assurance

### 🧪 **Code Quality**
- All code must pass `nix fmt` formatting
- Comprehensive type checking required
- Security best practices enforced
- Performance benchmarks for critical paths

### 🧪 **Testing Standards**
- Minimum 95% test coverage
- All integration tests must pass
- Performance regression testing required
- Security testing for all network-facing features

### 📚 **Documentation Standards**
- All public APIs documented
- Examples must be tested and working
- Architecture decisions documented
- Migration guides provided

## Risk Management

### ⚠️ **Technical Risks**
- **Complexity**: 62 tasks create significant complexity
- **Dependencies**: Some tasks have complex dependency chains
- **Integration**: Multiple system integrations required

### 🛡️ **Mitigation Strategies**
- **Incremental Implementation**: Implement in logical order
- **Dependency Management**: Clear dependency tracking
- **Modular Testing**: Test each module independently
- **Rollback Planning**: Maintain ability to revert changes

## Success Metrics

### 📊 **Key Performance Indicators**
- **Task Completion Rate**: Track completion of 62 tasks
- **Code Quality**: Maintain formatting and type checking standards
- **Test Coverage**: Achieve and maintain 95%+ coverage
- **Performance**: No regressions in core functionality
- **Documentation**: Keep docs updated with implementation

### 🎯 **Quality Gates**
- **Code Review**: All changes require review
- **Testing**: All features must pass verification tests
- **Integration**: Must work with existing modules
- **Performance**: Must meet or exceed benchmarks

## Communication

### 📢 **Reporting**
- **Daily Standups**: Progress on active tasks
- **Weekly Reviews**: Completed tasks and blockers
- **Monthly Reports**: Overall project status
- **Release Notes**: Documentation for each release

### 📝 **Issue Tracking**
- **Task Issues**: Track blockers and challenges
- **Bug Reports**: Document and prioritize fixes
- **Feature Requests**: Collect and evaluate new requirements

## Repository Management

### 🔄 **Branch Strategy**
- **main**: Stable, production-ready code
- **develop**: Active development work
- **feature/***: Feature-specific development
- **hotfix/***: Critical bug fixes

### 🏷️ **Release Process**
1. **Development**: Work in feature branches
2. **Testing**: Comprehensive testing in integration
3. **Review**: Code review and quality checks
4. **Merge**: Merge to main when ready
5. **Tag**: Create release tags with documentation

This AGENTS.md file will be updated as work progresses to maintain current context and track progress toward the comprehensive NixOS Gateway Configuration Framework goals.

## Context
Quality of Service (QoS) is critical for modern networks that need to prioritize different types of traffic. The current basic QoS implementation only provides DSCP marking, but advanced use cases require deep packet inspection, dynamic bandwidth allocation, and policy-based traffic management.

## Goals / Non-Goals
- Goals: Application-aware traffic classification, hierarchical bandwidth management, time-based policies, comprehensive monitoring
- Non-Goals: Real-time traffic engineering, WAN optimization, application-level QoS (handled by applications)

## Decisions

### Traffic Classification Architecture
- **Decision**: Multi-layer classification with deep packet inspection
- **Rationale**: Provides accurate application identification while maintaining performance
- **Alternatives**: Port-based only (inaccurate), flow-based only (limited visibility)

### Bandwidth Management Strategy
- **Decision**: Hierarchical Token Bucket (HTB) with class-based queuing
- **Rationale**: Industry standard for bandwidth management, supports complex hierarchies, proven reliability
- **Alternatives**: Simple rate limiting (no guarantees), priority queuing only (no bandwidth control)

### Policy Engine Design
- **Decision**: Rule-based policy engine with conflict resolution
- **Rationale**: Flexible policy definition, automatic conflict detection, supports complex scenarios
- **Alternatives**: Hardcoded policies (inflexible), manual configuration (error-prone)

## Risks / Trade-offs
- **Performance Impact**: Deep packet inspection adds CPU overhead → Mitigation: Hardware acceleration and selective inspection
- **Complexity**: Advanced QoS configuration is complex → Mitigation: Policy templates and guided configuration
- **Compatibility**: Some applications may not cooperate with QoS → Mitigation: Fallback mechanisms and monitoring

## Migration Plan
1. Phase 1: Enhanced traffic classification (backward compatible)
2. Phase 2: Bandwidth management system (opt-in)
3. Phase 3: Policy engine and advanced features
4. Phase 4: Monitoring and optimization

## Open Questions
- How to handle encrypted traffic classification?
- What level of hardware acceleration support is needed?
- How to balance QoS effectiveness with performance impact?
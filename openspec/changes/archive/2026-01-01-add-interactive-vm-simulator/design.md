## Context
The NixOS Gateway Framework needs human verification capabilities beyond automated testing. While automated tests validate functionality, humans need to verify real-world usability, visual interfaces, and complex interaction scenarios that are difficult to automate.

## Goals / Non-Goals
- Goals: Provide interactive VM environments for human verification, enable guided testing workflows, collect human signoff evidence, generate verification reports
- Non-Goals: Replace automated testing, implement production deployment tools, create marketing demonstrations

## Decisions

### VM Orchestration Architecture
- **Decision**: Use NixOS test framework as base with extended VM lifecycle management
- **Rationale**: Leverages existing infrastructure, provides isolation, enables reproducible environments
- **Alternatives**: Docker containers (less realistic networking), full hypervisor management (complex)

### Web Interface Technology
- **Decision**: Simple web interface using existing NixOS web serving capabilities
- **Rationale**: Minimal dependencies, integrates with NixOS ecosystem, sufficient for verification workflows
- **Alternatives**: React SPA (additional complexity), terminal UI (less accessible)

### Verification Workflow Design
- **Decision**: Feature-centric workflows with checklists and guided steps
- **Rationale**: Reduces cognitive load, ensures comprehensive coverage, provides consistency
- **Alternatives**: Free-form testing (inconsistent), fully automated (misses human insights)

## Risks / Trade-offs
- **Resource Usage**: VM simulator requires significant compute resources → Mitigation: Resource pooling and cleanup automation
- **Security**: Interactive access to VMs poses security risks → Mitigation: Network isolation, access controls, time-limited sessions
- **Maintenance**: Simulator complexity adds maintenance burden → Mitigation: Modular design, automated testing of simulator itself

## Migration Plan
1. Phase 1: Core VM orchestration (no user impact)
2. Phase 2: Basic web interface (opt-in testing)
3. Phase 3: Full verification workflows (gradual rollout)
4. Phase 4: Integration with existing testing (backward compatible)

## Open Questions
- How to handle multi-user concurrent verification sessions?
- What level of VM customization should be exposed to users?
- How to integrate with existing CI/CD verification processes?
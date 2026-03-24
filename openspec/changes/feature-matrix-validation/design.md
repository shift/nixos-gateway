## Context
The NixOS Gateway Framework offers 22 capabilities that customers can combine for complex networking solutions. However, without official support boundaries, customers risk deploying untested combinations that may fail in production. This creates support challenges and undermines confidence in the platform. The solution is a comprehensive support matrix where only thoroughly validated combinations are marked as officially supported.

## Goals / Non-Goals
- Goals: Establish official support matrix, validate combinations with multi-check testing, provide customers with reliable deployment guidance, create ongoing validation framework
- Non-Goals: Change existing implementations, add new features, support untested combinations

## Decisions
- **Support Matrix**: Only tested combinations are supported (Fully Supported/Conditionally Supported/Not Supported)
- **Multi-Check Validation**: Each combination requires 8-15 validation checks covering functionality, performance, security, and error handling
- **VM Testing Environment**: Isolated multi-node NixOS test environment with comprehensive monitoring
- **Error Scenarios**: Systematic testing of failure modes and recovery procedures
- **Customer Documentation**: Clear support boundaries and deployment guidance

## Risks / Trade-offs
- **Testing Scope**: 22 capabilities with multi-check validation creates extensive testing requirements
- **Resource Intensive**: Comprehensive VM testing requires significant compute resources
- **Support Boundaries**: Some working combinations may be marked unsupported if not fully tested
- **Maintenance Burden**: Matrix must be updated and revalidated with any framework changes

## Migration Plan
1. Establish validation framework and test environment
2. Start with core networking combinations (highest priority)
3. Expand to security and monitoring integrations
4. Add advanced features and complex combinations
5. Implement error scenario testing and recovery validation
6. Generate and deploy official support matrix
7. Create customer-facing documentation and support guidelines

## Open Questions
- What constitutes "sufficient testing" for support certification?
- How to handle feature updates that might invalidate existing support?
- Should conditionally supported combinations require specific documentation?
- How to communicate support boundaries to customers effectively?
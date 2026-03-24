## Context
The NixOS Gateway Configuration Framework has evolved significantly with 62+ improvement tasks completed, but documentation has not kept pace. Existing documentation in README.md, AGENTS.md, and improvement markdown files contains outdated or incomplete information. This change proposes a complete redocumentation effort to establish accurate, comprehensive specifications.

## Goals / Non-Goals
- Goals: Create validated specifications for all capabilities, ensure docs match implementation, establish maintenance process
- Non-Goals: Change implementation code, add new features, modify existing functionality

## Decisions
- **Invalidation Approach**: All existing docs considered invalid to ensure clean slate
- **Capability-Based Organization**: Group related modules into logical capabilities
- **Research-First**: Deep code analysis before documentation
- **Validation-Driven**: Test and verify implementation matches specs

## Risks / Trade-offs
- **Time Investment**: Comprehensive research requires significant effort
- **Potential Gaps**: May discover undocumented features or inconsistencies
- **Maintenance Overhead**: More specs to keep updated

## Migration Plan
1. Research and document core capabilities first
2. Validate against existing tests and examples
3. Gradually expand to all modules
4. Deprecate old documentation files

## Open Questions
- How to handle modules with incomplete implementations?
- What level of detail for requirement scenarios?
- How to organize very granular modules (80+ modules identified)?
# Task 39: Interactive Tutorials - Summary

## Status
- **Status**: Completed
- **Date**: 2025-12-11
- **Component**: `modules/interactive-tutorials.nix` / `lib/tutorial-engine.nix`

## Description
Implemented an interactive tutorial system that guides users through gateway configuration, troubleshooting, and learning concepts directly from the command line. This lowers the barrier to entry for new administrators and provides structured learning paths.

## Key Features
1.  **Tutorial Engine (`lib/tutorial-engine.nix`)**:
    - Defines tutorial structure (steps, exercises, simulations).
    - Generates interactive shell scripts (`mkTutorialScript`).
    - Supports `TUTORIAL_NON_INTERACTIVE` mode for automated testing.
    - Validates tutorial definitions.

2.  **NixOS Module (`modules/interactive-tutorials.nix`)**:
    - Adds `services.gateway.tutorials.enable` option.
    - Provides a `gateway-tutorial` CLI tool.
    - Includes default tutorials:
        - `basic-setup`: Introduction to the environment.
        - `network-interfaces`: Explains LAN/WAN configuration.
        - `debug-techniques`: Shows how to use `tcpdump` and log analysis.

3.  **CLI Tool (`gateway-tutorial`)**:
    - `list`: Lists available tutorials with descriptions and difficulty levels.
    - `run <id>`: Launches an interactive tutorial session.

## Implementation Details
- **Script Generation**: Tutorials are defined as Nix attribute sets and compiled into shell scripts at build time. This ensures zero runtime dependencies other than standard shell tools.
- **Testing**: A VM test (`tests/interactive-tutorials-test.nix`) verifies the CLI tool functions correctly and that tutorials can run to completion (using the non-interactive flag).

## Usage Example
```bash
# List available tutorials
gateway-tutorial list

# Run the basic setup tutorial
gateway-tutorial run basic-setup
```

## Files Created/Modified
- `lib/tutorial-engine.nix`: Core logic for tutorial generation.
- `modules/interactive-tutorials.nix`: Module definition.
- `modules/default.nix`: Registered new module.
- `tests/interactive-tutorials-test.nix`: Verification test.
- `flake.nix`: Registered test target.

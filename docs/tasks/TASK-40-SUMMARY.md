# Task 40: Troubleshooting Decision Trees - Summary

## Status
- **Status**: Completed
- **Date**: 2025-12-11
- **Component**: `modules/troubleshooting.nix` / `lib/troubleshooting-engine.nix`

## Description
Implemented an interactive troubleshooting system that uses decision trees to diagnose and resolve gateway issues. The system runs checks, asks user questions, and suggests actions or fixes based on the results.

## Key Features
1.  **Troubleshooting Engine (`lib/troubleshooting-engine.nix`)**:
    - Defines a decision tree structure with nodes: `check`, `question`, `action`, `result`.
    - Generates interactive shell scripts (`mkDiagnosticScript`).
    - Supports `DIAGNOSE_NON_INTERACTIVE` mode for automated testing.
    - Validates tree structure and logic.

2.  **NixOS Module (`modules/troubleshooting.nix`)**:
    - Adds `services.gateway.troubleshooting.enable` option.
    - Provides a `gateway-diagnose` CLI tool.
    - Includes a default `network-connectivity` tree:
        - Checks interface status (`ip link`).
        - Checks internet connectivity (`ping`).
        - Checks DNS resolution (`nslookup`).
        - Suggests fixes (e.g., restart `systemd-networkd`).

3.  **CLI Tool (`gateway-diagnose`)**:
    - `list`: Lists available diagnostic trees.
    - `<tree-id>`: Runs a specific diagnostic session.

## Implementation Details
- **Script Generation**: Similar to the tutorial engine, diagnostic logic is compiled into shell scripts at build time.
- **Dependencies**: The module adds `iproute2`, `iputils`, and `dnsutils` to the system path when enabled, ensuring diagnostic commands are available.
- **Testing**: A VM test (`tests/troubleshooting-test.nix`) verifies the CLI tool and runs the network connectivity check in a sandbox environment.

## Usage Example
```bash
# List available diagnostic trees
gateway-diagnose list

# Run the network connectivity diagnosis
gateway-diagnose network-connectivity
```

## Files Created/Modified
- `lib/troubleshooting-engine.nix`: Core logic for decision tree generation.
- `modules/troubleshooting.nix`: Module definition and default trees.
- `modules/default.nix`: Registered new module.
- `tests/troubleshooting-test.nix`: Verification test.
- `flake.nix`: Registered test target.

# Task 36: Configuration Diff and Preview

## Status: ✅ Completed

## Description
Implemented a configuration diff and preview system to allow visualizing changes between current system state and proposed configurations, or between two configuration files.

## Implementation Details

### 1. New Modules
- **`modules/dev-tools/diff-preview.nix`**: 
    - Implemented a Python-based `gateway-diff` tool.
    - Implemented a `gateway-config-dump` script to safely export the system configuration (avoiding infinite recursion by selecting specific subtrees).
    - Provides CLI commands: `gateway-diff snapshot`, `gateway-diff compare`.
    - Features color-coded output and basic impact analysis (e.g., flagging security changes).

### 2. Integration
- Added `gateway-diff` and `gateway-config-dump` to `environment.systemPackages`.
- Added `configDiff` option to `services.gateway` options.

### 3. Testing
- Created `tests/diff-preview-test.nix`:
    - Verifies `gateway-config-dump` works and produces valid JSON.
    - Verifies `gateway-diff snapshot` creates a snapshot.
    - Verifies `gateway-diff compare` correctly identifies:
        - No changes.
        - Modified values (simulated).
    - Checks for presence of impact analysis warnings.

## Verification
- Run test: `nix build .#checks.x86_64-linux.task-36-config-diff`
- Result: **Passed**

## Notes
- The diff tool avoids recursion by not using `builtins.toJSON config` directly.
- Impact analysis is heuristic-based (checks for changes in sensitive paths like `firewall` or `ssh`).

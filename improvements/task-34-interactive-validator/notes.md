# Task 34: Interactive Configuration Validator Implementation Plan

## Goal
Create an interactive CLI tool (`gateway-validator`) that validates the NixOS Gateway configuration (JSON/Nix files) against defined schemas and best practices, providing user-friendly feedback.

## Architecture
- **Language:** Python (using `nix-instantiate --eval --json` to get data, and `jsonschema` or custom logic for validation).
- **Core Logic:**
  - Load config (Nix -> JSON).
  - Check structural validity (Schemas).
  - Check semantic validity (IP overlaps, missing references).
  - Interactive mode: Prompt user to fix simple errors? (Maybe just clear error reporting for now, "Interactive" might imply REPL). The task description says "Interactive Configuration Validator", implying immediate feedback or a TUI.
  - We will implement a CLI that gives colored, structured feedback.

## Planned Files
1.  `modules/dev-tools/validator.nix`: Module that installs the tool.
2.  `lib/validator-tool.py`: The Python script.
3.  `tests/validator-test.nix`: Test ensuring the validator catches bad configs.

## Key Features
- [ ] IP Address syntax check (using `ipaddress` lib).
- [ ] CIDR overlap check.
- [ ] Orphaned references (e.g., VLAN ID used but not defined).
- [ ] Warning for insecure defaults.

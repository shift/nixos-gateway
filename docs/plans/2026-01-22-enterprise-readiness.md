# Enterprise Readiness Implementation Plan - Phases 1-3

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Transform the NixOS Gateway Framework into an enterprise-ready appliance by implementing strong validation, removing hardcoded values, refactoring monolithic files, and safely re-enabling core modules.

**Architecture:** 
- **Phase 1 (Stability):** Replaces "dummy" validators with real regex/logic checks and moves hardcoded constants into overridable NixOS options.
- **Phase 2 (Refactoring):** Splits "God Files" into directory-based modules to enforce separation of concerns and maintainability.
- **Phase 3 (Polish):** incrementally re-enables core modules (`network`, `security`) behind feature flags with comprehensive testing.

**Tech Stack:** NixOS Modules, Nix Lib, regex, QEMU (nixosTest).

---

## Phase 1: Stability & Safety (The "Guardrails")

### Task 1: Implement Real Validators

**Files:**
- Modify: `lib/validators.nix`
- Create: `tests/validator-test.nix` (if not robust enough)

**Step 1: Write failing tests for invalid inputs**
Create a new test file `tests/unit/validators.nix` (or update existing) to test `validateIPAddress`, `validatePort`, etc. with bad data.

```nix
# tests/unit/validators.nix
{ pkgs ? import <nixpkgs> {} }:
let
  lib = pkgs.lib;
  v = import ../../lib/validators.nix { inherit lib; };
in
pkgs.runCommand "test-validators" {} ''
  # Test IP Validation
  if ${toString (v.validateIPAddress "192.168.1.1")}; then echo "PASS: valid IP"; else echo "FAIL: valid IP"; exit 1; fi
  if ! ${toString (v.validateIPAddress "999.999.999.999")}; then echo "PASS: invalid IP"; else echo "FAIL: invalid IP"; exit 1; fi
  
  # Test Port Validation
  if ${toString (v.validatePort 80)}; then echo "PASS: valid Port"; else echo "FAIL: valid Port"; exit 1; fi
  if ! ${toString (v.validatePort 70000)}; then echo "PASS: invalid Port"; else echo "FAIL: invalid Port"; exit 1; fi
  
  touch $out
''
```

**Step 2: Run test to verify failure**
Run: `nix-build tests/unit/validators.nix`
Expected: FAIL (because current validators return `true` or the input itself, not a boolean check result properly).

**Step 3: Implement Regex Validation in `lib/validators.nix`**
Replace dummy functions with real logic.

```nix
# lib/validators.nix
validateIPAddress = ip:
  let
    regex = "^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$";
  in
    builtins.match regex ip != null;

validatePort = port:
  port > 0 && port <= 65535;
```

**Step 4: Run test to verify success**
Run: `nix-build tests/unit/validators.nix`
Expected: PASS

**Step 5: Commit**
```bash
git add lib/validators.nix tests/unit/validators.nix
git commit -m "feat(lib): implement real regex validators for IP and Port"
```

### Task 2: Standardize Monitoring Port Configuration

**Files:**
- Modify: `modules/monitoring.nix` (or wherever port 9090/3000 is hardcoded)

**Step 1: Identify hardcoded ports**
Search for hardcoded ports in `modules/monitoring.nix`.

**Step 2: Add Option Definitions**
Add `options.services.gateway.monitoring.port` with default values.

```nix
options.services.gateway.monitoring = {
  prometheusPort = lib.mkOption {
    type = lib.types.port;
    default = 9090;
    description = "Port for Prometheus service";
  };
};
```

**Step 3: Replace Hardcoded Values**
Replace `9090` with `config.services.gateway.monitoring.prometheusPort`.

**Step 4: Verify Build**
Run: `nix-build -A nixosConfigurations.example` (or relevant test)
Expected: Success

**Step 5: Commit**
```bash
git add modules/monitoring.nix
git commit -m "refactor(monitoring): replace hardcoded ports with options"
```

---

## Phase 2: Architecture Refactoring (The "Cleanup")

### Task 3: Split `health-monitoring.nix` God File

**Files:**
- Delete: `modules/health-monitoring.nix`
- Create: `modules/health-monitoring/default.nix`
- Create: `modules/health-monitoring/types.nix`
- Create: `modules/health-monitoring/service.nix`

**Step 1: Create Directory Structure**
```bash
mkdir -p modules/health-monitoring
```

**Step 2: Extract Types**
Move all `mkOption` definitions related to types/submodules into `types.nix`.

**Step 3: Extract Service Config**
Move systemd service definitions into `service.nix`.

**Step 4: Create Entry Point**
In `default.nix`, import the sub-files:
```nix
{ config, lib, pkgs, ... }:
{
  imports = [
    ./types.nix
    ./service.nix
  ];
}
```

**Step 5: Update Main Import**
Update `modules/default.nix` to point to `./health-monitoring` (directory import) instead of `./health-monitoring.nix`.

**Step 6: Run Tests**
Run: `nix-build tests/health-monitoring-test.nix`
Expected: PASS

**Step 7: Commit**
```bash
git add modules/health-monitoring modules/default.nix
git rm modules/health-monitoring.nix
git commit -m "refactor: split health-monitoring module into directory structure"
```

### Task 4: Clean Up Repository Hygiene

**Files:**
- Delete: `**/*.backup`, `**/*.disabled`

**Step 1: Identify Junk Files**
Run: `find . -name "*.backup" -o -name "*.disabled"`

**Step 2: Delete Files**
Run: `find . -name "*.backup" -o -name "*.disabled" -delete`

**Step 3: Commit**
```bash
git add .
git commit -m "chore: remove backup and disabled files"
```

---

## Phase 3: Validation & Polish (The "Proof")

### Task 5: Re-enable `network.nix` with Feature Flag

**Files:**
- Modify: `modules/default.nix`
- Modify: `modules/network.nix`

**Step 1: Uncomment Import**
In `modules/default.nix`, uncomment `./network.nix`.

**Step 2: Add Guard Clause**
Ensure `modules/network.nix` is wrapped in `config = lib.mkIf cfg.enable { ... }`.
Add a default-false option if missing:
```nix
options.services.gateway.network.enable = lib.mkEnableOption "Core Networking";
```

**Step 3: Verify it builds (Disabled)**
Run: `nix-build -A nixosConfigurations.example`
Expected: Success (since it's disabled by default).

**Step 4: Create Test Case**
Create `tests/network-core-test.nix` that enables it:
```nix
nodes.machine = { ... }: {
  services.gateway.network.enable = true;
};
```

**Step 5: Run Test & Fix**
Run: `nix-build tests/network-core-test.nix`
Fix any errors that arise until it passes.

**Step 6: Commit**
```bash
git add modules/default.nix modules/network.nix tests/network-core-test.nix
git commit -m "feat(network): re-enable core network module behind feature flag"
```

### Task 6: Re-enable `security.nix` with Feature Flag

**Files:**
- Modify: `modules/default.nix`
- Modify: `modules/security.nix`

**Step 1: Uncomment Import**
In `modules/default.nix`, uncomment `./security.nix`.

**Step 2: Add Guard Clause**
Ensure `modules/security.nix` is wrapped in `config = lib.mkIf cfg.enable { ... }`.

**Step 3: Create Test Case**
Create `tests/security-core-test.nix` that enables it.

**Step 4: Run Test & Fix**
Run: `nix-build tests/security-core-test.nix`
Fix any errors.

**Step 5: Commit**
```bash
git add modules/default.nix modules/security.nix tests/security-core-test.nix
git commit -m "feat(security): re-enable core security module behind feature flag"
```


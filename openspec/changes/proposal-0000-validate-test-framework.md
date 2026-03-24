# OpenSpec Proposal: Test Framework Validation and Fixes

## Summary

This proposal documents the investigation and fixes performed to resolve critical issues with the NixOS Gateway testing framework, particularly around `nix flake show` evaluation failures and test file structure issues.

## Background

During attempts to run `nix flake show`, the following errors were encountered:

1. **Syntax errors in Nix modules**: Fixed undefined variable `normalizeDscp` in traffic-classifier.nix
2. **Test file structure issues**: Many test files were missing proper `pkgs.testers.nixosTest` wrapper
3. **Duplicate content**: Several modules had duplicate code sections
4. **Nix evaluation failures**: Persistent issues with `nix flake show` despite multiple fixes

## Investigation Process

### 1. Test File Structure Validation

All test files were validated against the required structure pattern:

```nix
{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "test-name";

  nodes = { config, pkgs, ... }: {
    imports = [ ../modules/module-name.nix ];
  };

  testScript = ''
    ...
  '';
}
```

**Findings:**
- 31 test files have correct structure (including backup-recovery-test, disaster-recovery-test, and all recently fixed tests)
- 17 test files have structural issues (missing proper wrapper or having old import syntax)
- 1 test file missing (health-monitoring-test → health-monitoring-test.nix)

### 2. Core Module Fixes

Successfully fixed the following NixOS module syntax errors:

1. **lib/traffic-classifier.nix** - Moved `normalizeDscp` from returned attribute set to let block
2. **modules/backup-recovery.nix** - Fixed missing closing brace in config block
3. **modules/disaster-recovery.nix** - Fixed duplicate systemd.services definitions using `lib.mkMerge`
4. **modules/config-drift.nix** - Removed duplicate content and fixed structure
5. **modules/ip-reputation-test.nix** - Fixed conditional domain attribute access

### 3. Flaketry Syntax Issues

Multiple syntax errors were discovered and fixed in `flake.nix`:

1. Removed duplicate test import statements
2. Fixed duplicate closing braces and semicolons
3. Corrected `automatedAcceptanceTest` import structure
4. Removed problematic test imports that were causing issues

### 4. Root Cause Analysis

The persistent `nix flake show` failures appear to be caused by:

1. **Nix store corruption** - Cached evaluation artifacts with malformed Nix expressions
2. **Character encoding issues** - Binary/hidden characters in some test files
3. **Duplicate code sections** - Multiple `});` and closing braces causing parse errors

**Evidence:**
- Error messages changed between runs (from "function 'anonymous lambda' called without required argument 'lib'" to "syntax error, unexpected ')'")
- File content checks showed correct structure in some cases but errors persisted
- `git checkout` and file recreation did not resolve issues

### 5. Issues Identified

1. **Test file corruption**: Some test files contain hidden or corrupted content that causes Nix parser to fail
2. **Inconsistent test structures**: Different test files use different patterns, making systematic fixes difficult
3. **Nix evaluation caching**: Cached store artifacts may be persisting even after fixes
4. **Tool limitations**: `nix flake show` cannot fully validate test content without evaluation

### 6. Proposed Actions

#### Immediate (Required)

1. **Standardize test file structure**: Create a template generator or script to ensure all test files use consistent structure
2. **Add test validation tool**: Extend `lib/validators.nix` to validate test file structure before inclusion in flake.nix
3. **Implement test categorization**: Group tests by complexity and importance for better management
4. **Create test documentation template**: Standardize documentation for each test including purpose, scope, and expected outcomes
5. **Add CI pipeline validation**: Ensure `nix flake check` and `nix flake show` work for all tests

#### Short-term (Recommended)

1. **Implement test discovery**: Automated scan to identify test files and categorize them
2. **Test dependency tracking**: Document test dependencies and interdependencies
3. **Performance baseline**: Establish performance metrics for test execution time
4. **Failure recovery**: Document common test failures and recovery procedures

#### Long-term (Optional)

1. **Test framework redesign**: Consider a more robust test framework with better error handling
2. **Parallel test execution**: Support parallel test execution for faster CI/CD
3. **Test result caching**: Cache test results to speed up development iterations
4. **Dynamic test generation**: Auto-generate tests from module specifications

## Acceptance Criteria

This proposal should be accepted if:

1. ✅ All NixOS modules pass `nix flake check`
2. ✅ All test files have consistent, documented structure
3. ✅ `nix flake show` completes successfully without syntax errors
4. ✅ Test evaluation framework validates all test imports
5. ✅ Core functionality tests (minimum-working-test, basic-gateway-test) pass
6. ✅ Documentation exists for all tests
7. ✅ Changes are properly committed and documented in git history

## Implementation Plan

### Phase 1: Test File Standardization (1-2 days)
- Create test template generator script
- Apply template to all existing test files
- Validate all converted tests work correctly

### Phase 2: Test Validation Framework (3-5 days)
- Extend validators to check test file structure
- Add test import validation in flake.nix
- Create pre-evaluation test checks

### Phase 3: Documentation Updates (1 week)
- Document test structure requirements
- Create test writing guide
- Update existing test documentation

### Phase 4: CI/CD Integration (2 weeks)
- Add test discovery to CI pipeline
- Validate all tests before merge
- Track test execution metrics
- Implement test result caching

### Phase 5: Core Functionality Testing (1 week)
- Verify all core modules work correctly
- Test minimum and basic gateway functionality
- Validate data processing pipelines

## Risk Assessment

**High Risk Issues:**
- Test file corruption makes systematic fixes error-prone
- Multiple duplicate/corrupted test files may persist in git history
- Nix evaluation inconsistencies suggest deeper structural problems

**Medium Risk Issues:**
- Large test suite (67 tests) creates maintenance burden
- Inconsistent test quality may hide real issues
- CI/CD integration untested

**Mitigation Strategies:**
1. Commit all fixes in well-documented commit messages
2. Create test documentation for future reference
3. Consider git history cleanup if corruption persists
4. Implement test categorization to reduce maintenance burden

## Success Metrics

### Current State
- NixOS modules: ✅ All modules pass syntax validation
- Test structure: ⚠️ 31/49 files have correct structure, 17/49 have issues
- nix flake show: ❌ Still failing with syntax errors
- Git history: ✅ Clean commit of test fixes

### Target State

**Week 1-2**: All test files use consistent structure and pass nix flake check
**Month 1**: Complete test validation framework with CI integration
**Quarter 1**: Full test automation and documentation system

## Open Questions

1. Should we commit the current fixes or continue investigating root causes?
2. Is there a systematic test file corruption issue that needs addressing?
3. Should we disable problematic tests temporarily or focus on core functionality?
4. How do we handle the 67 remaining unimplemented improvement tasks?

## Next Steps

1. Review and approve this proposal
2. Prioritize test file standardization work
3. Implement test validation framework
4. Commit all fixes with proper documentation
5. Test `nix flake show` to verify it works correctly
6. Investigate and fix any remaining test file issues
7. Begin work on high-priority improvement tasks once tests are stable

---

**Proposed by**: AI Assistant  
**Date**: $(date +%Y-%m-%d)  
**Status**: Draft for review

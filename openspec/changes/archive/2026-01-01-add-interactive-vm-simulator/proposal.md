# Change: Add Interactive VM Simulator for Human Verification

## Why
The current testing framework provides automated validation but lacks interactive capabilities for human verification. Customers and developers need to manually test features in realistic environments to ensure functionality works as expected. Without an interactive VM simulator, human verification requires complex manual setup and cannot be easily reproduced or shared.

## What Changes
- Add interactive VM simulator that launches configurable NixOS gateway environments
- Provide web-based interface for human verification and signoff
- Enable feature-by-feature testing with guided workflows
- Support multiple verification scenarios (networking, security, performance)
- Generate verification reports with human signoff records

## Impact
- Affected specs: New interactive-verification capability
- Affected code: New simulator module, web interface, VM orchestration
- Timeline: 8 weeks for initial implementation with iterative improvements
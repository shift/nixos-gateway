# Test Plan: Data Validation Enhancements
**Source Task:** [improvements/01-data-validation-enhancements.md]
**Category:** Core / Validation

## 1. Scope

This feature enhances the `lib/validators.nix` library to provide strict type checking and schema validation for network configurations (IPs, CIDRs, MACs, Port Ranges). The goal is to ensure that invalid configurations are rejected at evaluation time, preventing broken system builds.

## 2. Verification Requirements

### 2.1 Tier 1: Functional Logic (Single Node)

*Standard NixOS VM tests for local state and evaluation time checks.*

| Req ID | Test Case | Success Criteria (Python Assertion) |
| :--- | :--- | :--- |
| REQ-VAL-01 | Valid IP Evaluation | `machine.succeed("nix-instantiate --eval -E 'import ./lib/validators.nix ... validateIP \"192.168.1.1\"'")` |
| REQ-VAL-02 | Invalid IP Rejection | `machine.fail("nix-instantiate --eval -E '... validateIP \"999.999.999.999\"'")` |
| REQ-VAL-03 | CIDR Validation | `machine.succeed("nix-instantiate --eval -E '... validateCIDR \"10.0.0.0/24\"'")` |
| REQ-VAL-04 | MAC Address Validation | `machine.succeed("nix-instantiate --eval -E '... validateMAC \"00:11:22:33:44:55\"'")` |
| REQ-VAL-05 | Service Config Integration | `machine.succeed("nixos-rebuild build")` (with valid config) |
| REQ-VAL-06 | Service Config Rejection | `machine.fail("nixos-rebuild build")` (with invalid port range in config) |

### 2.2 Tier 2: Network Simulation (Multi-Node)

*Not applicable for pure library validation logic. Verification is focused on build-time evaluation.*

| Req ID | Scenario | Topology Req | Validation Logic (Python) |
| :--- | :--- | :--- | :--- |
| N/A | N/A | N/A | N/A |

## 3. Simulation Constraints

  * **Required Nodes:** Single Node (Builder/Evaluator)
  * **Traffic Profile:** N/A (Build-time check)

# Design: Policy-Based Routing Enhancements (Task 10)

## Overview
This design implements advanced Policy-Based Routing (PBR) capabilities for the NixOS Gateway, addressing requirements for time-based routing, firewall integration, and comprehensive testing. The goal is to allow users to define routing policies based not just on destination, but on source, protocol, port, and time of day, routing traffic through specific upstream providers (tables).

## Architecture

### 1. Configuration Schema (`modules/policy-routing.nix`)
We will extend the existing `policies` option to support advanced matching criteria, specifically time-based rules, and improve the backend implementation to hybridize `ip rule` and `nftables`.

```nix
services.gateway.policyRouting.policies.<name> = {
  match = {
    # Existing: source/dest IP, port, protocol
    
    # NEW: Time-based matching
    time = {
      start = "08:00"; # UTC
      end = "17:00";   # UTC
      days = [ "Mon" "Tue" "Wed" "Thu" "Fri" ];
    };
  };
  # Action remains the same (route to table, blackhole, etc.)
}
```

### 2. Implementation Logic (`lib/policy-routing.nix`)
The routing engine will distinguish between **Simple Rules** and **Complex Rules**.

*   **Simple Rules:** Can be expressed purely with `ip rule` (e.g., source IP, TOS, fwmark).
*   **Complex Rules:** Require packet marking via `nftables` (e.g., time ranges, potentially deep packet inspection in future).

**Workflow:**
1.  **Mark Allocation:** Iterate through all policies. Assign a unique `fwmark` ID (starting at `0x1000`) to any rule that uses "Complex" criteria.
2.  **Nftables Generation:** For every Complex Rule, generate an `nftables` chain in `mangle/prerouting` that matches the criteria (e.g., `meta time`) and sets the assigned `meta mark`.
3.  **IP Rule Generation:**
    *   For Simple Rules: Generate standard `ip rule add from ... to ... lookup ...`.
    *   For Complex Rules: Generate `ip rule add fwmark <assigned_id> lookup <table_name>`.

### 3. Firewall Integration
*   The module will automatically inject `nftables` rules to allow forwarded traffic for defined policies, ensuring that PBR traffic isn't dropped by the default deny firewall.
*   We will deprecate the legacy `iptables` comments in favor of native `networking.nftables` integration.

## Testing Strategy (`tests/policy-routing-test.nix`)
We will implement a **Multi-Router Topology** to rigorously verify routing paths.

*   **Nodes:**
    *   `gateway`: The DUT (Device Under Test).
    *   `client`: Simulates a LAN device.
    *   `isp1`: Upstream Router A (Subnet 192.168.100.0/24).
    *   `isp2`: Upstream Router B (Subnet 192.168.200.0/24).
*   **Test Cases:**
    1.  **Source-Based Routing:** Traffic from `client` IP A goes to ISP1, IP B goes to ISP2.
    2.  **Port-Based Routing:** Traffic to port 80 (HTTP) goes to ISP1, port 443 (HTTPS) goes to ISP2.
    3.  **Time-Based Routing (Simulation):** Since we can't easily change system time in a live test script without side effects, we will mock the `time` match by verifying the generated configuration contains the correct `nftables` time rules and `fwmark` logic.
    4.  **Failover (Multipath):** Verify equal-cost multipath (ECMP) or weighted distribution if enabled.

## Deliverables
1.  Updated `modules/policy-routing.nix` with `nftables` integration.
2.  Updated `lib/policy-routing.nix` with complex rule logic.
3.  New `tests/policy-routing-test.nix` with the 4-node topology.

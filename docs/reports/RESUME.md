# Task 11: WireGuard Automation Test - Debug Resume

## Current Status
**Failing**: The test fails at runtime with `RequestedAssertionFailed: unit "wireguard-wg0.service" is inactive and there are no pending jobs`.

## Diagnosis
1.  **Configuration Conflict**:
    *   The configuration enables `networking.useNetworkd = true` (via `modules/network.nix`).
    *   It also defines `networking.wireguard.interfaces.wg0`.
    *   **Result**: NixOS delegates WireGuard interface creation to `systemd-networkd` (creating `.netdev` and `.network` files). It **does not** create the standalone `wireguard-wg0.service` (which is used by the script-based/wg-quick implementation).

2.  **Broken Dependencies**:
    *   **Test Script**: Explicitly waits for `wireguard-wg0.service`, which does not exist in this mode.
    *   **Module Logic (`modules/vpn.nix`)**: Defines a NAT service (`wireguard-wg0-nat`) that explicitly `bindsTo` and comes `after` `wireguard-wg0.service`. This means the NAT service will also fail or never start because its dependency is missing.

## Evidence
*   **Test Logs**: `wireguard-wg0.service` status is `not-found inactive dead`.
*   **Code**: `modules/vpn.nix` lines 139-140 hardcode the dependency:
    ```nix
    after = [ "wireguard-${cfg.wireguard.server.interface}.service" ];
    bindsTo = [ "wireguard-${cfg.wireguard.server.interface}.service" ];
    ```

## Action Plan
1.  **Fix Module (`modules/vpn.nix`)**:
    *   Update the dependency logic for the NAT service.
    *   If `networking.useNetworkd` is enabled, the NAT service should probably depend on `network-online.target` or the specific device unit `sys-subsystem-net-devices-wg0.device`, not `wireguard-wg0.service`.
    *   Alternatively, rely on `network-online.target` generally.

2.  **Fix Test (`tests/wireguard-automation-test.nix`)**:
    *   Stop waiting for `wireguard-wg0.service`.
    *   Instead, wait for the interface to appear and be "up" (e.g., `gw.wait_until_succeeds("ip link show wg0")`).
    *   Wait for `wireguard-wg0-nat.service`.

## Next Steps
Execute the plan to decouple the specific service name dependency when running under systemd-networkd.

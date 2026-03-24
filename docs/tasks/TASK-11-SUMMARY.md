# Task 11: WireGuard VPN Automation - Summary

## Status
**Completed**

## Overview
Implemented an automated framework for managing WireGuard VPNs, focusing on security (automatic key rotation), peer management, and visibility (monitoring).

## Key Components

### 1. Automation Library (`lib/wireguard-manager.nix`)
*   **Key Rotation**: `mkKeyRotationScript` logic that checks key age and automatically rotates keys if they exceed the configured interval. Backs up old keys and restarts the interface.
*   **Monitoring**: `mkMonitoringScript` that parses `wg show dump` output to provide a friendly status report of peers, including handshake recency and data transfer.
*   **Peer Helpers**: Utilities to convert peer attributes to systemd-networkd or standard WireGuard config formats.

### 2. Module Enhancement (`modules/vpn.nix`)
*   **Key Rotation Service**:
    *   Systemd service `wireguard-<interface>-key-rotation`
    *   Systemd timer running daily to check rotation validity.
    *   Configurable options: `automation.keyRotation.enable`, `interval`, `notifyBefore`.
*   **Monitoring**:
    *   Installs a `wg-monitor-<interface>` CLI tool when enabled (`monitoring.enable = true`).
    *   Integrated with standard system tools (`wireguard-tools`, `iptables`).
*   **Activation Scripts**: Improved key generation to happen during system activation, ensuring keys exist before services start.

### 3. Verification (`tests/wireguard-automation-test.nix`)
*   Verified auto-generation of keys.
*   Verified existence and execution of key rotation service/timer.
*   Verified manual triggering of key rotation works (changing the key file content).
*   Verified monitoring script installation and execution.

## Usage

### Enabling Automation
```nix
services.gateway.wireguard = {
  enable = true;
  server = {
    interface = "wg0";
    # ... standard config ...
  };
  automation = {
    keyRotation = {
      enable = true;
      interval = "90"; # Rotate every 90 days
    };
  };
  monitoring.enable = true;
};
```

### Manual Key Rotation
```bash
systemctl start wireguard-wg0-key-rotation.service
```

### Checking Status
```bash
wg-monitor-wg0
```

## Next Steps
*   Integrate with secrets management (Task 7/8) to securely store rotated keys if needed centrally.
*   Implement `peerManagement` automation to auto-add peers from an API source (placeholder added).

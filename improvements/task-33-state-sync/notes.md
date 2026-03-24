# Task 33: State Synchronization Implementation Plan

## Goal
Implement a mechanism to synchronize state (e.g., DHCP leases, connection tracking table, application state) between active and standby nodes in a high-availability cluster.

## Architecture
- **Tooling:** `syncthing` (simple, robust file sync) or `rsync` (cron/triggered).
- **Scope:**
  - Critical directories: `/var/lib/dhcp`, `/var/lib/dns` (if applicable), application data.
  - **Exclusions:** Node-specific configs (IPs, hostnames).
- **Integration:** Service that runs on both nodes, but sync direction needs care.
  - *Active -> Standby*: One-way sync is safer for active/standby.
  - `csync2` or `lsyncd` are often used for this. We will use **`lsyncd`** (Lua-based Live Syncing Daemon) wrapping rsync/ssh for real-time one-way sync from Active to Standby.

## Planned Files
1.  `modules/state-sync.nix`: Module configuring `lsyncd`.
2.  `tests/state-sync-test.nix`: Test verifying file replication.
3.  `lib/state-sync-utils.nix`: Helper logic if needed.

## Key Features
- [ ] SSH Key management (automated setup for cluster nodes? might be tricky in pure Nix without secrets, will rely on existing keys or mock).
- [ ] Configuration of sync directories.
- [ ] Service definition (`lsyncd`).

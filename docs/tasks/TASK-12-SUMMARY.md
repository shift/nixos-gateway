# Task 12: Tailscale Site-to-Site VPN Automation - Summary

## Overview
This task implemented automated site-to-site VPN configuration using Tailscale, allowing for declarative definition of mesh networks between gateway nodes.

## Key Components

### 1. Tailscale Site Manager Library (`lib/tailscale-site-manager.nix`)
A helper library that generates Tailscale configuration based on high-level site definitions.
- **`mkSiteConfig`**: Generates the necessary configuration for a site, including subnet advertising and acceptance.
- **`mkPeerConfig`**: Helper to define peer relationships (though mostly handled by Tailscale's mesh nature, this allows for future policy definitions).

### 2. Tailscale Module Enhancements (`modules/tailscale.nix`)
Updated the existing Tailscale module to support site-to-site features:
- **`services.gateway.tailscale.siteConfig`**: New option group for defining site-specific settings.
- **Subnet Routing**: Automatically configures `tailscale up` with `--advertise-routes` based on defined subnets.
- **Route Acceptance**: Automatically adds `--accept-routes` if peer sites are defined.
- **Package Injection**: Added `services.tailscale.package` to allow overriding the tailscale binary (crucial for testing).

### 3. Integration Test (`tests/tailscale-site-to-site-test.nix`)
A comprehensive VM test that verifies the automation logic.
- **Mocking**: Mocks the `tailscale` binary and `tailscaled` daemon to simulate VPN behavior without real network connectivity.
- **Verification**: Checks that the correct arguments (`--advertise-routes`, `--accept-routes`, `--auth-key`) are passed to the `tailscale up` command.
- **Service Dependency**: Ensures proper ordering of services (tailscaled, autoconnect).

## Implementation Details
- **Automated Setup**: A systemd service `tailscale-autoconnect` is created to handle the initial authentication and configuration.
- **Idempotency**: The configuration logic is designed to be declarative; changing the nix configuration updates the systemd service arguments.
- **Security**: Auth keys are handled via file paths, avoiding secrets in the nix store (except for the dummy key in the test).

## Usage Example
```nix
services.gateway.tailscale = {
  enable = true;
  authKeyFile = "/run/secrets/tailscale_key";
  siteConfig = {
    siteName = "branch-office-1";
    subnetRouters = [
      { subnet = "10.0.1.0/24"; advertise = true; }
    ];
    peerSites = [
      { name = "headquarters"; subnets = ["10.0.0.0/24"]; }
    ];
  };
};
```

## Verification
The feature was verified using `nix build .#checks.x86_64-linux.task-12-tailscale-site-to-site`, ensuring that the generated commands match the expected configuration.

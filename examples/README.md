# Example Configurations

This directory contains example configurations demonstrating different usage patterns for the NixOS Gateway framework.

## Available Examples

### [`basic-gateway.nix`](./basic-gateway.nix)

A full-featured gateway configuration with all services enabled:

- DNS (Knot + Knot Resolver)
- DHCP (Kea with DDNS integration)
- Network (multi-WAN with failover)
- Firewall (zone-based with nftables)
- IDS/IPS (Suricata with Prometheus exporter)
- Monitoring (Prometheus exporters)

**Use this when:** You need a complete router/gateway solution with all features.

**Key features demonstrated:**
- Multi-WAN setup (primary, WiFi, cellular)
- Static DHCP assignments with DNS integration
- PTR record generation
- Zone-based firewall policies
- Device type classification
- Intrusion detection with CPU affinity tuning
- Prometheus monitoring of remote hosts

### [`dns-only.nix`](./dns-only.nix)

A minimal DNS and DHCP server configuration without routing/firewall features:

- DNS (Knot Resolver + Knot Authoritative)
- DHCP (Kea with basic configuration)

**Use this when:** You need DNS/DHCP services but don't need a full gateway (e.g., on an existing network with a separate router).

**Key features demonstrated:**
- Selective module imports
- Minimal data configuration
- Running DNS/DHCP on a single interface
- Custom firewall configuration separate from gateway modules

## Example Data Files

The [`data/`](./data/) directory contains example data files showing the expected structure:

### [`network.nix`](./data/network.nix)

Network topology including:
- Subnet definitions (IPv4/IPv6)
- Gateway addresses
- DHCP pool ranges
- Management interface addresses

### [`hosts.nix`](./data/hosts.nix)

Host definitions including:
- Static DHCP assignments (IPv4/IPv6)
- MAC addresses and DUIDs
- Device types
- Monitoring configuration
- DNS records (FQDN, PTR)

### [`firewall.nix`](./data/firewall.nix)

Firewall policies including:
- Zone definitions (green/mgmt/red)
- Per-zone port allowlists
- Device type policies
- LAN isolation rules

### [`ids.nix`](./data/ids.nix)

Intrusion detection configuration including:
- Detection engine settings
- CPU affinity and threading
- Protocol-specific detection (HTTP, TLS, DNS, Modbus)
- Logging configuration
- Log rotation policies
- Prometheus exporter settings

## Using These Examples

### Option 1: Direct Import

```nix
{
  inputs.nixos-gateway.url = "github:yourorg/nixos-gateway";
  
  outputs = { nixos-gateway, ... }: {
    nixosConfigurations.gateway = nixpkgs.lib.nixosSystem {
      modules = [
        nixos-gateway.nixosModules.gateway
        (import "${nixos-gateway}/examples/basic-gateway.nix")
      ];
    };
  };
}
```

### Option 2: Copy and Customize

1. Copy the example to your configuration:
   ```bash
   cp examples/basic-gateway.nix my-gateway.nix
   cp -r examples/data/ my-data/
   ```

2. Customize for your environment:
   ```nix
   # my-gateway.nix
   { config, pkgs, ... }: {
     imports = [
       nixos-gateway.nixosModules.gateway
     ];
     
     services.gateway = {
       enable = true;
       interfaces = {
         wan = "enp1s0";      # Change to your interface names
         lan = "enp2s0";
         # ...
       };
       data = {
         network = import ./my-data/network.nix;
         hosts = import ./my-data/hosts.nix;
         # ...
       };
     };
   }
   ```

### Option 3: Use as Reference

Study the examples to understand the structure, then build your own configuration from scratch using the [main documentation](../README.md).

## Testing Examples

All examples can be tested using NixOS VM tests:

```bash
# Test basic gateway example
nix build .#checks.x86_64-linux.basic

# Test DNS/DHCP example
nix build .#checks.x86_64-linux.dns-dhcp
```

## Customization Tips

### Adapting for Different Network Sizes

**Small network (home/SOHO):**
- Use fewer CPU cores for IDS
- Reduce DHCP pool size
- Simplify firewall zones

**Large network (enterprise):**
- Increase IDS worker threads
- Use larger DHCP pools
- Add more granular firewall zones
- Enable additional monitoring

### Adapting for Different Use Cases

**Home Router:**
```nix
services.gateway = {
  data.firewall = nixos-gateway.lib.defaultFirewall;  # Simple defaults
  data.ids = {};  # Minimal IDS
};
```

**Edge Router:**
```nix
services.gateway = {
  data.ids = {
    detectEngine.profile = "high";
    threading.workerCpus = [ 2 3 4 5 6 7 ];  # More CPU
  };
  data.firewall = {
    zones.red.allowedTCPPorts = [];  # Strict WAN policy
  };
};
```

**DNS/DHCP Server (no routing):**
```nix
{
  imports = [
    nixos-gateway.nixosModules.dns
    nixos-gateway.nixosModules.dhcp
  ];
  # Don't import network, ips, or security modules
}
```

## Further Reading

- [Main Documentation](../README.md)
- [Data Schema Reference](../README.md#data-schema)
- [Module Reference](../README.md#module-reference)
- [Troubleshooting Guide](../README.md#troubleshooting)

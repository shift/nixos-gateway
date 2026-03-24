# Environment-Specific Gateway Configuration Example

This example demonstrates how to use the environment-specific override system to manage different deployment environments from a single configuration base.

## Base Configuration

```nix
# base-config.nix
{
  network = {
    subnets.lan.ipv4 = {
      subnet = "192.168.1.0/24";
      gateway = "192.168.1.1";
    };
  };
  
  hosts = {
    staticDHCPv4Assignments = [
      {
        name = "server";
        ipAddress = "192.168.1.10";
        macAddress = "aa:bb:cc:dd:ee:ff";
        type = "server";
      }
    ];
  };
  
  firewall = {
    zones.green.allowedTCPPorts = [ 22 53 80 ];
    zones.mgmt.allowedTCPPorts = [ 22 ];
  };
  
  ids = {
    detectEngine.profile = "medium";
    logging.eveLog.types = [ "alert" "http" ];
  };
}
```

## Environment-Specific Deployments

### Development Environment

```nix
# flake.nix
{
  outputs = { self, nixpkgs }: {
    nixosConfigurations.gateway-dev = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        self.nixosModules.gateway
        {
          services.gateway = {
            enable = true;
            interfaces = {
              lan = "enp1s0";
              wan = "enp2s0";
            };
            domain = "dev.local";
            
            # Use environment-specific configuration
            data = import ./lib/mk-gateway-data.nix {
              lib = nixpkgs.lib;
              networkFile = ./base-config.nix;
              environmentFile = ./examples/environments/development.nix;
              conflictStrategy = "right-wins";
            };
          };
        }
      ];
    };
  };
}
```

### Production Environment

```nix
# flake.nix
{
  outputs = { self, nixpkgs }: {
    nixosConfigurations.gateway-prod = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        self.nixosModules.gateway
        {
          services.gateway = {
            enable = true;
            interfaces = {
              lan = "enp1s0";
              wan = "enp2s0";
            };
            domain = "example.com";
            
            # Use environment-specific configuration
            data = import ./lib/mk-gateway-data.nix {
              lib = nixpkgs.lib;
              networkFile = ./base-config.nix;
              environmentFile = ./examples/environments/production.nix;
              conflictStrategy = "right-wins";
            };
          };
        }
      ];
    };
  };
}
```

## Environment Comparison

### Development vs Production

| Setting | Development | Production |
|---------|-------------|------------|
| Firewall Ports | 22,53,80,443,8080,3000,5000,9090 | 22,53,80,443 |
| IDS Profile | low | high |
| Monitoring | Full (Grafana, Prometheus, all exporters) | Essential (Grafana, Prometheus, core exporters) |
| SSH Auth | Password + Key | Key only |
| Debug Logging | Enabled | Disabled |
| Kernel Tuning | Development values | Production optimized |

## Conflict Resolution Strategies

### Right-Wins (Default)
Environment overrides take precedence over base configuration.

```nix
# Base: ports = [ 22 53 80 ]
# Environment: ports = [ 22 53 80 443 ]
# Result: ports = [ 22 53 80 443 ]
```

### Left-Wins
Base configuration takes precedence over environment overrides.

```nix
# Base: ports = [ 22 53 80 ]
# Environment: ports = [ 22 53 80 443 ]
# Result: ports = [ 22 53 80 ]
```

### Error
Fails when conflicts are detected.

```nix
# Base: ports = [ 22 53 80 ]
# Environment: ports = [ 22 53 80 443 ]
# Result: Error: Conflict detected for attribute 'ports'
```

## Environment Detection

The system can automatically detect the environment from:

1. **Environment Variable**: `NIXOS_GATEWAY_ENV=production`
2. **Build Attribute**: `environment = "production"`
3. **Fallback**: Default to "development"

```bash
# Set environment variable
export NIXOS_GATEWAY_ENV=production
nix build .#nixosConfigurations.gateway.config.system.build.toplevel
```

## Multi-Environment Management

```nix
# Build all environments from the same base
let
  baseData = import ./lib/mk-gateway-data.nix {
    lib = nixpkgs.lib;
    networkFile = ./base-config.nix;
  };
  
  environments = {
    development = import ./examples/environments/development.nix { inherit lib; };
    staging = import ./examples/environments/staging.nix { inherit lib; };
    production = import ./examples/environments/production.nix { inherit lib; };
  };
  
  buildForEnvironment = env: baseData {
    environmentFile = environments.${env};
  };
in
{
  gateway-dev = buildForEnvironment "development";
  gateway-staging = buildForEnvironment "staging";
  gateway-prod = buildForEnvironment "production";
}
```

## Best Practices

1. **Use Specific Environment Files**: Create dedicated environment files for production
2. **Validate Configurations**: Always test environment configurations before deployment
3. **Use Conflict Detection**: Enable error strategy for production builds
4. **Document Differences**: Keep clear documentation of environment differences
5. **Version Control**: Track environment configurations separately from base config

## Testing Environment Configurations

```bash
# Test environment validation
nix eval .#lib.environment.validateEnvironmentConfig \
  '(import ./examples/environments/production.nix { lib = (import <nixpkgs/lib>); })'

# Test override application
nix eval --expr '
  let
    lib = import <nixpkgs/lib>;
    env = import ./lib/environment.nix { inherit lib; };
    base = { services.gateway.data.firewall.zones.green.allowedTCPPorts = [ 22 53 80 ]; };
    prod = import ./examples/environments/production.nix { inherit lib; };
  in
  env.applyEnvironmentOverrides base prod "right-wins"
'
```
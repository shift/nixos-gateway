# Environment-Specific Gateway Configuration Examples

This directory contains examples of how to use the environment-specific override system to manage different deployment environments from a single configuration base.

## Environment Types

The framework supports four predefined environment types:

### Development (`development.nix`)
- **Purpose**: Development environment with enhanced debugging
- **Features**: 
  - Relaxed security settings
  - Debug logging enabled
  - Additional monitoring and profiling tools
  - Development packages and services
  - Password authentication for SSH
  - Firewall disabled for easier debugging

### Staging (`staging.nix`)
- **Purpose**: Production-like environment for testing
- **Features**:
  - Production-like security settings
  - Comprehensive monitoring
  - Staging-specific database and cache configurations
  - SSH key-based authentication only
  - Firewall enabled with production-like rules

### Production (`production.nix`)
- **Purpose**: Production environment optimized for performance and security
- **Features**:
  - Strict security settings
  - Optimized kernel parameters
  - Essential monitoring only
  - Minimal package set
  - Enhanced SSH security
  - Performance-tuned database and cache

### Testing (`testing.nix`)
- **Purpose**: Isolated testing environment with mock services
- **Features**:
  - Minimal security for testing
  - In-memory database configurations
  - Comprehensive debugging tools
  - Isolated networking
  - Test-specific environment variables

## Usage Examples

### Basic Usage with Environment File

```nix
# flake.nix
{
  outputs = { self, nixpkgs }: {
    nixosConfigurations = {
      gateway-dev = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./modules/gateway.nix
          {
            services.gateway.data = import ./lib/mk-gateway-data.nix {
              networkFile = ./examples/data/network.nix;
              hostsFile = ./examples/data/hosts.nix;
              firewallFile = ./examples/data/firewall.nix;
              idsFile = ./examples/data/ids.nix;
              environmentFile = ./examples/environments/development.nix;
            };
          }
        ];
      };
    };
  };
}
```

### Usage with Environment Type Only

```nix
# Using predefined environment type
{
  services.gateway.data = import ./lib/mk-gateway-data.nix {
    networkFile = ./examples/data/network.nix;
    hostsFile = ./examples/data/hosts.nix;
    firewallFile = ./examples/data/firewall.nix;
    idsFile = ./examples/data/ids.nix;
    environment = "production";  # Uses built-in defaults
    conflictStrategy = "right-wins";
  };
}
```

### Multi-Environment Configuration

```nix
# Define multiple environments from the same base
let
  baseData = import ./lib/mk-gateway-data.nix {
    networkFile = ./examples/data/network.nix;
    hostsFile = ./examples/data/hosts.nix;
    firewallFile = ./examples/data/firewall.nix;
    idsFile = ./examples/data/ids.nix;
  };
  
  environments = {
    development = import ./examples/environments/development.nix { inherit lib; };
    staging = import ./examples/environments/staging.nix { inherit lib; };
    production = import ./examples/environments/production.nix { inherit lib; };
  };
  
  environmentLib = import ./lib/environment.nix { inherit lib; };
in
{
  # Build configurations for each environment
  gateway-dev = environmentLib.buildMultiEnvironmentConfig baseData environments "development";
  gateway-staging = environmentLib.buildMultiEnvironmentConfig baseData environments "staging";
  gateway-prod = environmentLib.buildMultiEnvironmentConfig baseData environments "production";
}
```

## Override Structure

Environment configurations follow this structure:

```nix
{
  environment = "development";  # Environment type
  
  metadata = {
    description = "Environment description";
    owner = "team-name";
    contact = "team@example.com";
    version = "1.0.0";
  };
  
  overrides = {
    # Override any configuration attribute
    services.gateway.data.firewall.zones.green.allowedTCPPorts = [ 22 53 80 8080 ];
    services.gateway.monitoring.enable = true;
    boot.kernel.sysctl."net.core.rmem_max" = 134217728;
    environment.variables.NODE_ENV = "development";
  };
}
```

## Conflict Resolution

The framework supports three conflict resolution strategies:

1. **right-wins** (default): Environment overrides take precedence
2. **left-wins**: Base configuration takes precedence
3. **error**: Fail on conflicts

## Environment Detection

The system can detect the environment from:

1. `NIXOS_GATEWAY_ENV` environment variable
2. Build attributes
3. Fallback to specified default

## Testing

Run the environment override tests:

```bash
# Run evaluation tests
nix eval .#tests.environment-overrides-eval

# Run VM tests
nix build .#checks.x86_64-linux.environment-overrides-test
```

## Best Practices

1. **Use specific environment files** for production deployments
2. **Leverage built-in defaults** for development and testing
3. **Validate configurations** before deployment
4. **Use conflict detection** to identify configuration issues
5. **Document environment differences** for team visibility
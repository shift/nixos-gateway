# Module System Dependencies

**Status: Completed**

## Description
Implement proper dependency management between gateway modules to ensure services start in the correct order and handle inter-service dependencies gracefully.

## Requirements

### Current State
- Modules imported sequentially in `modules/default.nix`
- Limited explicit dependency management
- Some services may fail if dependencies aren't ready

### Improvements Needed

#### 1. Dependency Graph
- Map service dependencies (DNS → DHCP, Network → All, etc.)
- Create explicit dependency declarations
- Implement startup ordering based on dependencies
- Handle circular dependency detection

#### 2. Service Health Dependencies
- Wait for services to be fully ready before starting dependents
- Health check integration for critical services
- Automatic restart of dependent services on failures
- Graceful degradation when optional services fail

#### 3. Configuration Dependencies
- Validate that required configuration sections exist
- Cross-module configuration validation
- Automatic generation of default configurations
- Warning about missing optional dependencies

#### 4. Runtime Dependency Management
- Service discovery between modules
- Dynamic reconfiguration when dependencies change
- Fallback mechanisms for failed dependencies
- Dependency status monitoring

## Implementation Details

### Files to Modify
- `modules/default.nix` - Add dependency management
- Individual module files - Add dependency declarations
- `lib/` - Create dependency management utilities

### Dependency Declarations
```nix
moduleDependencies = {
  dns = [ "network" ];
  dhcp = [ "dns" "network" ];
  monitoring = [ "dns" "dhcp" "network" ];
  ips = [ "network" ];
};
```

### Service Integration
- Systemd service dependencies (`After=`, `Requires=`)
- Socket activation for dependent services
- Health check integration with `systemd-health`
- Restart policies for dependency failures

## Testing Requirements
- Dependency graph validation tests
- Service startup ordering tests
- Failure scenario testing
- Performance impact assessment

## Dependencies
- 01-data-validation-enhancements (for validation)

## Estimated Effort
- Medium (dependency management system)
- 1-2 weeks implementation
- 1 week testing

## Implementation Summary

### Completed Features
1. **Dependency Graph System**
   - Created comprehensive dependency mapping for all 23 modules
   - Implemented circular dependency detection
   - Added topological sorting for startup order calculation

2. **Systemd Integration**
   - Generated automatic service dependencies (`After=`, `Requires=`)
   - Created dependency wait services for each module
   - Integrated with existing systemd service management

3. **Validation Framework**
   - Added dependency validation with detailed error reporting
   - Implemented configuration assertions for dependency consistency
   - Created dependency documentation generation

4. **Testing Infrastructure**
   - Created dependency test suite
   - Added validation for dependency graph integrity
   - Verified startup order calculation works correctly

### Files Created/Modified
- `lib/dependencies.nix` - Core dependency management system
- `modules/default.nix` - Integrated dependency management
- `tests/dependency-test.nix` - Test suite for dependencies
- `flake.nix` - Added dependency test to checks

## Success Criteria
- ✅ Services start in correct order every time
- ✅ Graceful handling of service failures  
- ✅ Clear dependency documentation
- ✅ No startup regressions
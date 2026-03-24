# Configuration Templates

**Status: Completed**

## Description
Create configuration templates for common deployment patterns to simplify gateway setup for various use cases.

## Requirements

### Current State
- Manual configuration required for each deployment
- Examples exist but no template system
- No standardized deployment patterns

### Improvements Needed

#### 1. Template System
- Template engine for gateway configurations
- Parameterized templates with variable substitution
- Template inheritance and composition
- Template validation and testing

#### 2. Common Deployment Patterns
- **Small Office/Home Office (SOHO)**: Basic routing, DNS, DHCP
- **Enterprise Gateway**: Multi-WAN, VPN, IDS, monitoring
- **Cloud Edge**: Hybrid connectivity, container networking
- **ISP Gateway**: BGP, QoS, advanced routing
- **IoT Gateway**: Device isolation, specialized protocols

#### 3. Template Parameters
- Network interface mappings
- IP addressing schemes
- Security policy levels
- Service enablement flags
- Performance tuning parameters

#### 4. Template Management
- Template repository and versioning
- Template customization workflow
- Template testing and validation
- Documentation generation

## Implementation Details

### Files to Create
- `templates/` directory with template definitions
- `lib/template-engine.nix` - Template processing system
- `examples/templates/` - Example template usage

### Template Structure
```nix
# templates/soho-gateway.nix
{
  name = "SOHO Gateway";
  description = "Small office/home office gateway template";
  
  parameters = {
    lanInterface = { type = "string"; required = true; };
    wanInterface = { type = "string"; required = true; };
    domain = { type = "string"; default = "home.local"; };
    dhcpRange = { type = "object"; default = { start = "192.168.1.100"; end = "192.168.1.200"; }; };
  };
  
  config = { lanInterface, wanInterface, domain, dhcpRange, ... }: {
    services.gateway = {
      enable = true;
      interfaces = {
        lan = lanInterface;
        wan = wanInterface;
      };
      domain = domain;
      data = {
        # Generated configuration based on parameters
      };
    };
  };
}
```

### Template Functions
- Template instantiation and validation
- Parameter type checking
- Configuration generation
- Template composition

## Testing Requirements
- Template validation tests
- Parameter substitution tests
- Generated configuration tests
- Template inheritance tests

## Dependencies
- 01-data-validation-enhancements

## Estimated Effort
- Medium (template system)
- 2 weeks implementation
- 1 week testing

## Success Criteria
- Common deployments configurable with minimal parameters
- Template validation prevents invalid configurations
- Clear template documentation
- Easy template customization workflow
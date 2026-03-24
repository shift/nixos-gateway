# VRF (Virtual Routing and Forwarding) Support

**Status: Pending**

## Description
Implement VRF support for true Layer 3 isolation, enabling overlapping IP ranges and management plane isolation.

## Requirements

### Current State
- Using VLANs for Layer 2 separation only
- Single routing table shared across all VLANs
- Firewall rules for inter-VLAN traffic control
- No support for overlapping IP subnets

### Improvements Needed

#### 1. VRF Creation and Management
- Automated VRF device creation
- Interface assignment to VRFs
- Routing table isolation per VRF
- VRF-specific firewall rules

#### 2. Overlapping IP Support
- Multiple VRFs with same IP ranges
- Route leaking between VRFs (controlled)
- VRF-aware NAT and forwarding
- Inter-VRF communication policies

#### 3. Management Isolation
- Dedicated management VRF
- Out-of-band management access
- VRF isolation for security
- Emergency access mechanisms

#### 4. VRF Routing Protocols
- VRF-aware BGP/OSPF configuration
- Per-VRF routing tables
- Route redistribution between VRFs
- VRF-specific routing policies

## Implementation Details

### Files to Create
- `modules/vrf.nix` - VRF management module
- `lib/vrf-config.nix` - VRF configuration functions
- `lib/vrf-routing.nix` - VRF routing helpers

### New Configuration Options
```nix
networking.vrfs = lib.mkOption {
  type = lib.types.attrsOf (lib.types.submodule {
    options = {
      enable = lib.mkEnableOption "VRF";
      
      interfaces = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = "Interfaces assigned to this VRF";
      };
      
      table = lib.mkOption {
        type = lib.types.int;
        description = "Routing table number for this VRF";
      };
      
      routing = {
        enable = lib.mkEnableOption "VRF routing protocols";
        
        bgp = {
          enable = lib.mkEnableOption "VRF BGP";
          asn = lib.mkOption { type = lib.types.int; };
          neighbors = lib.mkOption { type = lib.types.attrs; };
        };
        
        static = lib.mkOption {
          type = lib.types.listOf (lib.types.submodule {
            options = {
              destination = lib.mkOption { type = lib.types.str; };
              gateway = lib.mkOption { type = lib.types.str; };
              metric = lib.mkOption { type = lib.types.int; default = 100; };
            };
          });
        };
      };
      
      firewall = {
        enable = lib.mkEnableOption "VRF firewall";
        rules = lib.mkOption { type = lib.types.listOf lib.types.attrs; };
        zones = lib.mkOption { type = lib.types.attrs; };
      };
      
      nat = {
        enable = lib.mkEnableOption "VRF NAT";
        rules = lib.mkOption { type = lib.types.listOf lib.types.attrs; };
      };
    };
  });
  description = "Virtual Routing and Forwarding instances";
};
```

### Integration Points
- Network module for interface management
- Firewall module for VRF-specific rules
- FRR module for VRF routing protocols
- Monitoring for VRF status

## Testing Requirements
- Overlapping IP range configuration
- VRF isolation testing
- Inter-VRF communication policies
- Management VRF access control

## Dependencies
- Linux kernel >= 4.3 (VRF support)
- iproute2 with VRF support
- VRF-aware network services

## Estimated Effort
- High (complex networking changes)
- 3-4 weeks implementation
- 2 weeks testing and validation

## Success Criteria
- Multiple VRFs with overlapping IPs working
- Complete routing table isolation
- Management VRF inaccessible from traffic VRFs
- VRF-aware routing protocols functional
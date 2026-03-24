# IPv6 Transition Mechanisms (NAT64/DNS64)

**Status: Pending**

## Description
Implement IPv6-only LAN support with NAT64/DNS64 for IPv4 internet access, enabling future-proof network architecture.

## Requirements

### Current State
- Dual-stack or IPv4-focused networking
- No IPv6-only internal network support
- Limited IPv6 transition mechanisms
- Complex address management

### Improvements Needed

#### 1. NAT64 Implementation
- IPv6 to IPv4 protocol translation
- Stateful NAT64 with Jool/Tayga
- Prefix management and allocation
- Performance optimization

#### 2. DNS64 Configuration
- IPv4 address synthesis for IPv6-only clients
- DNS64 server configuration
- DNS64/NAT64 coordination
- Fallback to traditional DNS

#### 3. IPv6-Only Network Management
- IPv6-only internal addressing
- Router advertisements configuration
- DHCPv6 for address assignment
- IPv6 firewall rules

#### 4. Transition Monitoring
- NAT64/DNS64 performance monitoring
- Translation statistics
- Error tracking and alerting
- IPv6 adoption metrics

## Implementation Details

### Files to Create
- `modules/nat64.nix` - NAT64 translation module
- `modules/dns64.nix` - DNS64 server module
- `lib/ipv6-transition.nix` - IPv6 transition helpers
- `lib/nat64-config.nix` - NAT64 configuration

### New Configuration Options
```nix
networking.ipv6 = {
  only = lib.mkEnableOption "IPv6-only internal network";
  
  nat64 = {
    enable = lib.mkEnableOption "NAT64 translation";
    
    prefix = lib.mkOption {
      type = lib.types.str;
      default = "64:ff9b::/96";
      description = "NAT64 prefix for IPv4-mapped IPv6 addresses";
    };
    
    implementation = lib.mkOption {
      type = lib.types.enum [ "jool" "tayga" ];
      default = "jool";
      description = "NAT64 implementation";
    };
    
    pool = lib.mkOption {
      type = lib.types.str;
      description = "IPv4 address pool for NAT64";
    };
    
    performance = {
      maxSessions = lib.mkOption {
        type = lib.types.int;
        default = 65536;
        description = "Maximum concurrent NAT64 sessions";
      };
      
      timeout = lib.mkOption {
        type = lib.types.int;
        default = 300;
        description = "Session timeout in seconds";
      };
    };
  };
  
  dns64 = {
    enable = lib.mkEnableOption "DNS64 synthesis";
    
    server = {
      enable = lib.mkEnableOption "Local DNS64 server";
      
      listen = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "[::1]:53" ];
        description = "DNS64 server listen addresses";
      };
      
      upstream = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "8.8.8.8" "8.8.4.4" ];
        description = "Upstream DNS servers";
      };
      
      prefix = lib.mkOption {
        type = lib.types.str;
        default = "64:ff9b::/96";
        description = "DNS64 synthesis prefix";
      };
    };
    
    client = {
      enable = lib.mkEnableOption "DNS64 client configuration";
      
      servers = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "::1" ];
        description = "DNS64 servers for clients";
      };
    };
  };
  
  addressing = {
    mode = lib.mkOption {
      type = lib.types.enum [ "slaac" "dhcpv6" "static" ];
      default = "slaac";
      description = "IPv6 address assignment mode";
    };
    
    prefix = lib.mkOption {
      type = lib.types.str;
      description = "IPv6 prefix for internal network";
    };
    
    routerAdvertisements = {
      enable = lib.mkEnableOption "Router advertisements";
      
      interval = lib.mkOption {
        type = lib.types.int;
        default = 200;
        description = "RA interval in seconds";
      };
      
      managed = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Managed flag (DHCPv6)";
      };
      
      other = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Other configuration flag";
      };
    };
  };
  
  firewall = {
    enable = lib.mkEnableOption "IPv6 firewall";
    
    rules = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [];
      description = "IPv6 firewall rules";
    };
    
    nat64 = {
      allowForwarding = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Allow NAT64 forwarding";
      };
      
      restrictAccess = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Restrict NAT64 to internal networks";
      };
    };
  };
  
  monitoring = {
    enable = lib.mkEnableOption "IPv6 transition monitoring";
    
    nat64 = {
      enable = lib.mkEnableOption "NAT64 monitoring";
      
      metrics = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "sessions" "translations" "errors" "performance" ];
        description = "NAT64 metrics to collect";
      };
    };
    
    dns64 = {
      enable = lib.mkEnableOption "DNS64 monitoring";
      
      metrics = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "queries" "synthesis" "cache" "errors" ];
        description = "DNS64 metrics to collect";
      };
    };
  };
};
```

### Integration Points
- Network module for interface configuration
- Firewall module for IPv6 rules
- DNS module for DNS64 integration
- Monitoring module for transition metrics

## Testing Requirements
- IPv6-only client connectivity
- NAT64 translation accuracy
- DNS64 synthesis functionality
- IPv4 internet access from IPv6-only clients
- Performance under load

## Dependencies
- Jool or Tayga for NAT64
- BIND or Unbound with DNS64 support
- radvd for router advertisements
- DHCPv6 server (if using DHCPv6)

## Estimated Effort
- High (complex protocol translation)
- 3-4 weeks implementation
- 2 weeks testing and validation

## Success Criteria
- IPv6-only clients access IPv4 internet
- Transparent NAT64/DNS64 operation
- Performance comparable to native IPv4
- Comprehensive monitoring and troubleshooting
- Zero-configuration client experience
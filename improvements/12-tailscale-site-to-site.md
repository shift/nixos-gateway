# Tailscale Site-to-Site

**Status: Completed**

## Description
Implement Tailscale integration for site-to-site connectivity with automatic subnet routing and ACL management.

## Requirements

### Current State
- Basic Tailscale module exists
- Limited site-to-site configuration
- No automated subnet routing

### Improvements Needed

#### 1. Site-to-Site Integration
- Automatic subnet advertisement
- Inter-site routing configuration
- ACL policy management
- Network topology discovery

#### 2. Subnet Routing
- Automatic subnet router setup
- Route advertisement control
- Access control lists
- Traffic filtering between sites

#### 3. Advanced Features
- Exit node configuration
- DNS integration across sites
- Failover and redundancy
- Performance optimization

#### 4. Management and Monitoring
- Tailscale API integration
- Network status monitoring
- Connection analytics
- Security event logging

## Implementation Details

### Files to Modify
- `modules/tailscale.nix` - Enhance existing Tailscale module
- `lib/tailscale-site-manager.nix` - Site management utilities

### Site-to-Site Configuration
```nix
services.gateway.tailscale = {
  enable = true;
  authKey = "encrypted-auth-key";
  
  siteConfig = {
    siteName = "datacenter-1";
    region = "us-west";
    
    subnetRouters = [
      {
        subnet = "192.168.1.0/24";
        advertise = true;
        exitNode = false;
      }
      {
        subnet = "10.0.0.0/24";
        advertise = true;
        exitNode = true;
      }
    ];
    
    aclPolicies = {
      groups = {
        "group:servers" = [ "server1" "server2" ];
        "group:clients" = [ "client:*" ];
      };
      
      acls = [
        {
          action = "accept";
          src = [ "group:servers" ];
          dst = [ "*" ];
        }
        {
          action = "accept";
          src = [ "group:clients" ];
          dst = [ "autogroup:internet" ];
        }
      ];
    };
    
    peerSites = [
      {
        name = "datacenter-2";
        subnets = [ "192.168.2.0/24" ];
        trustLevel = "full";
      }
    ];
  };
  
  automation = {
    subnetDiscovery = true;
    routePropagation = true;
    aclSync = true;
    
    monitoring = {
      connectionHealth = true;
      trafficStats = true;
      latencyMonitoring = true;
    };
  };
  
  integration = {
    dns = {
      enable = true;
      searchDomains = [ "ts.net" "internal.local" ];
    };
    
    firewall = {
      autoGenerateRules = true;
      allowTailscaleTraffic = true;
    };
  };
};
```

### Integration Points
- Network module integration
- DNS module integration
- Firewall module integration
- Monitoring module integration

## Testing Requirements
- Site-to-site connectivity tests
- Subnet routing validation
- ACL enforcement tests
- Failover scenario tests

## Dependencies
- 02-module-system-dependencies
- 07-secrets-management-integration

## Estimated Effort
- Medium (Tailscale integration)
- 2 weeks implementation
- 1 week testing

## Success Criteria
- Automatic site-to-site connectivity
- Proper subnet routing between sites
- Effective ACL enforcement
- Comprehensive monitoring
## Implementation Summary (Dec 12 2025)

- Enhanced `modules/tailscale.nix` to support:
  - ACL Policy generation via `tailscale-acl-gen.service`
  - Automatic site tagging (`tag:site-<name>`)
  - Subnet route advertisement integration
- Verified with `tests/tailscale-site-to-site-test.nix` checking script generation and ACL output.

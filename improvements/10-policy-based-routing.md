# Policy-Based Routing

**Status: Completed**

## Description
Implement policy-based routing (PBR) to route traffic based on source address, protocol, or other criteria beyond destination.

## Requirements

### Current State
- Basic destination-based routing
- No traffic classification for routing decisions
- Limited traffic engineering capabilities

### Improvements Needed

#### 1. Traffic Classification
- Source-based routing rules
- Protocol-specific routing
- Application-based traffic identification
- QoS-based routing decisions

#### 2. Routing Policies
- Multiple routing tables
- Rule-based traffic selection
- Route selection priorities
- Failover and backup paths

#### 3. Advanced Features
- Traffic engineering and load balancing
- Application-aware routing
- Time-based routing policies
- Dynamic policy updates

#### 4. Integration and Monitoring
- Integration with existing network module
- Policy effectiveness monitoring
- Traffic analytics and reporting
- Policy validation and testing

## Implementation Details

### Files to Create
- `modules/policy-routing.nix` - PBR implementation
- `lib/policy-engine.nix` - Policy management utilities

### Policy Configuration
```nix
services.gateway.policyRouting = {
  enable = true;
  
  routingTables = {
    table100 = { name = "ISP1"; priority = 100; };
    table200 = { name = "ISP2"; priority = 200; };
    table300 = { name = "VPN"; priority = 300; };
  };
  
  policies = {
    "voip-traffic" = {
      priority = 1000;
      rules = [
        {
          match = {
            protocol = "udp";
            sourcePort = 5060;  // SIP
          };
          action = "route";
          table = "table100";
        }
      ];
    };
    
    "vpn-traffic" = {
      priority = 2000;
      rules = [
        {
          match = {
            destinationNetwork = "10.0.0.0/8";
          };
          action = "route";
          table = "table300";
        }
      ];
    };
    
    "load-balance" = {
      priority = 3000;
      rules = [
        {
          match = {
            sourceAddress = "192.168.1.0/24";
          };
          action = "multipath";
          tables = [ "table100" "table200" ];
          weights = { table100 = 70; table200 = 30; };
        }
      ];
    };
  };
  
  monitoring = {
    enable = true;
    metrics = {
      policyHits = true;
      trafficByPolicy = true;
      tableUtilization = true;
    };
  };
};
```

### Integration Points
- Network module integration
- QoS module integration
- Monitoring module integration
- Firewall rule coordination

## Testing Requirements
- Policy rule matching tests
- Traffic routing validation
- Failover scenario tests
- Performance impact assessment

## Dependencies
- 02-module-system-dependencies
- 13-advanced-qos-policies

## Estimated Effort
- High (complex routing policies)
- 3 weeks implementation
- 2 weeks testing

## Success Criteria
- Traffic routed according to policies
- Fast policy rule processing
- Seamless failover between paths
- Comprehensive policy monitoring
# Advanced QoS Policies

**Status: Pending**

## Description
Implement sophisticated Quality of Service policies beyond basic DSCP marking, including application-aware traffic shaping and bandwidth management.

## Requirements

### Current State
- Basic QoS module exists
- Simple DSCP marking
- Limited traffic classification

### Improvements Needed

#### 1. Traffic Classification
- Deep packet inspection for application identification
- Protocol-specific traffic analysis
- User/role-based traffic classification
- Time-based traffic categorization

#### 2. Bandwidth Management
- Per-application bandwidth limits
- Dynamic bandwidth allocation
- Priority-based queuing
- Fairness algorithms

#### 3. Advanced Shaping
- Hierarchical token bucket (HTB)
- Class-based queuing (CBQ)
- Traffic policing and shaping
- Burst handling

#### 4. Policy Management
- QoS policy templates
- Dynamic policy updates
- Policy effectiveness monitoring
- Automated policy optimization

## Implementation Details

### Files to Modify
- `modules/qos.nix` - Enhance existing QoS module
- `lib/traffic-classifier.nix` - Traffic classification utilities

### Advanced QoS Configuration
```nix
services.gateway.qos = {
  enable = true;
  
  interfaces = {
    lan = "eth1";
    wan = "eth0";
  };
  
  trafficClasses = {
    "voip" = {
      priority = 1;
      maxBandwidth = "2Mbps";
      guaranteedBandwidth = "1Mbps";
      protocols = [ "sip" "rtp" "srtp" ];
      dscp = 46; // EF
    };
    
    "video" = {
      priority = 2;
      maxBandwidth = "10Mbps";
      guaranteedBandwidth = "5Mbps";
      applications = [ "zoom" "teams" "webex" ];
      dscp = 34; // AF41
    };
    
    "gaming" = {
      priority = 3;
      maxBandwidth = "5Mbps";
      guaranteedBandwidth = "2Mbps";
      applications = [ "steam" "epic-games" "xbox-live" ];
      dscp = 26; // AF31
    };
    
    "bulk" = {
      priority = 5;
      maxBandwidth = "50Mbps";
      guaranteedBandwidth = "1Mbps";
      applications = [ "torrents" "downloads" "backups" ];
      dscp = 8; // AF11
    };
  };
  
  policies = {
    "work-hours" = {
      schedule = "Mon-Fri 09:00-17:00";
      rules = [
        {
          match = { user = "employee:*"; };
          action = { class = "video"; priority = 2; };
        }
        {
          match = { application = "social-media"; };
          action = { class = "bulk"; maxBandwidth = "1Mbps"; };
        }
      ];
    };
    
    "after-hours" = {
      schedule = "Mon-Fri 17:01-08:59 Sat-Sun";
      rules = [
        {
          match = { application = "backups"; };
          action = { class = "bulk"; maxBandwidth = "80Mbps"; };
        }
      ];
    };
  };
  
  monitoring = {
    enable = true;
    metrics = {
      classUtilization = true;
      applicationBandwidth = true;
      policyEffectiveness = true;
    };
  };
};
```

### Integration Points
- Network module integration
- Traffic classification engine
- Monitoring module integration
- Policy management interface

## Testing Requirements
- Traffic classification accuracy tests
- Bandwidth allocation validation
- Policy effectiveness tests
- Performance impact assessment

## Dependencies
- 02-module-system-dependencies
- 03-service-health-checks

## Estimated Effort
- High (complex QoS system)
- 3 weeks implementation
- 2 weeks testing

## Success Criteria
- Accurate application traffic identification
- Effective bandwidth allocation
- Fair resource distribution
- Comprehensive QoS monitoring
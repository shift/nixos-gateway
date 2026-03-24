# SD-WAN Traffic Engineering with Jitter-Based Steering

**Status: Pending**

## Description
Implement quality-based routing for SD-WAN functionality that routes traffic based on link quality metrics (jitter, latency, loss) rather than simple failover.

## Requirements

### Current State
- Basic failover (switch if link is down)
- Round-robin load balancing
- No consideration of link quality
- Static routing decisions

### Improvements Needed

#### 1. Link Quality Monitoring
- Real-time jitter measurement
- Latency monitoring and tracking
- Packet loss detection
- Bandwidth utilization monitoring
- Historical quality data collection

#### 2. Dynamic Route Metrics
- Automatic route metric adjustment
- Quality-based path selection
- Application-specific routing policies
- Real-time route updates

#### 3. Traffic Classification
- Application identification (VoIP, video, bulk)
- QoS class mapping
- Performance requirement mapping
- Policy-based traffic steering

#### 4. SD-WAN Controller
- Centralized quality management
- Multi-link coordination
- Policy enforcement
- Performance optimization

## Implementation Details

### Files to Create
- `modules/sdwan.nix` - SD-WAN controller module
- `lib/quality-monitoring.nix` - Link quality monitoring
- `lib/traffic-classification.nix` - Traffic classification
- `lib/dynamic-routing.nix` - Dynamic route management

### New Configuration Options
```nix
routing.policy = {
  enable = lib.mkEnableOption "SD-WAN traffic engineering";
  
  links = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        interface = lib.mkOption {
          type = lib.types.str;
          description = "Network interface";
        };
        
        weight = lib.mkOption {
          type = lib.types.int;
          default = 1;
          description = "Link weight for load balancing";
        };
        
        priority = lib.mkOption {
          type = lib.types.int;
          default = 100;
          description = "Link priority for failover";
        };
        
        quality = {
          maxLatency = lib.mkOption {
            type = lib.types.str;
            default = "100ms";
            description = "Maximum acceptable latency";
          };
          
          maxJitter = lib.mkOption {
            type = lib.types.str;
            default = "30ms";
            description = "Maximum acceptable jitter";
          };
          
          maxLoss = lib.mkOption {
            type = lib.types.str;
            default = "1%";
            description = "Maximum acceptable packet loss";
          };
          
          minBandwidth = lib.mkOption {
            type = lib.types.str;
            default = "1Mbps";
            description = "Minimum available bandwidth";
          };
        };
      };
    });
    description = "SD-WAN link definitions";
  };
  
  applications = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        protocol = lib.mkOption {
          type = lib.types.enum [ "tcp" "udp" "icmp" ];
          description = "Application protocol";
        };
        
        ports = lib.mkOption {
          type = lib.types.listOf lib.types.port;
          description = "Application ports";
        };
        
        requirements = {
          maxLatency = lib.mkOption {
            type = lib.types.str;
            description = "Maximum latency requirement";
          };
          
          maxJitter = lib.mkOption {
            type = lib.types.str;
            description = "Maximum jitter requirement";
          };
          
          minBandwidth = lib.mkOption {
            type = lib.types.str;
            description = "Minimum bandwidth requirement";
          };
        };
        
        priority = lib.mkOption {
          type = lib.types.enum [ "low" "medium" "high" "critical" ];
          default = "medium";
          description = "Application priority";
        };
      };
    });
    description = "Application traffic profiles";
  };
  
  monitoring = {
    enable = lib.mkEnableOption "SD-WAN monitoring";
    
    interval = lib.mkOption {
      type = lib.types.str;
      default = "5s";
      description = "Quality monitoring interval";
    };
    
    history = lib.mkOption {
      type = lib.types.int;
      default = 3600;
      description = "History retention time in seconds";
    };
    
    prometheus = {
      enable = lib.mkEnableOption "Prometheus metrics export";
      port = lib.mkOption {
        type = lib.types.port;
        default = 9092;
        description = "Prometheus metrics port";
      };
    };
  };
  
  controller = {
    enable = lib.mkEnableOption "SD-WAN controller";
    
    mode = lib.mkOption {
      type = lib.types.enum [ "active" "passive" "hybrid" ];
      default = "active";
      description = "Controller mode";
    };
    
    decisionInterval = lib.mkOption {
      type = lib.types.str;
      default = "10s";
      description = "Route decision interval";
    };
    
    failover = {
      enable = lib.mkEnableOption "Automatic failover";
      
      threshold = lib.mkOption {
        type = lib.types.int;
        default = 3;
        description = "Consecutive failures before failover";
      };
      
      recoveryTime = lib.mkOption {
        type = lib.types.str;
        default = "60s";
        description = "Time before attempting recovery";
      };
    };
  };
};
```

### Integration Points
- Network module for interface management
- Monitoring module for metrics collection
- QoS module for traffic shaping
- Health checks for link monitoring

## Testing Requirements
- Link quality measurement accuracy
- Dynamic route updates
- Application-specific routing
- Failover and recovery scenarios
- Performance under load

## Dependencies
- iproute2 with advanced routing
- Quality monitoring tools (ping, fping, iperf)
- Traffic classification (nDPI, libprotoident)
- Time synchronization (NTP/chrony)

## Estimated Effort
- High (complex real-time system)
- 4-5 weeks implementation
- 3 weeks testing and optimization

## Success Criteria
- Sub-second quality measurement
- Automatic route optimization
- Application-aware traffic steering
- Seamless failover and recovery
- Comprehensive monitoring and alerting
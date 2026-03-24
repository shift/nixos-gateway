# Distributed Tracing

**Status: Pending**

## Description
Implement distributed tracing for network flows and service requests to provide end-to-end visibility and performance analysis.

## Requirements

### Current State
- Basic metrics collection
- No request tracing
- Limited performance visibility

### Improvements Needed

#### 1. Tracing Framework
- OpenTelemetry integration
- Span generation and collection
- Trace context propagation
- Sampling strategies

#### 2. Service Tracing
- **DNS**: Query resolution traces
- **DHCP**: Lease assignment traces
- **Network**: Packet flow tracing
- **IDS**: Rule processing traces
- **VPN**: Connection establishment traces

#### 3. Network Flow Tracing
- End-to-end flow tracking
- Path analysis and latency
- Protocol-specific tracing
- Performance bottleneck identification

#### 4. Analysis and Visualization
- Trace search and filtering
- Performance analysis tools
- Dependency mapping
- Anomaly detection

## Implementation Details

### Files to Create
- `modules/distributed-tracing.nix` - Tracing framework
- `lib/trace-collector.nix` - Trace collection utilities

### Tracing Configuration
```nix
services.gateway.tracing = {
  enable = true;
  
  collector = {
    endpoint = "http://jaeger:14268/api/traces";
    protocol = "http";
    
    sampling = {
      strategy = "probabilistic";
      probability = 0.1;  // 10% sampling
      
      serviceOverrides = {
        dns = { probability = 0.05; };
        dhcp = { probability = 0.02; };
        network = { probability = 0.01; };
        ids = { probability = 0.5; };
      };
    };
    
    batch = {
      timeout = "5s";
      batchSize = 100;
      maxPacketSize = 1048576;
    };
  };
  
  services = {
    dns = {
      enable = true;
      
      spans = {
        "query-resolution" = {
          operations = [ "resolve" "forward" "authoritative" ];
          attributes = [
            "query.name"
            "query.type"
            "response.code"
            "cache.hit"
          ];
        };
        
        "zone-transfer" = {
          operations = [ "axfr" "ixfr" ];
          attributes = [
            "zone.name"
            "transfer.type"
            "record.count"
          ];
        };
      };
    };
    
    dhcp = {
      enable = true;
      
      spans = {
        "lease-assignment" = {
          operations = [ "discover" "offer" "request" "ack" ];
          attributes = [
            "client.mac"
            "client.ip"
            "lease.duration"
            "reservation.type"
          ];
        };
        
        "ddns-update" = {
          operations = [ "update" "delete" ];
          attributes = [
            "record.name"
            "record.type"
            "update.result"
          ];
        };
      };
    };
    
    network = {
      enable = true;
      
      spans = {
        "packet-processing" = {
          operations = [ "ingress" "routing" "egress" ];
          attributes = [
            "packet.src_ip"
            "packet.dst_ip"
            "packet.protocol"
            "routing.decision"
          ];
        };
        
        "nat-translation" = {
          operations = [ "snat" "dnat" ];
          attributes = [
            "nat.original_ip"
            "nat.translated_ip"
            "nat.protocol"
          ];
        };
      };
    };
    
    ids = {
      enable = true;
      
      spans = {
        "rule-evaluation" = {
          operations = [ "match" "alert" "drop" ];
          attributes = [
            "rule.sid"
            "rule.action"
            "packet.signature"
            "alert.severity"
          ];
        };
        
        "suricata-processing" = {
          operations = [ "decode" "detect" "output" ];
          attributes = [
            "packet.size"
            "processing.time"
            "cpu.usage"
          ];
        };
      };
    };
  };
  
  networkFlows = {
    enable = true;
    
    tracing = {
      flowTimeout = "30s";
      maxFlows = 100000;
      
      attributes = [
        "flow.src_ip"
        "flow.dst_ip"
        "flow.src_port"
        "flow.dst_port"
        "flow.protocol"
        "flow.bytes"
        "flow.packets"
        "flow.duration"
      ];
    };
    
    sampling = {
      strategy = "flow-based";
      sampleRate = 1000;  // 1 in 1000 flows
      
      filters = [
        { protocol = "tcp"; sampleRate = 500; }
        { dstPort = 443; sampleRate = 100; }
        { dstPort = 22; sampleRate = 50; }
      ];
    };
  };
  
  analysis = {
    enable = true;
    
    performance = {
      latencyThresholds = {
        dns = "100ms";
        dhcp = "1s";
        network = "10ms";
        ids = "1ms";
      };
      
      anomalyDetection = {
        enable = true;
        algorithm = "statistical";
        sensitivity = 0.95;
      };
    };
    
    dependencies = {
      autoDiscovery = true;
      updateInterval = "5m";
      
      mapping = {
        services = true;
        networks = true;
        protocols = true;
      };
    };
  };
  
  integration = {
    jaeger = {
      enable = true;
      endpoint = "http://jaeger:16686";
    };
    
    prometheus = {
      enable = true;
      metrics = [
        "trace_duration_seconds"
        "trace_spans_total"
        "trace_errors_total"
      ];
    };
    
    grafana = {
      enable = true;
      dashboards = [
        "tracing-overview"
        "service-performance"
        "network-flows"
      ];
    };
  };
};
```

### Integration Points
- All service modules
- Monitoring module integration
- Jaeger/Tempo integration
- Grafana dashboard integration

## Testing Requirements
- Trace collection accuracy tests
- Performance impact assessment
- Sampling strategy validation
- Analysis tool functionality tests

## Dependencies
- 03-service-health-checks
- 19-health-monitoring

## Estimated Effort
- High (complex tracing system)
- 4 weeks implementation
- 3 weeks testing

## Success Criteria
- Complete end-to-end trace visibility
- Minimal performance overhead
- Effective trace analysis tools
- Accurate dependency mapping
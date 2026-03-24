# Log Aggregation

**Status: Pending**

## Description
Implement comprehensive log aggregation with structured logging, log parsing, and centralized collection for all gateway services.

## Requirements

### Current State
- Basic local logging
- No log aggregation
- Limited log analysis capabilities

### Improvements Needed

#### 1. Log Collection Framework
- Structured logging (JSON format)
- Centralized log collection
- Log shipping and buffering
- Log retention policies

#### 2. Service Log Integration
- **DNS**: Query logs, zone transfers, errors
- **DHCP**: Lease assignments, renewals, errors
- **Network**: Connection logs, routing changes
- **IDS**: Alert logs, rule matches, performance
- **System**: Service logs, audit logs

#### 3. Log Processing and Analysis
- Log parsing and field extraction
- Log enrichment and correlation
- Log-based metrics generation
- Anomaly detection in logs

#### 4. Search and Visualization
- Log search and filtering
- Log dashboards and visualizations
- Log-based alerting
- Compliance reporting

## Implementation Details

### Files to Create
- `modules/log-aggregation.nix` - Log aggregation framework
- `lib/log-processor.nix` - Log processing utilities

### Log Aggregation Configuration
```nix
services.gateway.logAggregation = {
  enable = true;
  
  collector = {
    type = "fluent-bit";
    
    inputs = [
      {
        name = "systemd";
        tag = "systemd.*";
        path = "/var/log/journal";
        maxLines = 1000;
        readFromHead = true;
      }
      {
        name = "tail";
        tag = "dns.*";
        path = "/var/log/knot/*.log";
        parser = "dns";
      }
      {
        name = "tail";
        tag = "dhcp.*";
        path = "/var/log/kea/*.log";
        parser = "dhcp";
      }
      {
        name = "tail";
        tag = "ids.*";
        path = "/var/log/suricata/*.log";
        parser = "suricata";
      }
    ];
    
    outputs = [
      {
        name = "elasticsearch";
        match = "*";
        host = "elasticsearch:9200";
        index = "gateway-logs";
        timeKey = "@timestamp";
      }
    ];
    
    filters = [
      {
        name = "parser";
        match = "dns.*";
        keyName = "message";
        parser = "dns";
      }
      {
        name = "parser";
        match = "dhcp.*";
        keyName = "message";
        parser = "dhcp";
      }
      {
        name = "enrich";
        match = "*";
        add = {
          hostname = "${config.networking.hostName}";
          environment = "production";
        };
      }
    ];
  };
  
  parsers = {
    dns = {
      type = "regex";
      regex = '^(?<timestamp>\w+\s+\d+\s+\d+:\d+:\d+)\s+(?<level>\w+)\s+(?<message>.*)$';
      timeKey = "timestamp";
      timeFormat = "%b %d %H:%M:%S";
      
      fields = {
        query_type = { type = "string"; pattern = "type=(?<query_type>\w+)"; };
        query_name = { type = "string"; pattern = "name=(?<query_name>[^s]+)"; };
        response_code = { type = "integer"; pattern = "rcode=(?<response_code>\d+)"; };
      };
    };
    
    dhcp = {
      type = "regex";
      regex = '^(?<timestamp>\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d+)\s+\[(?<level>\w+)\]\s+(?<message>.*)$';
      timeKey = "timestamp";
      timeFormat = "%Y-%m-%d %H:%M:%S.%f";
      
      fields = {
        client_mac = { type = "string"; pattern = "mac=(?<client_mac>[0-9a-f:]+)"; };
        client_ip = { type = "ip"; pattern = "ip=(?<client_ip>\d+\.\d+\.\d+\.\d+)"; };
        lease_duration = { type = "integer"; pattern = "lease=(?<lease_duration>\d+)"; };
      };
    };
    
    suricata = {
      type = "json";
      timeKey = "timestamp";
      timeFormat = "%Y-%m-%dT%H:%M:%S.%f%z";
      
      fields = {
        alert = { type = "object"; };
        flow = { type = "object"; };
        src_ip = { type = "ip"; path = "src_ip"; };
        dst_ip = { type = "ip"; path = "dst_ip"; };
        alert_signature = { type = "string"; path = "alert.signature"; };
        alert_severity = { type: "integer"; path = "alert.severity"; };
      };
    };
  };
  
  retention = {
    policies = {
      "system-logs" = {
        match = "systemd.*";
        retention = "30d";
        compression = true;
      };
      
      "service-logs" = {
        match = "dns.* dhcp.* ids.*";
        retention = "90d";
        compression = true;
      };
      
      "audit-logs" = {
        match = "*audit*";
        retention = "365d";
        compression = true;
      };
    };
    
    cleanup = {
      schedule = "daily";
      batchSize = 1000;
      maxDiskUsage = "80%";
    };
  };
  
  monitoring = {
    enable = true;
    
    metrics = {
      logVolume = true;
      errorRates = true;
      parsingErrors = true;
      bufferUtilization = true;
    };
    
    alerting = {
      highErrorRate = {
        threshold = "5%";
        window = "5m";
        severity = "warning";
      };
      
      parsingErrors = {
        threshold = "10/min";
        window = "1m";
        severity = "critical";
      };
      
      bufferFull = {
        threshold = "90%";
        window = "1m";
        severity = "critical";
      };
    };
  };
  
  search = {
    enable = true;
    
    indexes = [
      {
        name = "gateway-logs";
        pattern = "gateway-logs-*";
        timeField = "@timestamp";
      }
    ];
    
    dashboards = [
      {
        name = "Service Logs";
        panels = [
          { title: "DNS Query Volume"; type: "count"; query: "service:dns"; }
          { title: "DHCP Lease Activity"; type: "count"; query: "service:dhcp"; }
          { title: "IDS Alerts"; type: "count"; query: "service:ids AND level:alert"; }
        ];
      }
      {
        name = "Error Analysis";
        panels = [
          { title: "Error Rate"; type: "rate"; query: "level:error"; }
          { title: "Top Errors"; type: "top"; query: "level:error"; field: "message"; }
        ];
      }
    ];
  };
  
  compliance = {
    enable = true;
    
    audit = {
      userActions = true;
      configurationChanges = true;
      securityEvents = true;
      accessLogs = true;
    };
    
    reporting = {
      schedule = "weekly";
      recipients = [ "compliance@example.com" ];
      include = [
        "access-summary"
        "security-events"
        "configuration-changes"
      ];
    };
  };
};
```

### Integration Points
- All service modules
- Monitoring module integration
- Elasticsearch/Loki integration
- Grafana/Kibana integration

## Testing Requirements
- Log collection accuracy tests
- Parser validation tests
- Performance impact assessment
- Search functionality tests

## Dependencies
- 03-service-health-checks
- 16-service-level-objectives

## Estimated Effort
- High (complex log system)
- 3 weeks implementation
- 2 weeks testing

## Success Criteria
- Complete log coverage for all services
- Accurate log parsing and field extraction
- Fast and efficient log search
- Comprehensive log-based monitoring
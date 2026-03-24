# Network Topology Discovery

**Status: Complete**

## Description
Implement automatic network topology discovery to map network infrastructure, identify devices, and visualize network relationships.

## Requirements

### Current State
- Manual network configuration
- No topology discovery
- Limited device visibility

### Improvements Needed

#### 1. Topology Discovery Engine
- Active and passive discovery methods
- Layer 2/3 topology mapping
- Device identification and classification
- Network relationship analysis

#### 2. Device Discovery
- ARP table analysis
- SNMP discovery
- LLDP/CDP neighbor discovery
- DHCP lease analysis
- DNS record analysis

#### 3. Topology Mapping
- Network graph generation
- Device relationship mapping
- Network segment identification
- Redundancy and failover paths

#### 4. Visualization and Analysis
- Interactive topology maps
- Network health overlay
- Change detection and alerts
- Capacity planning insights

## Implementation Details

### Files to Create
- `modules/topology-discovery.nix` - Topology discovery framework
- `lib/network-mapper.nix` - Network mapping utilities

### Topology Discovery Configuration
```nix
services.gateway.topologyDiscovery = {
  enable = true;
  
  discovery = {
    methods = {
      arp = {
        enable = true;
        interval = "5m";
        tableRefresh = "1m";
      };
      
      snmp = {
        enable = true;
        communities = [ "public" "private" ];
        timeout = "5s";
        retries = 3;
        
        targets = [
          "192.168.1.1"
          "192.168.1.10"
          "192.168.1.20"
        ];
      };
      
      lldp = {
        enable = true;
        interval = "2m";
        interfaceFilter = [ "eth*" "enp*" ];
      };
      
      dhcp = {
        enable = true;
        leaseAnalysis = true;
        staticMapping = true;
      };
      
      dns = {
        enable = true;
        zoneTransfer = true;
        recordAnalysis = true;
      };
      
      passive = {
        enable = true;
        packetCapture = true;
        flowAnalysis = true;
        learningPeriod = "24h";
      };
    };
    
    deviceIdentification = {
      fingerprinting = {
        enable = true;
        methods = [ "mac-vendor" "os-detection" "service-detection" ];
        database = "nmap-mac-prefixes";
      };
      
      classification = {
        types = [
          "router"
          "switch"
          "firewall"
          "server"
          "workstation"
          "printer"
          "iot"
          "phone"
        ];
        
        rules = [
          {
            name = "cisco-switch";
            conditions = [
              { field = "mac_vendor"; value = "Cisco"; }
              { field = "snmp_sysdescr"; pattern = ".*Switch.*"; }
            ];
            type = "switch";
          }
          {
            name = "windows-server";
            conditions = [
              { field = "os_fingerprint"; pattern = "Windows.*Server.*"; }
              { field = "services"; contains = [ "smb" "dns" "ldap" ]; }
            ];
            type = "server";
          }
        ];
      };
    };
  };
  
  topology = {
    layers = {
      l2 = {
        enable = true;
        methods = [ "arp" "lldp" "cdp" ];
        linkDiscovery = true;
        vlanMapping = true;
      };
      
      l3 = {
        enable = true;
        methods = [ "routing-table" "snmp" "traceroute" ];
        subnetMapping = true;
        gatewayIdentification = true;
      };
      
      l4 = {
        enable = true;
        methods = [ "port-scanning" "service-detection" ];
        serviceMapping = true;
        protocolAnalysis = true;
      };
    };
    
    graph = {
      nodes = {
        device = {
          attributes = [
            "name"
            "type"
            "vendor"
            "model"
            "os"
            "ip_addresses"
            "mac_addresses"
            "services"
            "status"
          ];
        };
        
        network = {
          attributes = [
            "name"
            "type"
            "subnet"
            "vlan"
            "gateway"
          ];
        };
      };
      
      edges = {
        physical = {
          type = "layer2";
          attributes = [ "interface" "speed" "duplex" "status" ];
        };
        
        logical = {
          type = "layer3";
          attributes = [ "protocol" "bandwidth" "latency" "utilization" ];
        };
      };
    };
  };
  
  analysis = {
    redundancy = {
      enable = true;
      pathAnalysis = true;
      failoverDetection = true;
      singlePointFailure = true;
    };
    
    performance = {
      enable = true;
      linkUtilization = true;
      latencyAnalysis = true;
      bottleneckDetection = true;
    };
    
    security = {
      enable = true;
      unauthorizedDevices = true;
      rogueDhcp = true;
      unusualTraffic = true;
    };
    
    changes = {
      enable = true;
      detection = true;
      alerting = true;
      history = "30d";
    };
  };
  
  visualization = {
    enable = true;
    
    maps = {
      overview = {
        type = "force-directed";
        layout = "hierarchical";
        clustering = true;
        filters = [ "device-type" "status" "network" ];
      };
      
      detailed = {
        type = "geographic";
        floorPlan = true;
        rackViews = true;
        deviceDetails = true;
      };
      
      logical = {
        type = "tree";
        groupBy = "network";
        showVlans = true;
        showSubnets = true;
      };
    };
    
    overlays = {
      health = {
        enable = true;
        metrics = [ "status" "cpu" "memory" "bandwidth" ];
        colors = { good = "green"; warning = "yellow"; critical = "red"; };
      };
      
      traffic = {
        enable = true;
        metrics = [ "throughput" "packets" "errors" ];
        animation = true;
        timeRange = "1h";
      };
      
      alerts = {
        enable = true;
        severity = [ "critical" "warning" "info" ];
        popup = true;
        history = "24h";
      };
    };
  };
  
  automation = {
    enable = true;
    
    documentation = {
      generate = true;
      format = "markdown";
      include = [
        "device-inventory"
        "network-diagram"
        "ip-plan"
        "vlan-mapping"
      ];
      schedule = "daily";
    };
    
    monitoring = {
      deviceDiscovery = true;
      topologyChanges = true;
      performanceAnomalies = true;
    };
    
    integration = {
      inventory = {
        enable = true;
        export = "cmdb";
        fields = [ "name" "type" "location" "owner" "purchase_date" ];
      };
      
      networkManagement = {
        enable = true;
        systems = [ "cisco-aci" "vmware-nsx" "openstack-neutron" ];
      };
    };
  };
  
  api = {
    enable = true;
    
    endpoints = {
      "/topology" = {
        methods = [ "GET" ];
        description = "Get current network topology";
      };
      
      "/devices" = {
        methods = [ "GET" "POST" "PUT" "DELETE" ];
        description = "Device management";
      };
      
      "/discovery" = {
        methods = [ "POST" ];
        description = "Trigger topology discovery";
      };
    };
    
    authentication = {
      type = "jwt";
      roles = [ "read-only" "operator" "admin" ];
    };
  };
};
```

### Integration Points
- Network module integration
- Monitoring module integration
- DHCP/DNS modules integration
- Management UI integration

## Testing Requirements
- Discovery accuracy tests
- Topology mapping validation
- Device identification tests
- Performance impact assessment

## Dependencies
- 02-module-system-dependencies
- 03-service-health-checks

## Estimated Effort
- High (complex discovery system)
- 4 weeks implementation
- 3 weeks testing

## Success Criteria
- Accurate network topology mapping
- Comprehensive device discovery
- Real-time change detection
- Interactive visualization tools

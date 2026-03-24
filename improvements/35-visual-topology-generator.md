# Visual Topology Generator

**Status: Pending**

## Description
Create a visual network topology generator that creates interactive diagrams of gateway configurations and network layouts.

## Requirements

### Current State
- Text-based configuration
- No visualization tools
- Manual diagram creation

### Improvements Needed

#### 1. Topology Generation Framework
- Automatic topology discovery
- Interactive diagram creation
- Multiple visualization formats
- Real-time updates

#### 2. Visualization Features
- Network device representation
- Connection visualization
- Traffic flow display
- Status indicators

#### 3. Export Options
- Multiple diagram formats
- Interactive web exports
- Print-ready layouts
- API access

#### 4. Integration Features
- Configuration import
- Live monitoring data
- Change tracking
- Collaboration tools

## Implementation Details

### Files to Create
- `tools/topology-generator.nix` - Topology generator tool
- `lib/visualizer.nix` - Visualization utilities

### Visual Topology Generator Configuration
```nix
services.gateway.topologyGenerator = {
  enable = true;
  
  generation = {
    sources = [
      {
        name: "configuration";
        type: "nix-config";
        path: "/etc/nixos";
        parser = "gateway-config-parser";
      }
      {
        name: "network-discovery";
        type: "live-scan";
        methods: [ "arp" "snmp" "lldp" ];
        interval: "5m";
      }
      {
        name: "monitoring-data";
        type: "metrics";
        source: "prometheus";
        interval: "1m";
      }
    ];
    
    processing = {
      nodeDetection = {
        enable = true;
        
        types = [
          "gateway"
          "router"
          "switch"
          "firewall"
          "server"
          "workstation"
          "iot"
        ];
        
        attributes = [
          "name"
          "type"
          "ip-address"
          "mac-address"
          "status"
          "role"
        ];
      };
      
      connectionDetection = {
        enable = true;
        
        methods = [
          "routing-table"
          "arp-table"
          "switch-mac-table"
          "connection-tracking"
        ];
        
        attributes = [
          "source"
          "destination"
          "protocol"
          "bandwidth"
          "latency"
          "status"
        ];
      };
      
      layout = {
        algorithm = "force-directed";
        
        parameters = {
          iterations = 1000;
          repulsion = 1000;
          attraction = 0.1;
          gravity = 0.1;
        };
        
        constraints = [
          { type: "hierarchy"; root: "gateway"; }
          { type: "grouping"; attribute: "network"; }
          { type: "alignment"; axis: "horizontal"; }
        ];
      };
    };
  };
  
  visualization = {
    rendering = {
      engine = "d3";
      
      styles = {
        nodes = [
          {
            type: "gateway";
            shape: "diamond";
            color: "#ff6b6b";
            size: 30;
          }
          {
            type: "router";
            shape: "rectangle";
            color: "#4ecdc4";
            size: 25;
          }
          {
            type: "switch";
            shape: "rectangle";
            color: "#45b7d1";
            size: 20;
          }
          {
            type: "server";
            shape: "circle";
            color: "#96ceb4";
            size: 15;
          }
          {
            type: "workstation";
            shape: "circle";
            color: "#ffeaa7";
            size: 10;
          }
          {
            type: "iot";
            shape: "square";
            color: "#dfe6e9";
            size: 8;
          }
        ];
        
        edges = [
          {
            type: "physical";
            style: "solid";
            color: "#2c3e50";
            width: 2;
          }
          {
            type: "logical";
            style: "dashed";
            color: "#7f8c8d";
            width: 1;
          }
          {
            type: "traffic";
            style: "animated";
            color: "#e74c3c";
            width: 3;
          }
        ];
      };
    };
    
    interaction = {
      enable = true;
      
      features = [
        "zoom-pan"
        "node-selection"
        "edge-selection"
        "drag-drop"
        "context-menu"
        "search-filter"
        "layer-toggle"
      ];
      
      tooltips = {
        enable = true;
        
        content = [
          "name"
          "type"
          "ip-address"
          "status"
          "metrics"
        ];
      };
      
      contextMenu = {
        enable = true;
        
        actions = [
          {
            label: "View Details";
            action: "show-node-details";
          }
          {
            label: "Edit Configuration";
            action: "edit-config";
          }
          {
            label: "View Metrics";
            action: "show-metrics";
          }
          {
            label: "Trace Route";
            action: "trace-route";
          }
        ];
      };
    };
    
    layers = [
      {
        name: "physical";
        description: "Physical network topology";
        visible: true;
        opacity: 1.0;
      }
      {
        name: "logical";
        description: "Logical network topology";
        visible: true;
        opacity: 0.8;
      }
      {
        name: "traffic";
        description: "Traffic flow visualization";
        visible: false;
        opacity: 0.6;
      }
      {
        name: "status";
        description: "Device status indicators";
        visible: true;
        opacity: 1.0;
      }
    ];
    
    filters = [
      {
        name: "device-type";
        type: "multi-select";
        options: [ "gateway" "router" "switch" "server" "workstation" "iot" ];
      }
      {
        name: "status";
        type: "multi-select";
        options: [ "online" "offline" "warning" "error" ];
      }
      {
        name: "network";
        type: "multi-select";
        options: [ "lan" "wan" "dmz" "vpn" ];
      }
    ];
  };
  
  export = {
    formats = [
      {
        name: "svg";
        description: "Scalable Vector Graphics";
        extension: ".svg";
        options: [ "size" "resolution" "background" ];
      }
      {
        name: "png";
        description: "Portable Network Graphics";
        extension: ".png";
        options: [ "size" "resolution" "background" ];
      }
      {
        name: "pdf";
        description: "Portable Document Format";
        extension: ".pdf";
        options: [ "size" "orientation" "background" ];
      }
      {
        name: "html";
        description: "Interactive HTML";
        extension: ".html";
        options: [ "interactive" "responsive" "theme" ];
      }
      {
        name: "json";
        description: "JSON data";
        extension: ".json";
        options: [ "pretty" "metadata" ];
      }
      {
        name: "graphviz";
        description: "Graphviz DOT";
        extension: ".dot";
        options: [ "layout" "engine" ];
      }
    ];
    
    templates = [
      {
        name: "network-diagram";
        description: "Standard network diagram";
        layout: "hierarchical";
        style: "corporate";
      }
      {
        name: "rack-layout";
        description: "Data center rack layout";
        layout: "grid";
        style: "technical";
      }
      {
        name: "logical-view";
        description: "Logical network view";
        layout: "circular";
        style: "abstract";
      }
    ];
  };
  
  monitoring = {
    enable = true;
    
    data = {
      sources = [
        {
          name: "prometheus";
          type: "metrics";
          endpoint: "http://prometheus:9090";
          queries: [
            "node_network_up"
            "node_cpu_usage"
            "node_memory_usage"
          ];
        }
        {
          name: "snmp";
          type: "device-status";
          devices: [ "192.168.1.1" "192.168.1.10" ];
          oids: [ "1.3.6.1.2.1.1.1.0" ];
        }
      ];
      
      refresh = {
        interval = "30s";
        realTime = true;
      };
    };
    
    visualization = {
      status = {
        enable = true;
        
        indicators = [
          {
            status: "online";
            color: "#27ae60";
            animation: "none";
          }
          {
            status: "offline";
            color: "#e74c3c";
            animation: "pulse";
          }
          {
            status: "warning";
            color: "#f39c12";
            animation: "blink";
          }
          {
            status: "error";
            color: "#c0392b";
            animation: "pulse";
          }
        ];
      };
      
      traffic = {
        enable = true;
        
        flow = {
          animation = true;
          speed = "normal";
          color = "intensity";
          width = "bandwidth";
        };
        
        metrics = [
          "throughput"
          "packet-rate"
          "error-rate"
          "latency"
        ];
      };
    };
  };
  
  collaboration = {
    enable = true;
    
    sharing = {
      enable = true;
      
      methods = [
        {
          name: "url";
          description: "Share via URL";
          ttl = "24h";
          password: false;
        }
        {
          name: "embed";
          description: "Embed in website";
          responsive: true;
          interactive: true;
        }
        {
          name: "export";
          description: "Export to file";
          formats: [ "svg" "png" "html" ];
        }
      ];
    };
    
    editing = {
      enable = true;
      
      features = [
        "real-time-collaboration"
        "comment-annotations"
        "version-history"
        "change-tracking"
      ];
      
      permissions = [
        {
          role: "viewer";
          actions: [ "view" "comment" ];
        }
        {
          role: "editor";
          actions: [ "view" "edit" "comment" ];
        }
        {
          role: "admin";
          actions: [ "view" "edit" "comment" "share" "delete" ];
        }
      ];
    };
  };
  
  api = {
    enable = true;
    
    endpoints = [
      {
        path: "/topology";
        method: "GET";
        description: "Get current topology";
        parameters: [ "format" "filter" "layout" ];
      }
      {
        path: "/topology";
        method: "POST";
        description: "Create topology from config";
        parameters: [ "config" "options" ];
      }
      {
        path: "/export";
        method: "POST";
        description: "Export topology";
        parameters: [ "format" "template" "options" ];
      }
    ];
    
    authentication = {
      type = "jwt";
      roles = [ "read" "write" "admin" ];
    };
  };
};
```

### Integration Points
- Configuration parser
- Network discovery
- Monitoring systems
- Export libraries

## Testing Requirements
- Topology accuracy tests
- Visualization quality tests
- Export functionality tests
- Performance tests

## Dependencies
- 20-network-topology-discovery
- 03-service-health-checks

## Estimated Effort
- High (complex visualization system)
- 5 weeks implementation
- 3 weeks testing

## Success Criteria
- Accurate topology generation
- Interactive visualization
- Multiple export formats
- Real-time monitoring integration
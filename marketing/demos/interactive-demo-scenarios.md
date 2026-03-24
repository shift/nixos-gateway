# Interactive Demo Scenarios

## 🎮 **Hands-On Demo Environment**

### **Demo Environment Architecture**
- **Platform**: Web-based interactive terminal
- **Backend**: NixOS VMs with pre-configured scenarios
- **Frontend**: Monaco editor with syntax highlighting
- **Execution**: Safe sandboxed environment with time limits

---

## 🚀 **Demo Scenario 1: Quick Start Gateway**

### **Duration**: 5 minutes
### **Difficulty**: Beginner
### **Goal**: Create first working gateway configuration

#### **Step-by-Step Flow**

**Step 1: Basic Configuration** (1 minute)
```nix
# gateway.nix
{
  networking.hostName = "gateway";
  services.gateway = {
    enable = true;
    interfaces = {
      wan = "eth0";
      lan = "eth1";
    };
  };
}
```

**Step 2: Add DHCP Service** (1 minute)
```nix
services.gateway.dhcp = {
  enable = true;
  networks.lan = {
    range = "192.168.1.100-192.168.1.200";
    domain = "local";
  };
};
```

**Step 3: Add DNS Service** (1 minute)
```nix
services.gateway.dns = {
  enable = true;
  forwarders = [ "8.8.8.8" "1.1.1.1" ];
  zones.local = {
    file = "/var/lib/bind/local.zone";
  };
};
```

**Step 4: Deploy and Test** (2 minutes)
- Build configuration
- Deploy to test environment
- Verify connectivity
- Test DHCP and DNS

#### **Interactive Elements**
- **Live Preview**: Real-time configuration validation
- **Syntax Highlighting**: Monaco editor with Nix language support
- **Error Detection**: Immediate feedback on configuration errors
- **Test Results**: Live output from deployment commands

---

## 🔥 **Demo Scenario 2: Advanced Networking**

### **Duration**: 10 minutes
### **Difficulty**: Intermediate
### **Goal**: Configure multi-homed BGP gateway

#### **Step-by-Step Flow**

**Step 1: Multi-Interface Setup** (2 minutes)
```nix
services.gateway.interfaces = {
  wan1 = "eth0";    # ISP A
  wan2 = "eth1";    # ISP B
  lan = "eth2";     # Internal network
  dmz = "eth3";     # DMZ network
};
```

**Step 2: BGP Configuration** (3 minutes)
```nix
services.gateway.bgp = {
  enable = true;
  asn = 65001;
  neighbors = {
    isp_a = {
      asn = 64512;
      peer_ip = "203.0.113.1";
      local_ip = "203.0.113.2";
    };
    isp_b = {
      asn = 64513;
      peer_ip = "198.51.100.1";
      local_ip = "198.51.100.2";
    };
  };
};
```

**Step 3: Policy Routing** (3 minutes)
```nix
services.gateway.policyRouting = {
  rules = {
    traffic_via_isp_a = {
      from = "192.168.1.0/24";
      table = 100;
      priority = 100;
    };
    traffic_via_isp_b = {
      from = "10.0.0.0/24";
      table = 200;
      priority = 200;
    };
  };
  tables = {
    table_100 = {
      default_via = "203.0.113.1";
    };
    table_200 = {
      default_via = "198.51.100.1";
    };
  };
};
```

**Step 4: Testing and Validation** (2 minutes)
- BGP session establishment
- Route advertisement verification
- Policy routing testing
- Failover simulation

#### **Interactive Elements**
- **Network Visualization**: Real-time topology diagram
- **BGP Status**: Live session status and route tables
- **Traffic Flow**: Packet flow visualization
- **Failover Test**: Simulated ISP failure scenarios

---

## 🛡️ **Demo Scenario 3: Security Hardening**

### **Duration**: 12 minutes
### **Difficulty**: Advanced
### **Goal**: Implement zero-trust security model

#### **Step-by-Step Flow**

**Step 1: Firewall Configuration** (3 minutes)
```nix
services.gateway.firewall = {
  enable = true;
  defaultPolicy = "drop";
  rules = {
    allow_ssh = {
      from = "admin-network";
      to = "gateway";
      ports = [ 22 ];
      proto = "tcp";
    };
    allow_web = {
      from = "any";
      to = "dmz";
      ports = [ 80 443 ];
      proto = "tcp";
    };
  };
};
```

**Step 2: IDS/IPS Setup** (3 minutes)
```nix
services.gateway.ids = {
  enable = true;
  engine = "suricata";
  rules = [
    "et/botcc.rules"
    "et/compromised.rules"
    "local/custom.rules"
  ];
  alerts = {
    log = true;
    email = "security@company.com";
  };
};
```

**Step 3: 802.1X Authentication** (3 minutes)
```nix
services.gateway.dot1x = {
  enable = true;
  interfaces = [ "eth2" "eth3" ];
  authentication = {
    backend = "radius";
    servers = [ "radius1.company.com" "radius2.company.com" ];
    secret = "shared-secret";
  };
  policies = {
    trusted_devices = {
      vlan = 100;
      access = "full";
    };
    guest_devices = {
      vlan = 999;
      access = "captive-portal";
    };
  };
};
```

**Step 4: Zero Trust Segmentation** (3 minutes)
```nix
services.gateway.microsegmentation = {
  enable = true;
  policies = {
    web_servers = {
      sources = [ "load-balancers" ];
      destinations = [ "web-servers" ];
      ports = [ 80 443 ];
      proto = "tcp";
    };
    database_access = {
      sources = [ "app-servers" ];
      destinations = [ "database-servers" ];
      ports = [ 5432 ];
      proto = "tcp";
    };
  };
};
```

#### **Interactive Elements**
- **Security Dashboard**: Real-time threat detection
- **Policy Visualization**: Network segmentation diagram
- **Attack Simulation**: Simulated security incidents
- **Compliance Check**: Automated security validation

---

## ⚡ **Demo Scenario 4: Performance Optimization**

### **Duration**: 8 minutes
### **Difficulty**: Advanced
### **Goal**: Implement high-performance data plane

#### **Step-by-Step Flow**

**Step 1: XDP/eBPF Programs** (2 minutes)
```nix
services.gateway.xdp = {
  enable = true;
  programs = {
    firewall = {
      interface = "eth0";
      program = ./firewall.c;
      mode = "native";
    };
    ddos_protection = {
      interface = "eth0";
      program = ./ddos.c;
      mode = "native";
    };
  };
};
```

**Step 2: Traffic Classification** (2 minutes)
```nix
services.gateway.trafficClassification = {
  enable = true;
  classifiers = {
    voip_traffic = {
      dscp = 46;  # EF
      priority = "high";
    };
    video_streaming = {
      dscp = 34;  # AF41
      priority = "medium";
    };
    bulk_transfer = {
      dscp = 8;   # CS1
      priority = "low";
    };
  };
};
```

**Step 3: QoS Configuration** (2 minutes)
```nix
services.gateway.qos = {
  enable = true;
  interfaces = {
    eth0 = {
      bandwidth = "1Gbps";
      queues = {
        high_priority = {
          bandwidth = "30%";
          priority = "strict";
        };
        medium_priority = {
          bandwidth = "40%";
          priority = "normal";
        };
        low_priority = {
          bandwidth = "30%";
          priority = "low";
        };
      };
    };
  };
};
```

**Step 4: Performance Testing** (2 minutes)
- Throughput measurement
- Latency testing
- Packet loss analysis
- Resource utilization monitoring

#### **Interactive Elements**
- **Performance Graphs**: Real-time throughput and latency
- **Packet Analysis**: Deep packet inspection visualization
- **Resource Monitor**: CPU and memory usage
- **Benchmark Comparison**: Before/after performance metrics

---

## 🎯 **Demo Scenario 5: Multi-Site SD-WAN**

### **Duration**: 15 minutes
### **Difficulty**: Expert
### **Goal**: Deploy multi-site SD-WAN solution

#### **Step-by-Step Flow**

**Step 1: Site Configuration** (4 minutes)
```nix
# Site A Configuration
services.gateway.sdwan = {
  enable = true;
  site = {
    name = "site-a";
    id = 1;
    region = "us-east";
  };
  wanLinks = {
    mpls = {
      interface = "eth0";
      bandwidth = "100Mbps";
      cost = 10;
    };
    broadband = {
      interface = "eth1";
      bandwidth = "50Mbps";
      cost = 5;
    };
    lte = {
      interface = "eth2";
      bandwidth = "10Mbps";
      cost = 20;
    };
  };
};
```

**Step 2: Path Selection** (4 minutes)
```nix
services.gateway.sdwan.pathSelection = {
  algorithm = "quality-based";
  metrics = [
    "latency"
    "jitter"
    "packet_loss"
    "bandwidth_utilization"
  ];
  thresholds = {
    latency = { max = "50ms"; weight = 40; };
    jitter = { max = "5ms"; weight = 30; };
    packet_loss = { max = "0.1%"; weight = 20; };
    bandwidth = { max = "80%"; weight = 10; };
  };
};
```

**Step 3: Application Policies** (4 minutes)
```nix
services.gateway.sdwan.applicationPolicies = {
  voip = {
    applications = [ "sip" "rtp" ];
    pathPreference = "lowest_latency";
    redundancy = "active-active";
  };
  video_conference = {
    applications = [ "zoom" "teams" "webex" ];
    pathPreference = "highest_bandwidth";
    redundancy = "active-backup";
  };
  bulk_data = {
    applications = [ "ftp" "sftp" "scp" ];
    pathPreference = "lowest_cost";
    redundancy = "best_effort";
  };
};
```

**Step 4: Monitoring and Optimization** (3 minutes)
- Path quality monitoring
- Automatic path optimization
- Performance analytics
- Failover testing

#### **Interactive Elements**
- **Site Topology**: Multi-site network visualization
- **Path Quality**: Real-time path performance metrics
- **Traffic Distribution**: Application traffic flow
- **Failover Simulation**: Link failure scenarios

---

## 🎨 **Demo Environment Features**

### **Interactive Editor**
- **Syntax Highlighting**: Full Nix language support
- **Auto-completion**: Intelligent code suggestions
- **Error Detection**: Real-time syntax and type checking
- **Code Templates**: Pre-built configuration snippets

### **Execution Environment**
- **Sandboxed**: Safe execution with resource limits
- **Instant Feedback**: Immediate results and validation
- **State Management**: Save and restore configurations
- **Version Control**: Track changes and experiments

### **Visualization Tools**
- **Network Topology**: Interactive network diagrams
- **Performance Graphs**: Real-time metrics and charts
- **Security Dashboard**: Threat detection and alerts
- **Configuration Diff**: Before/after comparisons

### **Learning Features**
- **Guided Tours**: Step-by-step instructions
- **Hints System**: Contextual help and tips
- **Documentation**: Integrated reference materials
- **Progress Tracking**: Completion status and achievements

---

## 📊 **Success Metrics**

### **Engagement Metrics**
- **Demo Completion Rate**: 70%+ completion for basic demos
- **Time Spent**: 10+ minutes average session duration
- **Return Visits**: 40%+ return for advanced demos
- **Feature Discovery**: 5+ features explored per session

### **Learning Metrics**
- **Skill Improvement**: Pre/post assessment scores
- **Concept Mastery**: Quiz completion rates
- **Practical Application**: Configuration export rates
- **Community Contribution**: GitHub project contributions

### **Conversion Metrics**
- **Documentation Visits**: 50%+ click-through to docs
- **GitHub Stars**: 20%+ conversion from demo to star
- **Community Join**: 10%+ join Discord/Slack
- **Enterprise Leads**: 5%+ request enterprise demo

---

## 🚀 **Implementation Roadmap**

### **Phase 1: Core Platform** (4 weeks)
- Interactive editor development
- Sandbox environment setup
- Basic demo scenarios
- User authentication system

### **Phase 2: Advanced Features** (6 weeks)
- Visualization tools
- Advanced demo scenarios
- Progress tracking
- Community features

### **Phase 3: Optimization** (4 weeks)
- Performance optimization
- Mobile responsiveness
- Accessibility improvements
- Analytics integration

---

**Status**: ✅ **Demo Scenarios Defined**  
**Next**: Interactive platform development  
**Timeline**: 14 weeks total implementation  
**Budget**: Development resources and hosting costs
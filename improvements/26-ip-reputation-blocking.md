# IP Reputation Blocking

**Status: Pending**

## Description
Implement IP reputation-based blocking to prevent connections from known malicious or suspicious IP addresses.

## Requirements

### Current State
- Basic IP filtering
- No reputation scoring
- Static blocklists

### Improvements Needed

#### 1. Reputation Framework
- Multiple reputation sources
- Dynamic reputation scoring
- Reputation-based policies
- Automated reputation updates

#### 2. Reputation Sources
- Commercial reputation feeds
- Community blocklists
- Historical analysis
- Behavioral reputation

#### 3. Policy Integration
- Firewall integration
- IDS correlation
- Rate limiting
- Connection throttling

#### 4. Analytics and Management
- Reputation trend analysis
- False positive tracking
- Reputation effectiveness metrics
- Custom reputation rules

## Implementation Details

### Files to Create
- `modules/ip-reputation.nix` - IP reputation blocking
- `lib/reputation-engine.nix` - Reputation calculation utilities

### IP Reputation Configuration
```nix
services.gateway.ipReputation = {
  enable = true;
  
  sources = {
    commercial = [
      {
        name = "crowdstrike";
        type = "api";
        url = "https://api.crowdstrike.com/intel";
        apiKey = "encrypted-key";
        format = "json";
        
        categories = [
          "malware-c2"
          "phishing"
          "botnet"
          "scanners"
          "spam"
        ];
        
        scoring = {
          malicious = 100;
          suspicious = 75;
          unknown = 50;
          benign = 0;
        };
        
        update = {
          interval = "1h";
          retry = 3;
          timeout = "30s";
        };
      }
    ];
    
    community = [
      {
        name = "firehol-level1";
        type = "http";
        url = "https://iplists.firehol.org/files/firehol_level1.netset";
        format = "text";
        
        categories = [ "malicious" ];
        scoring = { malicious = 90; };
        
        update = {
          interval = "6h";
          retry = 3;
          timeout = "60s";
        };
      }
      {
        name = "blocklistde";
        type = "http";
        url = "https://lists.blocklist.de/lists/all.txt";
        format = "text";
        
        categories = [ "attacks" "scans" ];
        scoring = { malicious = 85; };
        
        update = {
          interval = "4h";
          retry = 3;
          timeout = "45s";
        };
      }
    ];
    
    behavioral = {
      enable = true;
      
      analysis = {
        window = "24h";
        minConnections = 10;
        
        indicators = [
          { name: "failed-logins"; weight: 30; threshold: 5; }
          { name: "port-scans"; weight: 25; threshold: 20; }
          { name: "malicious-requests"; weight: 35; threshold: 10; }
          { name: "unusual-traffic"; weight: 10; threshold: 100; }
        ];
      };
      
      scoring = {
        malicious = 80;
        suspicious = 60;
        unknown = 40;
        benign = 20;
      };
    };
  };
  
  scoring = {
    algorithm = "weighted-average";
    
    weights = {
      commercial = 50;
      community = 30;
      behavioral = 20;
    };
    
    thresholds = {
      block = 80;
      throttle = 60;
      monitor = 40;
      allow = 20;
    };
    
    decay = {
      enable = true;
      rate = 0.1;
      minScore = 10;
      maxAge = "30d";
    };
  };
  
  policies = [
    {
      name = "block-malicious";
      condition = "reputation.score >= 80";
      action = "block";
      duration = "7d";
      sources = [ "firewall" "ids" ];
    }
    {
      name = "throttle-suspicious";
      condition = "reputation.score >= 60 && reputation.score < 80";
      action = "throttle";
      rate = "10/minute";
      duration = "1h";
      sources = [ "firewall" ];
    }
    {
      name = "monitor-unknown";
      condition = "reputation.score >= 40 && reputation.score < 60";
      action = "monitor";
      logging = "extended";
      alert = true;
    }
  ];
  
  integration = {
    firewall = {
      enable = true;
      
      ipsets = {
        malicious = {
          type = "hash:ip";
          timeout = 604800;  // 7 days
          size = 65536;
        };
        suspicious = {
          type = "hash:ip";
          timeout = 3600;    // 1 hour
          size = 32768;
        };
      };
      
      rules = [
        {
          chain = "INPUT";
          set = "malicious";
          action = "DROP";
          comment = "Block malicious IPs";
        }
        {
          chain = "INPUT";
          set = "suspicious";
          action = "rate-limit";
          limit = "10/min";
          comment = "Throttle suspicious IPs";
        }
      ];
    };
    
    ids = {
      enable = true;
      
      rules = [
        {
          sid = 1000001;
          msg = "IP Reputation: Malicious IP detected";
          ipset = "malicious";
          action = "alert";
        }
        {
          sid = 1000002;
          msg = "IP Reputation: Suspicious IP detected";
          ipset = "suspicious";
          action = "alert";
        }
      ];
    };
    
    dns = {
      enable = true;
      
      filtering = {
        enable = true;
        threshold = 70;
        action = "block";
        log = true;
      };
    };
  };
  
  analytics = {
    enable = true;
    
    metrics = {
      reputationDistribution = true;
      blockEffectiveness = true;
      falsePositives = true;
      sourcePerformance = true;
    };
    
    reporting = {
      schedules = [
        {
          name = "daily-reputation";
          frequency = "daily";
          recipients = [ "security@example.com" ];
          include = [ "blocked-ips" "reputation-trends" "source-analysis" ];
        }
        {
          name = "weekly-analysis";
          frequency = "weekly";
          recipients = [ "management@example.com" ];
          include = [ "effectiveness-report" "false-positive-analysis" "recommendations" ];
        }
      ];
    };
    
    dashboard = {
      enable = true;
      
      panels = [
        { title: "IP Reputation Distribution"; type: "pie"; }
        { title: "Blocked Connections"; type: "counter"; }
        { title: "Source Performance"; type: "bar"; }
        { title: "Reputation Trends"; type: "trend"; }
      ];
    };
  };
  
  automation = {
    enable = true;
    
    workflows = [
      {
        name = "high-reputation-block";
        trigger = "reputation.score >= 90";
        actions = [
          { type: "add-to-firewall"; duration: "30d"; }
          { type: "add-to-ids"; duration: "30d"; }
          { type: "notify-security"; template: "high-reputation"; }
        ];
      }
      {
        name = "reputation-decay";
        trigger = "reputation.age > 30d";
        actions = [
          { type: "reduce-score"; factor: 0.5; }
          { type: "re-evaluate"; interval: "7d"; }
        ];
      }
    ];
    
    feedback = {
      enable = true;
      
      falsePositive = {
        enable = true;
        method = "webhook";
        endpoint = "https://reputation-provider.com/feedback";
        
        data = [
          "ip"
          "originalScore"
          "reason"
          "timestamp"
        ];
      };
      
      performance = {
        enable = true;
        metrics = [ "accuracy" "precision" "recall" ];
        reporting = "weekly";
      };
    };
  };
};
```

### Integration Points
- Firewall module integration
- IDS module integration
- DNS module integration
- Monitoring module integration

## Testing Requirements
- Reputation accuracy tests
- Block effectiveness validation
- False positive analysis
- Performance impact assessment

## Dependencies
- 25-threat-intelligence-integration
- 02-module-system-dependencies

## Estimated Effort
- Medium (reputation system)
- 3 weeks implementation
- 2 weeks testing

## Success Criteria
- Accurate reputation scoring
- Effective malicious IP blocking
- Minimal false positives
- Comprehensive reputation analytics
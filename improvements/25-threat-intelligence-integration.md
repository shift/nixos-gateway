# Threat Intelligence Integration

**Status: Pending**

## Description
Integrate threat intelligence feeds to enhance security detection, block malicious IPs/domains, and provide proactive threat protection.

## Requirements

### Current State
- Basic IDS signatures
- No threat intelligence integration
- Static security rules

### Improvements Needed

#### 1. Threat Intelligence Framework
- Multiple feed integration
- Feed normalization and deduplication
- Threat scoring and prioritization
- Automated rule generation

#### 2. Feed Management
- Commercial and open-source feeds
- Custom threat feeds
- Feed validation and quality checks
- Update scheduling and reliability

#### 3. Integration Points
- Firewall blocklists
- IDS signature updates
- DNS sinkholing
- Web filtering

#### 4. Analytics and Reporting
- Threat landscape analysis
- Block effectiveness metrics
- False positive tracking
- Threat trend reporting

## Implementation Details

### Files to Create
- `modules/threat-intel.nix` - Threat intelligence integration
- `lib/feed-processor.nix` - Feed processing utilities

### Threat Intelligence Configuration
```nix
services.gateway.threatIntel = {
  enable = true;
  
  feeds = {
    commercial = [
      {
        name = "recorded-future";
        type = "api";
        url = "https://api.recordedfuture.com/v2";
        apiKey = "encrypted-key";
        format = "json";
        
        indicators = [
          "ip"
          "domain"
          "url"
          "hash"
          "email"
        ];
        
        riskScores = {
          critical = 90;
          high = 75;
          medium = 50;
          low = 25;
        };
        
        update = {
          interval = "1h";
          retry = 3;
          timeout = "30s";
        };
      }
    ];
    
    opensource = [
      {
        name = "abuseipdb";
        type = "http";
        url = "https://feeds.abuseipdb.com/feeds/blacklist";
        format = "text";
        
        indicators = [ "ip" ];
        
        confidence = {
          threshold = 100;
          weight = 0.8;
        };
        
        update = {
          interval = "6h";
          retry = 3;
          timeout = "60s";
        };
      }
      {
        name = "phishstats";
        type = "http";
        url = "https://phishstats.info/phish_score.csv";
        format = "csv";
        
        indicators = [ "domain" "url" ];
        
        scoring = {
          threshold = 50;
          weight = 0.7;
        };
        
        update = {
          interval = "4h";
          retry = 3;
          timeout = "45s";
        };
      }
    ];
    
    custom = [
      {
        name = "internal-threats";
        type = "file";
        path = "/etc/threat-intel/internal.txt";
        format = "json";
        
        indicators = [ "ip" "domain" "email" ];
        
        source = "internal";
        confidence = 100;
        ttl = "7d";
      }
    ];
  };
  
  processing = {
    normalization = {
      enable = true;
      
      fields = [
        "indicator"
        "type"
        "source"
        "confidence"
        "riskScore"
        "firstSeen"
        "lastSeen"
        "tags"
      ];
      
      validation = {
        ipFormat = true;
        domainFormat = true;
        hashFormat = true;
        urlFormat = true;
      };
    };
    
    deduplication = {
      enable = true;
      
      strategy = "highest-confidence";
      ttl = "30d";
      
      merge = {
        sources = true;
        tags = true;
        timestamps = true;
      };
    };
    
    scoring = {
      algorithm = "weighted-average";
      
      factors = [
        { name = "confidence"; weight = 40; }
        { name = "source-reliability"; weight = 30; }
        { name = "recency"; weight = 20; }
        { name = "threat-type"; weight = 10; }
      ];
      
      thresholds = {
        block = 80;
        monitor = 60;
        ignore = 40;
      };
    };
  };
  
  integration = {
    firewall = {
      enable = true;
      
      blocklists = {
        ip = {
          enable = true;
          source = "threat-intel";
          threshold = 80;
          action = "drop";
          comment = "Threat Intelligence Block";
        };
        
        domain = {
          enable = true;
          source = "threat-intel";
          threshold = 80;
          action = "drop";
          comment = "Malicious Domain Block";
        };
      };
      
      update = {
        interval = "15m";
        reload = true;
        validate = true;
      };
    };
    
    ids = {
      enable = true;
      
      rules = {
        ip = {
          enable = true;
          source = "threat-intel";
          threshold = 70;
          action = "alert";
          sid = 1000000;
        };
        
        domain = {
          enable = true;
          source = "threat-intel";
          threshold = 70;
          action = "alert";
          sid = 2000000;
        };
      };
      
      update = {
        interval = "30m";
        reload = true;
        validate = true;
      };
    };
    
    dns = {
      enable = true;
      
      sinkhole = {
        enable = true;
        domains = true;
        threshold = 80;
        response = "0.0.0.0";
      };
      
      filtering = {
        enable = true;
        domains = true;
        threshold = 60;
        action = "block";
      };
    };
    
    proxy = {
      enable = true;
      
      categories = [
        "malware"
        "phishing"
        "botnet"
        "c2"
      ];
      
      action = "block";
      threshold = 70;
    };
  };
  
  analytics = {
    enable = true;
    
    metrics = {
      feedUpdates = true;
      indicatorCounts = true;
      blockEffectiveness = true;
      falsePositives = true;
    };
    
    reporting = {
      schedules = [
        {
          name = "daily-threat-summary";
          frequency = "daily";
          recipients = [ "security@example.com" ];
          include = [ "new-threats" "blocked-indicators" "trends" ];
        }
        {
          name = "weekly-threat-landscape";
          frequency = "weekly";
          recipients = [ "management@example.com" ];
          include = [ "threat-trends" "feed-performance" "recommendations" ];
        }
      ];
    };
    
    dashboard = {
      enable = true;
      
      panels = [
        { title: "Threat Feed Status"; type: "status"; }
        { title: "Blocked Indicators"; type: "count"; }
        { title: "Threat Trends"; type: "trend"; }
        { title: "Feed Performance"; type: "comparison"; }
      ];
    };
  };
  
  automation = {
    enable = true;
    
    workflows = [
      {
        name = "high-confidence-block";
        trigger = "indicator.riskScore >= 90";
        actions = [
          { type: "add-to-firewall"; duration: "30d"; }
          { type: "add-to-ids"; duration: "30d"; }
          { type: "notify-security"; template: "high-threat"; }
        ];
      }
      {
        name = "emerging-threat";
        trigger = "indicator.appearsInMultipleFeeds";
        actions = [
          { type: "increase-monitoring"; duration: "7d"; }
          { type: "notify-analysts"; template: "emerging-threat"; }
        ];
      }
    ];
    
    escalation = {
      enable = true;
      
      levels = [
        {
          name = "analyst";
          conditions = [ "riskScore >= 70" "sourceCount >= 2" ];
          actions = [ "create-ticket" "notify-team" ];
        }
        {
          name = "manager";
          conditions = [ "riskScore >= 85" "sourceCount >= 3" ];
          actions = [ "escalate-ticket" "notify-management" ];
        }
        {
          name = "ciso";
          conditions = [ "riskScore >= 95" "critical-infrastructure" ];
          actions = [ "immediate-alert" "executive-notification" ];
        }
      ];
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
- Feed processing accuracy tests
- Integration effectiveness tests
- False positive analysis
- Performance impact assessment

## Dependencies
- 02-module-system-dependencies
- 03-service-health-checks

## Estimated Effort
- High (complex threat intel system)
- 4 weeks implementation
- 3 weeks testing

## Success Criteria
- Accurate threat feed processing
- Effective threat blocking
- Minimal false positives
- Comprehensive threat analytics
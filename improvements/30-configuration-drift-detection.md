# Configuration Drift Detection

**Status: Pending**

## Description
Implement configuration drift detection to identify unauthorized changes and maintain system consistency.

## Requirements

### Current State
- No drift detection
- Manual configuration tracking
- Limited change monitoring

### Improvements Needed

#### 1. Drift Detection Framework
- Configuration baseline tracking
- Change detection algorithms
- Drift severity classification
- Automated remediation options

#### 2. Configuration Monitoring
- Real-time change detection
- Scheduled configuration audits
- Cross-system consistency checks
- Compliance validation

#### 3. Change Management
- Change approval workflows
- Configuration versioning
- Rollback capabilities
- Change attribution

#### 4. Analytics and Reporting
- Drift trend analysis
- Change frequency monitoring
- Compliance reporting
- Risk assessment

## Implementation Details

### Files to Create
- `modules/config-drift.nix` - Configuration drift detection
- `lib/drift-detector.nix` - Drift analysis utilities

### Configuration Drift Detection Configuration
```nix
services.gateway.configDrift = {
  enable = true;
  
  baseline = {
    creation = {
      schedule = "daily";
      time = "03:00";
      approval = "automatic";
      
      sources = [
        "nixos-configuration"
        "service-configs"
        "system-settings"
        "security-policies"
      ];
    };
    
    storage = {
      path = "/var/lib/config-drift/baselines";
      retention = "90d";
      encryption = true;
      
      versioning = {
        enable = true;
        maxVersions = 30;
        compression = true;
      };
    };
    
    validation = {
      enable = true;
      checks = [
        "syntax-validation"
        "semantic-validation"
        "security-validation"
        "compliance-validation"
      ];
    };
  };
  
  monitoring = {
    realTime = {
      enable = true;
      
      paths = [
        "/etc/nixos"
        "/etc/gateway"
        "/var/lib/gateway"
        "/etc/systemd"
      ];
      
      events = [
        "create"
        "modify"
        "delete"
        "permission-change"
        "ownership-change"
      ];
      
      filters = [
        { path: "*.tmp"; action: "ignore"; }
        { path: "*.log"; action: "ignore"; }
        { path: "cache/*"; action: "ignore"; }
      ];
    };
    
    scheduled = {
      enable = true;
      
      scans = [
        {
          name: "full-scan";
          schedule: "daily";
          time: "04:00";
          scope: "full";
        }
        {
          name: "security-scan";
          schedule: "hourly";
          scope: "security";
        }
        {
          name: "compliance-scan";
          schedule: "weekly";
          scope: "compliance";
        }
      ];
    };
    
    comparison = {
      algorithm = "hash-based";
      method = "sha256";
      
      attributes = [
        "content"
        "permissions"
        "ownership"
        "timestamps"
      ];
      
      sensitivity = {
        high = "security-files";
        medium = "config-files";
        low = "log-files";
      };
    };
  };
  
  drift = {
    classification = {
      severity = [
        {
          level: "critical";
          score: 90;
          types: [ "security-policy" "access-control" "encryption-keys" ];
          action: "immediate-alert";
        }
        {
          level: "high";
          score: 75;
          types: [ "service-config" "network-config" "firewall-rules" ];
          action: "alert-and-remediate";
        }
        {
          level: "medium";
          score: 50;
          types: [ "system-config" "application-config" ];
          action: "alert-and-log";
        }
        {
          level: "low";
          score: 25;
          types: [ "documentation" "log-config" ];
          action: "log-only";
        }
      ];
    };
    
    detection = {
      algorithms = [
        {
          name: "content-hash";
          type: "cryptographic";
          sensitivity: "high";
        }
        {
          name: "permission-check";
          type: "attribute";
          sensitivity: "medium";
        }
        {
          name: "timestamp-analysis";
          type: "behavioral";
          sensitivity: "low";
        }
      ];
      
      correlation = {
        enable = true;
        window = "5m";
        threshold = 3;
      };
    };
    
    remediation = {
      automatic = {
        enable = true;
        
        actions = [
          {
            trigger: "critical-drift";
            action: "restore-from-baseline";
            approval: "automatic";
          }
          {
            trigger: "high-drift";
            action: "create-ticket";
            approval: "automatic";
          }
          {
            trigger: "medium-drift";
            action: "notify-admin";
            approval: "automatic";
          }
        ];
      };
      
      manual = {
        enable = true;
        
        workflows = [
          {
            name: "security-drift";
            steps = [
              { type: "isolate-system"; }
              { type: "notify-security"; }
              { type: "investigate-change"; }
              { type: "approve-remediation"; }
              { type: "apply-remediation"; }
            ];
          }
          {
            name: "config-drift";
            steps: [
              { type: "analyze-change"; }
              { type: "assess-impact"; }
              { type: "approve-change"; }
              { type: "update-baseline"; }
            ];
          }
        ];
      };
    };
  };
  
  change = {
    management = {
      enable = true;
      
      approval = {
        required = true;
        
        workflows = [
          {
            name: "standard-change";
            approvers = [ "ops-team" ];
            timeout = "24h";
            autoApprove = false;
          }
          {
            name: "emergency-change";
            approvers = [ "ops-manager" ];
            timeout = "1h";
            autoApprove = true;
          }
          {
            name: "security-change";
            approvers = [ "security-team" "ops-team" ];
            timeout = "48h";
            autoApprove = false;
          }
        ];
      };
      
      tracking = {
        enable = true;
        
        attributes = [
          "requester"
          "timestamp"
          "reason"
          "approval"
          "implementation"
          "verification"
        ];
        
        retention = "7y";
      };
    };
    
    attribution = {
      enable = true;
      
      methods = [
        "system-logs"
        "audit-trails"
        "session-records"
        "api-calls"
      ];
      
      correlation = {
        enable = true;
        sources = [ "ssh" "sudo" "systemd" "application" ];
        confidence = 0.8;
      };
    };
  };
  
  analytics = {
    enable = true;
    
    metrics = {
      driftFrequency = true;
      driftSeverity = true;
      remediationSuccess = true;
      changeTrends = true;
    };
    
    reporting = {
      schedules = [
        {
          name: "daily-drift-summary";
          frequency: "daily";
          recipients: [ "ops@example.com" ];
          include: [ "drift-events" "remediation-actions" "trends" ];
        }
        {
          name: "weekly-compliance";
          frequency: "weekly";
          recipients: [ "compliance@example.com" ];
          include: [ "compliance-status" "violations" "recommendations" ];
        }
        {
          name: "monthly-analysis";
          frequency: "monthly";
          recipients: [ "management@example.com" ];
          include: [ "trend-analysis" "risk-assessment" "improvements" ];
        }
      ];
    };
    
    dashboard = {
      enable = true;
      
      panels = [
        { title: "Drift Events"; type: "timeline"; }
        { title: "Severity Distribution"; type: "pie"; }
        { title: "Remediation Success"; type: "gauge"; }
        { title: "Change Trends"; type: "trend"; }
      ];
    };
  };
  
  integration = {
    siem = {
      enable = true;
      endpoint = "https://siem.example.com";
      events = [ "drift-detected" "change-made" "remediation-action" ];
    };
    
    ticketing = {
      enable = true;
      system = "jira";
      endpoint = "https://company.atlassian.net";
      
      projects = [ "SEC" "OPS" ];
      priorities = [ "High" "Medium" "Low" ];
    };
    
    compliance = {
      enable = true;
      frameworks = [ "sox" "hipaa" "pci-dss" "iso-27001" ];
      
      reporting = true;
      audit = true;
      retention = "7y";
    };
  };
};
```

### Integration Points
- All service modules
- Security module integration
- Monitoring module integration
- Ticketing system integration

## Testing Requirements
- Drift detection accuracy tests
- Remediation effectiveness tests
- Change attribution validation
- Performance impact assessment

## Dependencies
- 28-automated-backup-recovery
- 03-service-health-checks

## Estimated Effort
- High (complex drift system)
- 4 weeks implementation
- 3 weeks testing

## Success Criteria
- Accurate drift detection
- Effective remediation
- Complete change attribution
- Comprehensive compliance reporting
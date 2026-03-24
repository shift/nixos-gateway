# Configuration Diff and Preview

**Status: Completed**

## Description
Implement configuration diff and preview tools to show changes before deployment and track configuration history.

## Requirements

### Current State
- No change preview
- Limited diff capabilities
- No change tracking

### Improvements Needed

#### 1. Diff Framework
- Configuration comparison
- Change impact analysis
- Visual diff display
- Change categorization

#### 2. Preview Features
- Before/after comparison
- Service impact analysis
- Resource requirement changes
- Security impact assessment

#### 3. Change Tracking
- Configuration history
- Change attribution
- Rollback capabilities
- Change approval workflow

#### 4. Integration Features
- Git integration
- CI/CD integration
- Monitoring integration
- Alerting on changes

## Implementation Details

### Files to Create
- `tools/config-diff.nix` - Configuration diff tool
- `lib/change-analyzer.nix` - Change analysis utilities

### Configuration Diff and Preview Configuration
```nix
services.gateway.configDiff = {
  enable = true;
  
  diff = {
    algorithms = [
      {
        name: "text-diff";
        description: "Line-based text comparison";
        algorithm: "myers";
        sensitivity: "line";
      }
      {
        name: "semantic-diff";
        description: "Semantic Nix configuration comparison";
        algorithm: "ast-compare";
        sensitivity: "semantic";
      }
      {
        name: "structured-diff";
        description: "Structured data comparison";
        algorithm: "json-diff";
        sensitivity: "field";
      }
    ];
    
    output = {
      formats = [
        {
          name: "unified";
          description: "Unified diff format";
          extension: ".diff";
        }
        {
          name: "side-by-side";
          description: "Side-by-side comparison";
          extension: ".html";
        }
        {
          name: "html";
          description: "Interactive HTML diff";
          extension: ".html";
        }
        {
          name: "json";
          description: "JSON diff data";
          extension: ".json";
        }
      ];
      
      highlighting = {
        enable = true;
        
        colors = {
          added = "#28a745";
          removed = "#dc3545";
          modified = "#ffc107";
          unchanged = "#6c757d";
        };
        
        syntax = {
          nix = true;
          json = true;
          yaml = true;
        };
      };
    };
    
    filtering = {
      enable = true;
      
      categories = [
        {
          name: "network";
          description: "Network configuration changes";
          paths = [ "networking" "services.gateway.interfaces" ];
        }
        {
          name: "services";
          description: "Service configuration changes";
          paths = [ "services" ];
        }
        {
          name: "security";
          description: "Security-related changes";
          paths = [ "security" "users" "services.gateway.data.firewall" ];
        }
        {
          name: "monitoring";
          description: "Monitoring configuration changes";
          paths: [ "services.gateway.monitoring" ];
        }
      ];
      
      severity = [
        {
          name: "critical";
          description: "Critical changes requiring immediate attention";
          patterns = [ "firewall.rules" "users.*" "security.*" ];
        }
        {
          name: "major";
          description: "Major changes affecting core functionality";
          patterns: [ "networking.interfaces" "services.gateway.enable" ];
        }
        {
          name: "minor";
          description: "Minor configuration adjustments";
          patterns: [ "services.gateway.domain" "monitoring.*" ];
        }
      ];
    };
  };
  
  preview = {
    impact = {
      enable = true;
      
      analysis = [
        {
          name: "service-impact";
          description: "Analyze service impact";
          checks = [
            "service-restart-required"
            "configuration-reload-required"
            "dependency-changes"
            "resource-requirements"
          ];
        }
        {
          name: "network-impact";
          description: "Analyze network impact";
          checks = [
            "interface-changes"
            "routing-changes"
            "firewall-changes"
            "nat-changes"
          ];
        }
        {
          name: "security-impact";
          description: "Analyze security impact";
          checks = [
            "access-control-changes"
            "authentication-changes"
            "encryption-changes"
            "audit-configuration"
          ];
        }
        {
          name: "performance-impact";
          description: "Analyze performance impact";
          checks = [
            "resource-usage"
            "service-scaling"
            "configuration-complexity"
            "optimization-opportunities"
          ];
        }
      ];
      
      scoring = {
        factors = [
          { name: "service-disruption"; weight: 40; }
          { name: "security-risk"; weight: 30; }
          { name: "performance-impact"; weight: 20; }
          { name: "complexity"; weight: 10; }
        ];
        
        thresholds = {
          low = 20;
          medium = 50;
          high = 80;
          critical = 90;
        };
      };
    };
    
    validation = {
      enable = true;
      
      checks = [
        {
          name: "syntax-validation";
          description: "Validate configuration syntax";
          command: "nix-instantiate --parse";
        }
        {
          name: "type-validation";
          description: "Validate option types";
          validator: "option-validator";
        }
        {
          name: "dependency-validation";
          description: "Validate service dependencies";
          validator: "dependency-validator";
        }
        {
          name: "resource-validation";
          description: "Validate resource availability";
          validator: "resource-validator";
        }
      ];
    };
    
    simulation = {
      enable = true;
      
      scenarios = [
        {
          name: "dry-run";
          description: "Simulate configuration application";
          steps = [
            "validate-configuration"
            "check-dependencies"
            "estimate-resources"
            "predict-impact"
          ];
        }
        {
          name: "service-test";
          description: "Test service configuration";
          steps = [
            "start-services"
            "check-health"
            "verify-functionality"
            "measure-performance"
          ];
        }
      ];
    };
  };
  
  tracking = {
    history = {
      enable = true;
      
      storage = {
        type = "git";
        repository = "/var/lib/config-history";
        
        commit = {
          author = "gateway-system";
          email = "gateway@example.com";
          message = "Configuration change: {{change-summary}}";
        };
      };
      
      retention = {
        duration = "365d";
        maxCommits = 1000;
        compression = true;
      };
    };
    
    attribution = {
      enable = true;
      
      sources = [
        {
          name: "system-user";
          method: "pam";
          attributes: [ "username" "uid" "timestamp" ];
        }
        {
          name: "api-user";
          method: "jwt";
          attributes: [ "user-id" "role" "session-id" ];
        }
        {
          name: "automation";
          method: "process";
          attributes: [ "process-name" "pid" "command-line" ];
        }
      ];
      
      correlation = {
        enable = true;
        confidence = 0.8;
      };
    };
    
    approval = {
      enable = true;
      
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
  };
  
  rollback = {
    enable = true;
    
    methods = [
      {
        name: "git-rollback";
        description: "Rollback using Git history";
        steps = [
          "checkout-commit"
          "validate-configuration"
          "apply-configuration"
          "verify-services"
        ];
      }
      {
        name: "backup-rollback";
        description: "Rollback using backup files";
        steps = [
          "restore-backup"
          "validate-configuration"
          "apply-configuration"
          "verify-services"
        ];
      }
    ];
    
    automation = {
      enable = true;
      
      triggers = [
        {
          name: "deployment-failure";
          condition = "deployment.status = failed";
          action = "auto-rollback";
          timeout = "5m";
        }
        {
          name: "health-degradation";
          condition = "health.score < 50";
          action = "prompt-rollback";
          timeout = "15m";
        }
      ];
    };
  };
  
  integration = {
    git = {
      enable = true;
      
      repository = "/etc/nixos";
      branch = "main";
      
      hooks = [
        {
          name: "pre-commit";
          script: "config-diff validate";
        }
        {
          name: "pre-push";
          script: "config-diff preview";
        }
      ];
    };
    
    cicd = {
      enable = true;
      
      systems = [
        {
          name: "jenkins";
          type: "jenkins";
          server = "https://jenkins.example.com";
          job = "gateway-config";
          
          parameters = [
            { name: "config-diff"; type: "boolean"; }
            { name: "preview-only"; type: "boolean"; }
          ];
        }
        {
          name: "gitlab-ci";
          type: "gitlab";
          server = "https://gitlab.example.com";
          
          stages = [ "validate" "preview" "deploy" ];
        }
      ];
    };
    
    monitoring = {
      enable = true;
      
      metrics = [
        "config-changes"
        "deployment-duration"
        "rollback-count"
        "validation-failures"
      ];
      
      alerts = [
        {
          name: "critical-change";
          condition: "change.severity = critical";
          severity: "high";
        }
        {
          name: "validation-failure";
          condition: "validation.status = failed";
          severity: "medium";
        }
        {
          name: "rollback-triggered";
          condition: "rollback.executed = true";
          severity: "warning";
        }
      ];
    };
  };
  
  interface = {
    cli = {
      enable = true;
      
      commands = [
        {
          name: "diff";
          description: "Show configuration differences";
          usage: "config-diff diff [options] <old> <new>";
          options = [
            { name: "format"; description: "Output format"; }
            { name: "severity"; description: "Filter by severity"; }
            { name: "category"; description: "Filter by category"; }
          ];
        }
        {
          name: "preview";
          description: "Preview configuration changes";
          usage: "config-diff preview [options] <config>";
          options = [
            { name: "impact"; description: "Show impact analysis"; }
            { name: "validate"; description: "Validate configuration"; }
            { name: "simulate"; description: "Simulate deployment"; }
          ];
        }
        {
          name: "history";
          description: "Show configuration history";
          usage: "config-diff history [options]";
          options = [
            { name: "limit"; description: "Limit number of entries"; }
            { name: "author"; description: "Filter by author"; }
            { name: "since"; description: "Show changes since date"; }
          ];
        }
        {
          name: "rollback";
          description: "Rollback configuration";
          usage: "config-diff rollback [options] <commit>";
          options = [
            { name: "dry-run"; description: "Show what would be rolled back"; }
            { name: "force"; description: "Force rollback without confirmation"; }
          ];
        }
      ];
    };
    
    web = {
      enable = true;
      
      server = {
        port = 8081;
        host = "localhost";
      };
      
      ui = {
        framework = "react";
        
        components = [
          "diff-viewer"
          "impact-analyzer"
          "history-browser"
          "rollback-manager"
        ];
      };
    };
  };
};
```

### Integration Points
- Git integration
- CI/CD systems
- Monitoring integration
- Configuration validation

## Testing Requirements
- Diff accuracy tests
- Impact analysis validation
- Rollback effectiveness tests
- UI/UX testing

## Dependencies
- 01-data-validation-enhancements
- 30-configuration-drift-detection

## Estimated Effort
- High (complex diff system)
- 4 weeks implementation
- 3 weeks testing

## Success Criteria
- Accurate configuration diffing
- Comprehensive impact analysis
- Reliable rollback functionality
- Good user experience
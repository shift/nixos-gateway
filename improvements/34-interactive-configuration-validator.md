# Interactive Configuration Validator

**Status: Pending**

## Description
Create an interactive configuration validation tool with real-time feedback, suggestions, and error correction.

## Requirements

### Current State
- Basic validation functions
- No interactive validation
- Limited error messages

### Improvements Needed

#### 1. Interactive Validation Framework
- Real-time validation feedback
- Interactive error correction
- Configuration suggestions
- Validation progress tracking

#### 2. Validation Features
- Syntax checking
- Semantic validation
- Best practices checking
- Security validation

#### 3. User Interface
- Command-line interface
- Web-based interface
- IDE integration
- API access

#### 4. Advanced Features
- Configuration completion
- Template suggestions
- Migration assistance
- Performance analysis

## Implementation Details

### Files to Create
- `tools/config-validator.nix` - Configuration validator tool
- `lib/validation-engine.nix` - Validation engine utilities

### Interactive Configuration Validator Configuration
```nix
services.gateway.configValidator = {
  enable = true;
  
  validation = {
    syntax = {
      enable = true;
      
      checks = [
        {
          name = "nix-syntax";
          description = "Check Nix expression syntax";
          command = "nix-instantiate --parse";
          severity = "error";
        }
        {
          name = "json-syntax";
          description = "Check JSON syntax";
          command = "jq .";
          severity = "error";
        }
        {
          name = "yaml-syntax";
          description = "Check YAML syntax";
          command = "yamllint";
          severity = "error";
        }
      ];
    };
    
    semantic = {
      enable = true;
      
      checks = [
        {
          name = "option-validation";
          description = "Validate option types and values";
          validator = "option-validator";
          severity = "error";
        }
        {
          name = "dependency-check";
          description = "Check service dependencies";
          validator = "dependency-validator";
          severity = "warning";
        }
        {
          name = "resource-validation";
          description = "Validate resource availability";
          validator = "resource-validator";
          severity = "warning";
        }
      ];
    };
    
    security = {
      enable = true;
      
      checks = [
        {
          name = "secret-detection";
          description = "Detect exposed secrets";
          validator = "secret-scanner";
          severity = "error";
        }
        {
          name = "permission-check";
          description = "Check file permissions";
          validator = "permission-validator";
          severity = "warning";
        }
        {
          name = "network-security";
          description = "Validate network security";
          validator = "security-validator";
          severity = "warning";
        }
      ];
    };
    
    bestPractices = {
      enable = true;
      
      checks = [
        {
          name = "naming-conventions";
          description = "Check naming conventions";
          validator = "naming-validator";
          severity = "info";
        }
        {
          name = "code-style";
          description = "Check code style";
          validator = "style-validator";
          severity = "info";
        }
        {
          name = "performance";
          description = "Check performance implications";
          validator = "performance-validator";
          severity = "warning";
        }
      ];
    };
  };
  
  interface = {
    cli = {
      enable = true;
      
      commands = [
        {
          name = "validate";
          description = "Validate configuration";
          usage = "gateway-validator validate [options] <config-file>";
          options = [
            { name: "syntax"; description: "Check syntax only"; }
            { name: "semantic"; description: "Check semantic validity"; }
            { name: "security"; description: "Check security issues"; }
            { name: "best-practices"; description: "Check best practices"; }
            { name: "interactive"; description: "Interactive validation"; }
          ];
        }
        {
          name = "fix";
          description = "Auto-fix configuration issues";
          usage = "gateway-validator fix [options] <config-file>";
          options = [
            { name: "auto"; description: "Auto-fix all issues"; }
            { name: "interactive"; description: "Interactive fixing"; }
            { name: "backup"; description: "Create backup before fixing"; }
          ];
        }
        {
          name: "suggest";
          description: "Suggest improvements";
          usage = "gateway-validator suggest [options] <config-file>";
          options = [
            { name: "performance"; description: "Performance suggestions"; }
            { name: "security"; description: "Security suggestions"; }
            { name: "best-practices"; description: "Best practice suggestions"; }
          ];
        }
      ];
      
      interactive = {
        enable = true;
        
        features = [
          "real-time-validation"
          "error-highlighting"
          "auto-completion"
          "suggestion-system"
        ];
        
        ui = {
          colors = true;
          progress = true;
          status = true;
        };
      };
    };
    
    web = {
      enable = true;
      
      server = {
        port = 8080;
        host = "localhost";
        ssl = false;
      };
      
      ui = {
        framework = "react";
        theme = "dark";
        
        features = [
          "drag-drop-config"
          "real-time-validation"
          "error-visualization"
          "suggestion-panel"
        ];
      };
      
      api = {
        enable = true;
        version = "v1";
        
        endpoints = [
          {
            path: "/validate";
            method: "POST";
            description: "Validate configuration";
          }
          {
            path: "/fix";
            method: "POST";
            description: "Fix configuration issues";
          }
          {
            path: "/suggest";
            method: "POST";
            description: "Get suggestions";
          }
        ];
      };
    };
    
    ide = {
      enable = true;
      
      plugins = [
        {
          name: "vscode";
          language = "nix";
          features = [
            "real-time-validation"
            "error-highlighting"
            "auto-completion"
            "quick-fixes"
          ];
        }
        {
          name: "intellij";
          language = "nix";
          features = [
            "syntax-validation"
            "semantic-analysis"
            "code-inspection"
            "quick-actions"
          ];
        }
      ];
    };
  };
  
  suggestions = {
    enable = true;
    
    types = [
      {
        name: "performance";
        description: "Performance optimization suggestions";
        
        rules = [
          {
            condition = "service.enable = true && service.performance = undefined";
            suggestion = "Consider adding performance tuning for better throughput";
            priority = "medium";
          }
          {
            condition = "network.interface.mtu > 1500";
            suggestion = "Ensure all devices support jumbo frames";
            priority = "low";
          }
        ];
      }
      {
        name: "security";
        description: "Security improvement suggestions";
        
        rules = [
          {
            condition = "firewall.allowedTCPPorts = [ 22 ]";
            suggestion = "Consider restricting SSH access to specific IPs";
            priority = "high";
          }
          {
            condition = "services.gateway.secrets = undefined";
            suggestion = "Consider using secrets management for sensitive data";
            priority = "high";
          }
        ];
      }
      {
        name: "best-practices";
        description: "Best practice suggestions";
        
        rules = [
          {
            condition = "backup.enable = undefined";
            suggestion = "Consider enabling backup for disaster recovery";
            priority = "medium";
          }
          {
            condition = "monitoring.enable = undefined";
            suggestion = "Consider enabling monitoring for observability";
            priority = "medium";
          }
        ];
      }
    ];
    
    ranking = {
      factors = [
        { name: "impact"; weight: 40; }
        { name: "effort"; weight: 30; }
        { name: "risk"; weight: 20; }
        { name: "popularity"; weight: 10; }
      ];
    };
  };
  
  autoFix = {
    enable = true;
    
    fixes = [
      {
        name: "syntax-error";
        description = "Fix common syntax errors";
        
        patterns = [
          {
            pattern: "=(?!=)";
            replacement: "==";
            description: "Replace = with ==";
          }
          {
            pattern: "(\\w+)\\s+\\{";
            replacement: "\\1 = {";
            description: "Add assignment operator";
          }
        ];
      }
      {
        name: "option-typo";
        description = "Fix common option typos";
        
        patterns = [
          {
            pattern: "enabel";
            replacement: "enable";
            description: "Fix enable typo";
          }
          {
            pattern: "inteface";
            replacement: "interface";
            description: "Fix interface typo";
          }
        ];
      }
      {
        name: "missing-option";
        description = "Add missing required options";
        
        rules = [
          {
            condition = "services.gateway.enable = true && services.gateway.domain = undefined";
            action: "add-option";
            option: "domain";
            value: "\"lan.local\"";
          }
        ];
      }
    ];
    
    safety = {
      enable = true;
      
      backup = true;
      confirmation = true;
      dryRun = true;
      
      riskAssessment = true;
      rollback = true;
    };
  };
  
  reporting = {
    enable = true;
    
    formats = [
      {
        name: "json";
        description: "JSON format output";
        fields: [ "errors" "warnings" "suggestions" "summary" ];
      }
      {
        name: "yaml";
        description: "YAML format output";
        fields: [ "errors" "warnings" "suggestions" "summary" ];
      }
      {
        name: "table";
        description: "Table format output";
        columns: [ "severity" "message" "line" "suggestion" ];
      }
      {
        name: "html";
        description: "HTML report";
        template: "/templates/validation-report.html";
      }
    ];
    
    metrics = {
      enable = true;
      
      counters = [
        "validation-runs"
        "errors-found"
        "warnings-found"
        "suggestions-made"
        "auto-fixes-applied"
      ];
      
      timing = [
        "validation-duration"
        "fix-duration"
        "suggestion-generation-time"
      ];
    };
  };
};
```

### Integration Points
- Configuration validation library
- IDE plugins
- Web interface
- API endpoints

## Testing Requirements
- Validation accuracy tests
- Auto-fix effectiveness tests
- UI/UX testing
- Performance tests

## Dependencies
- 01-data-validation-enhancements
- 05-configuration-templates

## Estimated Effort
- High (complex validator tool)
- 4 weeks implementation
- 3 weeks testing

## Success Criteria
- Accurate validation results
- Helpful suggestions
- Effective auto-fixes
- Good user experience
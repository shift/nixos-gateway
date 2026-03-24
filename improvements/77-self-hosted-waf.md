# Self-Hosted Web Application Firewall (WAF)

**Status: Pending**

## Description
Implement a comprehensive self-hosted Web Application Firewall module to replace cloud-based WAF services like Azure Application Gateway WAF, GCP Cloud Armor, and AWS WAF. The module will provide advanced threat protection, compliance features, and seamless integration with the NixOS Gateway framework.

## Requirements

### Current State
- No built-in WAF capabilities in the gateway
- Basic firewall rules at network level only
- No application-layer threat protection
- Reliance on external cloud WAF services
- Limited visibility into web application attacks

### Improvements Needed

#### 1. Core WAF Engine
- Implement ModSecurity or similar engine integration
- OWASP Core Rule Set (CRS) support
- Custom rule creation and management
- Real-time rule updates and synchronization
- Performance-optimized rule processing

#### 2. Threat Detection and Prevention
- SQL injection protection
- Cross-Site Scripting (XSS) prevention
- Cross-Site Request Forgery (CSRF) protection
- Command injection detection
- File inclusion attack prevention
- HTTP protocol violation detection

#### 3. Advanced Security Features
- Rate limiting and DDoS protection at application layer
- Bot detection and mitigation
- Session management and protection
- Input validation and sanitization
- Anomaly detection based on behavior patterns
- Geo-blocking and IP reputation integration

#### 4. Compliance and Auditing
- PCI DSS compliance rule sets
- HIPAA compliance configurations
- GDPR data protection features
- Comprehensive audit logging
- Security event correlation
- Compliance reporting and dashboards

#### 5. Integration and Management
- Reverse proxy integration (nginx/haproxy)
- API gateway compatibility
- Centralized management interface
- Configuration templating
- Multi-site deployment support
- High availability clustering

## Implementation Details

### Files to Create
- `modules/waf.nix` - Main WAF module configuration
- `lib/waf-rules.nix` - Rule management and generation
- `lib/waf-compliance.nix` - Compliance rule sets
- `modules/waf-monitoring.nix` - WAF-specific monitoring
- `templates/waf-config/` - Configuration templates

### New Configuration Options
```nix
services.gateway.waf = {
  enable = lib.mkEnableOption "Web Application Firewall";

  engine = lib.mkOption {
    type = lib.types.enum [ "modsecurity" "coraza" ];
    default = "modsecurity";
    description = "WAF engine to use";
  };

  sites = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        enable = lib.mkEnableOption "WAF for this site";

        rules = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "Custom WAF rules";
        };

        crs = {
          enable = lib.mkEnableOption "OWASP Core Rule Set";
          paranoiaLevel = lib.mkOption {
            type = lib.types.ints.between 1 4;
            default = 1;
            description = "CRS paranoia level";
          };
        };

        rateLimit = {
          enable = lib.mkEnableOption "Rate limiting";
          requestsPerMinute = lib.mkOption {
            type = lib.types.int;
            default = 1000;
            description = "Requests per minute limit";
          };
        };

        compliance = lib.mkOption {
          type = lib.types.listOf (lib.types.enum [ "pci-dss" "hipaa" "gdpr" ]);
          default = [];
          description = "Compliance standards to enforce";
        };
      };
    });
  };

  monitoring = {
    enable = lib.mkEnableOption "WAF monitoring";
    metricsPort = lib.mkOption {
      type = lib.types.port;
      default = 9092;
      description = "Port for WAF metrics export";
    };
  };
};
```

### Integration Points
- Reverse proxy modules for traffic interception
- Monitoring module for security event collection
- Alerting system for threat notifications
- Log aggregation for centralized security analysis
- Configuration management for rule updates
- Health checks for WAF service status

### Rule Management System
```nix
# lib/waf-rules.nix
mkWAFRule = { id, phase, variables, operator, actions }: /* ... */;

# Predefined rule sets
owaspCRS = import ./crs-rules.nix;
pciRules = import ./pci-rules.nix;
customRules = import ./custom-rules.nix;
```

## Testing Requirements
- Security vulnerability scanning (OWASP ZAP, Nikto)
- Performance benchmarking under attack simulation
- False positive/negative rate testing
- Compliance validation testing
- Multi-site configuration testing
- Failover and high availability testing
- Rule update mechanism testing

## Dependencies
- Task 74: Self-Hosted API Gateway (for integration)
- Task 18: Log Aggregation (for security events)
- Task 19: Health Monitoring (for WAF status)
- Task 25: Threat Intelligence Integration (for IP reputation)

## Estimated Effort
- High (complex security implementation)
- 4-6 weeks implementation
- 2-3 weeks security testing and validation
- 1 week performance optimization

## Success Criteria
- Blocks 99%+ of OWASP Top 10 attacks
- Sub-5ms latency overhead for legitimate traffic
- PCI DSS Level 1 compliance certification
- Zero false positives in production testing
- Seamless integration with existing gateway services
- Comprehensive security event logging and alerting
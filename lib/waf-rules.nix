{ lib }:

let
  # Helper function to create ModSecurity rules
  mkModSecurityRule = {
    id,
    phase ? 2,
    variables ? ["REQUEST_URI"],
    operator ? "@rx",
    pattern,
    actions ? ["deny"],
    msg ? "",
    severity ? "CRITICAL",
    ...
  }: ''
    SecRule ${lib.concatStringsSep "|" variables} "${operator} ${pattern}" "${lib.concatStringsSep "," actions},id:${toString id},phase:${toString phase},msg:'${msg}',severity:${severity}''
  '';

  # OWASP Core Rule Set rules
  owaspCRS = {
    # SQL Injection rules
    sqlInjection = [
      (mkModSecurityRule {
        id = 1001;
        variables = ["ARGS"];
        pattern = "(?i)(union.*select|select.*from|insert.*into|update.*set|delete.*from)";
        msg = "SQL Injection Attack";
        actions = ["deny" "log"];
      })
      (mkModSecurityRule {
        id = 1002;
        variables = ["ARGS"];
        pattern = "(?i)(;|--|\#|\/\*|\*\/)";
        msg = "SQL Injection Comment Attack";
        actions = ["deny" "log"];
      })
    ];

    # Cross-Site Scripting rules
    xss = [
      (mkModSecurityRule {
        id = 2001;
        variables = ["ARGS"];
        pattern = "(?i)(<script|javascript:|vbscript:|onload=|onerror=)";
        msg = "Cross-Site Scripting Attack";
        actions = ["deny" "log"];
      })
      (mkModSecurityRule {
        id = 2002;
        variables = ["ARGS"];
        pattern = "(?i)(<iframe|<object|<embed|<link|<meta)";
        msg = "HTML Injection Attack";
        actions = ["deny" "log"];
      })
    ];

    # Command Injection rules
    commandInjection = [
      (mkModSecurityRule {
        id = 3001;
        variables = ["ARGS"];
        pattern = "(?i)(\\|\||&&|;|`|\$\(|\$\{)";
        msg = "Command Injection Attack";
        actions = ["deny" "log"];
      })
    ];

    # Path Traversal rules
    pathTraversal = [
      (mkModSecurityRule {
        id = 4001;
        variables = ["ARGS"];
        pattern = "(?i)(\\.\\./|\\.\\.|\\.\\/)";
        msg = "Path Traversal Attack";
        actions = ["deny" "log"];
      })
    ];
  };

  # Compliance rule sets
  complianceRules = {
    pci-dss = [
      # PCI DSS specific rules
      (mkModSecurityRule {
        id = 5001;
        variables = ["REQUEST_HEADERS:User-Agent"];
        pattern = "(?i)(sqlmap|nikto|dirbuster|acunetix|nmap)";
        msg = "PCI DSS: Security Scanner Detected";
        actions = ["deny" "log"];
        severity = "WARNING";
      })
    ];

    hipaa = [
      # HIPAA specific rules
      (mkModSecurityRule {
        id = 6001;
        variables = ["ARGS"];
        pattern = "(?i)(ssn|social.security|medical.record|patient.id)";
        msg = "HIPAA: Sensitive Data Exposure Attempt";
        actions = ["deny" "log"];
        severity = "CRITICAL";
      })
    ];

    gdpr = [
      # GDPR specific rules
      (mkModSecurityRule {
        id = 7001;
        variables = ["ARGS"];
        pattern = "(?i)(personal.data|gdpr|data.subject)";
        msg = "GDPR: Personal Data Access Attempt";
        actions = ["log"];
        severity = "NOTICE";
      })
    ];
  };

  # Rate limiting rules
  rateLimitRules = requestsPerMinute: [
    ''
      SecAction "id:900001,phase:1,nolog,pass,setvar:tx.ratelimit_requests=${toString requestsPerMinute}"
      SecRule TX:RATELIMIT_REQUESTS "@gt ${toString requestsPerMinute}" "id:900002,phase:1,deny,status:429,msg:'Rate limit exceeded'"
    ''
  ];

  # Bot detection rules
  botDetectionRules = [
    (mkModSecurityRule {
      id = 8001;
      variables = ["REQUEST_HEADERS:User-Agent"];
      pattern = "(?i)(bot|crawler|spider|scanner)";
      msg = "Bot Detected";
      actions = ["log"];
      severity = "NOTICE";
    })
  ];

  # Generate complete rule set for a site
  generateSiteRules = siteConfig: let
    rules = []
      ++ (if siteConfig.crs.enable then owaspCRS.sqlInjection ++ owaspCRS.xss ++ owaspCRS.commandInjection ++ owaspCRS.pathTraversal else [])
      ++ (if siteConfig.rateLimit.enable then rateLimitRules siteConfig.rateLimit.requestsPerMinute else [])
      ++ botDetectionRules
      ++ (lib.concatMap (compliance: complianceRules.${compliance} or []) siteConfig.compliance)
      ++ siteConfig.rules;
  in ''
    # WAF Configuration for ${siteConfig._module.args.name or "site"}
    SecRuleEngine On
    SecDebugLog /etc/waf/logs/modsec_debug.log
    SecDebugLogLevel 3
    SecAuditEngine RelevantOnly
    SecAuditLog /etc/waf/logs/modsec_audit.log

    # Default actions
    SecDefaultAction "phase:2,deny,log,status:403"

    # Core rules
    ${lib.concatStringsSep "\n" rules}
  '';

in {
  inherit
    mkModSecurityRule
    owaspCRS
    complianceRules
    rateLimitRules
    botDetectionRules
    generateSiteRules;
}
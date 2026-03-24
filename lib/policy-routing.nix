{ lib }:

let
  # Constants
  complexRuleBaseMark = 4096;

  # Policy routing rule types
  policyAction = lib.types.enum [
    "route"
    "multipath"
    "blackhole"
    "prohibit"
    "unreachable"
  ];

  # Helper to detect if a rule is "complex" (requires nftables marking)
  isComplexRule = rule: rule.match ? time && rule.match.time != null;

  # Validate policy rule - MOVED TO LET BLOCK so it's accessible in generatePolicyConfig
  validatePolicyRule =
    rule:
    let
      errors = [ ];
      # Check if match criteria are valid
      hasMatchCriteria =
        rule.match.sourceAddress != null
        || rule.match.destinationAddress != null
        || rule.match.protocol != null
        || rule.match.sourcePort != null
        || rule.match.destinationPort != null
        || rule.match.inputInterface != null
        || rule.match.outputInterface != null
        || rule.match.fwmark != null
        || rule.match.dscp != null
        || rule.match.tos != null
        || isComplexRule rule;

      # Check action consistency
      actionValid =
        if rule.action.action == "route" then
          rule.action.table != null
        else if rule.action.action == "multipath" then
          rule.action.tables != [ ] && rule.action.weights != { }
        else
          true;
    in
    {
      valid = hasMatchCriteria && actionValid;
      errors =
        errors
        ++ (if !hasMatchCriteria then [ "Policy rule must have at least one match criterion" ] else [ ])
        ++ (if !actionValid then [ "Policy action configuration is invalid" ] else [ ]);
      warnings = [ ];
    };

in
{
  inherit isComplexRule;

  # Generate fwmark for a complex rule based on its index
  # We use a base offset (e.g., 0x1000 or 4096) + index
  getComplexRuleMark = index: complexRuleBaseMark + index;

  # Generate nftables rule for complex matching
  # Returns a string like: "meta time \"08:00\"-\"17:00\" meta mark set 0x1000"
  generateNftablesRule =
    rule: index:
    let
      match = rule.match;
      mark = complexRuleBaseMark + index;

      # Build match parts
      matches = [
        (if (isComplexRule rule) then "meta time \"${match.time.start}\"-\"${match.time.end}\"" else null)
        (if (match.sourceAddress or null != null) then "ip saddr ${match.sourceAddress}" else null)
        (
          if (match.destinationAddress or null != null) then "ip daddr ${match.destinationAddress}" else null
        )
        (if (match.protocol or null != null) then "ip protocol ${match.protocol}" else null)
        (
          if (match.sourcePort or null != null) then
            if builtins.isList match.sourcePort then
              "tcp sport { ${lib.concatStringsSep ", " (map toString match.sourcePort)} }"
            else
              "tcp sport ${toString match.sourcePort}"
          else
            null
        )
        (
          if (match.destinationPort or null != null) then
            if builtins.isList match.destinationPort then
              "tcp dport { ${lib.concatStringsSep ", " (map toString match.destinationPort)} }"
            else
              "tcp dport ${toString match.destinationPort}"
          else
            null
        )
        (if (match.inputInterface or null != null) then "iifname \"${match.inputInterface}\"" else null)
        (if (match.outputInterface or null != null) then "oifname \"${match.outputInterface}\"" else null)
      ];

      matchStr = lib.concatStringsSep " " (lib.filter (x: x != null) matches);
    in
    if (isComplexRule rule) then "${matchStr} meta mark set ${toString mark}" else null;

  # Generate ip rule command from policy rule
  # Returns a list of argument strings (one for each port combination)
  generateIpRule =
    rule: index:
    let
      match = rule.match;
      action = rule.action;
      isComplex = isComplexRule rule;
      mark = if isComplex then (complexRuleBaseMark + index) else match.fwmark;

      # Normalize ports to lists to handle single port or list of ports
      sourcePorts =
        if match.sourcePort == null then
          [ null ]
        else if builtins.isList match.sourcePort then
          match.sourcePort
        else
          [ match.sourcePort ];

      destPorts =
        if match.destinationPort == null then
          [ null ]
        else if builtins.isList match.destinationPort then
          match.destinationPort
        else
          [ match.destinationPort ];

      # Function to generate arguments for a single combination
      mkArgs = sp: dp: [
        (if (match.sourceAddress != null) then "from ${match.sourceAddress}" else null)
        (if (match.destinationAddress != null) then "to ${match.destinationAddress}" else null)
        (if (match.protocol != null) then "ipproto ${match.protocol}" else null)
        (if (sp != null) then "sport ${toString sp}" else null)
        (if (dp != null) then "dport ${toString dp}" else null)
        (if (match.inputInterface != null) then "iif ${match.inputInterface}" else null)
        (if (match.outputInterface != null) then "oif ${match.outputInterface}" else null)
        (if (mark != null) then "fwmark ${toString mark}" else null)
        (if (match.dscp != null) then "dscp ${toString match.dscp}" else null)
        (if (match.tos != null) then "tos ${toString match.tos}" else null)
        (if (action.table != null) then "lookup ${action.table}" else null)
        (if (action.action == "blackhole") then "blackhole" else null)
        (if (action.action == "prohibit") then "prohibit" else null)
        (if (action.action == "unreachable") then "unreachable" else null)
        "priority ${toString action.priority}"
      ];

      # For complex rules, we only generate one rule based on fwmark,
      # ignoring other match criteria in the ip rule command (handled by nftables)
      # except for action-related parameters
      complexRuleArgs = [
        "fwmark ${toString mark}"
        (if (action.table != null) then "lookup ${action.table}" else null)
        (if (action.action == "blackhole") then "blackhole" else null)
        (if (action.action == "prohibit") then "prohibit" else null)
        (if (action.action == "unreachable") then "unreachable" else null)
        "priority ${toString action.priority}"
      ];
    in
    if isComplex then
      [ (lib.concatStringsSep " " (lib.filter (x: x != null) complexRuleArgs)) ]
    else
      lib.flatten (
        map (
          sp:
          map (
            dp:
            let
              args = lib.filter (x: x != null) (mkArgs sp dp);
              argsStr = lib.concatStringsSep " " args;
            in
            if argsStr == "" then "" else argsStr
          ) destPorts
        ) sourcePorts
      );

  # Generate ip route command for multipath
  generateMultipathRoute =
    tables: weights: gateways:
    let
      tableRoutes = lib.mapAttrsToList (
        table: weight:
        let
          gateway = gateways.${table} or (throw "No default route defined for table ${table}");
        in
        "nexthop via ${gateway} weight ${toString weight}"
      ) weights;
    in
    lib.concatStringsSep " " tableRoutes;

  # Generate policy routing configuration validation result
  generatePolicyConfig =
    config:
    let
      enabledPolicies = lib.filterAttrs (_: policy: policy.enabled or true) config.policies;
      policyRules = lib.mapAttrsToList (_: policy: policy.rules or [ ]) enabledPolicies;
      allRules = lib.flatten policyRules;

      validatedRules = map validatePolicyRule allRules;
      invalidRules = lib.filterAttrs (_: validation: !validation.valid) (
        lib.listToAttrs (
          map (rule: {
            name = rule.name;
            value = validatePolicyRule rule;
          }) allRules
        )
      );
    in
    {
      valid = invalidRules == { };
      errors = lib.mapAttrsToList (
        name: validation: "Rule ${name}: ${lib.concatStringsSep ", " validation.errors}"
      ) invalidRules;
      warnings = [ ];
      rules = allRules;
      tables = config.routingTables;
    };

  # Keep the simplified ones for backward compat if needed or refactoring
  mkRuleCommand =
    {
      priority,
      match,
      action,
      table,
      ...
    }:
    throw "mkRuleCommand is deprecated and should not be used. Use generateIpRule instead.";
}

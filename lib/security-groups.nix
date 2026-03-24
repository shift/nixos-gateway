{ lib, pkgs }:

let
  # Generate iptables rules from security group rules
  generateFirewallRules =
    securityGroups:
    lib.flatten (
      map (
        sg:
        map (
          rule:
          let
            chain = if rule.type == "ingress" then "INPUT" else "OUTPUT";
            action = "-j ACCEPT";
            protocol = if rule.protocol == "all" then "" else "-p ${rule.protocol}";
            portSpec =
              if rule.portRange != null then
                "-m ${rule.protocol} --dport ${toString rule.portRange.from}:${toString rule.portRange.to}"
              else
                "";
            sources = lib.concatStringsSep " " (map (src: "-s ${src}") rule.sources);
            comment = "# Security Group: ${sg.name} - ${rule.description}";
          in
          "${pkgs.iptables}/bin/iptables -A ${chain} ${protocol} ${portSpec} ${sources} ${action} ${comment}"
        ) sg.rules
      ) securityGroups
    );

  # Validate security group configuration
  validateSecurityGroups =
    securityGroups:
    let
      names = map (sg: sg.name) securityGroups;
      uniqueNames = lib.unique names;
    in
    if lib.length names != lib.length uniqueNames then
      throw "Security group names must be unique"
    else
      lib.all (
        sg:
        lib.all (
          rule:
          if rule.type == "egress" && rule.sources == [ ] then
            throw "Egress rules must specify sources"
          else if rule.protocol != "all" && rule.portRange == null then
            throw "Port range required for protocol ${rule.protocol}"
          else
            true
        ) sg.rules
      ) securityGroups;

  # Generate default security groups
  generateDefaultSecurityGroups = interface: [
    {
      name = "default-${interface}";
      rules = [
        {
          type = "ingress";
          protocol = "tcp";
          portRange = {
            from = 22;
            to = 22;
          };
          sources = [ "0.0.0.0/0" ];
          description = "SSH access";
        }
        {
          type = "ingress";
          protocol = "tcp";
          portRange = {
            from = 80;
            to = 80;
          };
          sources = [ "0.0.0.0/0" ];
          description = "HTTP access";
        }
        {
          type = "ingress";
          protocol = "tcp";
          portRange = {
            from = 443;
            to = 443;
          };
          sources = [ "0.0.0.0/0" ];
          description = "HTTPS access";
        }
        {
          type = "egress";
          protocol = "all";
          portRange = null;
          sources = [ "0.0.0.0/0" ];
          description = "Allow all outbound traffic";
        }
      ];
    }
  ];

  # Merge security groups (for combining multiple groups)
  mergeSecurityGroups =
    groups:
    let
      allRules = lib.flatten (map (g: g.rules) groups);
      uniqueRules = lib.unique allRules;
    in
    {
      name = "merged-group";
      rules = uniqueRules;
    };

  # Generate security group references for instances
  generateInstanceSecurityGroups =
    instanceConfig:
    let
      baseGroups = instanceConfig.securityGroups or [ ];
      defaultGroups = generateDefaultSecurityGroups instanceConfig.interface;
    in
    baseGroups ++ defaultGroups;

  # Convert security groups to iptables chains
  createSecurityGroupChains =
    securityGroups:
    lib.concatStringsSep "\n" (
      map (sg: ''
        # Create chain for security group ${sg.name}
        ${pkgs.iptables}/bin/iptables -N SG_${lib.toUpper (lib.replaceStrings [ "-" ] [ "_" ] sg.name)}
        ${lib.concatStringsSep "\n" (
          map (
            rule:
            let
              action = "-j ACCEPT";
              protocol = if rule.protocol == "all" then "" else "-p ${rule.protocol}";
              portSpec =
                if rule.portRange != null then
                  "-m ${rule.protocol} --dport ${toString rule.portRange.from}:${toString rule.portRange.to}"
                else
                  "";
              sources = lib.concatStringsSep " " (map (src: "-s ${src}") rule.sources);
            in
            "${pkgs.iptables}/bin/iptables -A SG_${
              lib.toUpper (lib.replaceStrings [ "-" ] [ "_" ] sg.name)
            } ${protocol} ${portSpec} ${sources} ${action}"
          ) sg.rules
        )}
        # Default drop rule
        ${pkgs.iptables}/bin/iptables -A SG_${
          lib.toUpper (lib.replaceStrings [ "-" ] [ "_" ] sg.name)
        } -j DROP
      '') securityGroups
    );

  # Apply security groups to interface
  applySecurityGroupsToInterface =
    interface: securityGroups:
    lib.concatStringsSep "\n" [
      "# Apply security groups to ${interface}"
      (createSecurityGroupChains securityGroups)
      "${pkgs.iptables}/bin/iptables -A INPUT -i ${interface} -j SG_${
        lib.toUpper (lib.replaceStrings [ "-" ] [ "_" ] (lib.head securityGroups).name)
      }"
    ];

  # Generate security audit rules
  generateAuditRules =
    securityGroups:
    map (
      sg:
      map (rule: {
        inherit (rule)
          type
          protocol
          sources
          description
          ;
        securityGroup = sg.name;
        timestamp = builtins.currentTime;
      }) sg.rules
    ) securityGroups;

  # Check for security group conflicts
  checkSecurityConflicts =
    securityGroups:
    let
      allRules = lib.flatten (map (sg: sg.rules) securityGroups);
      conflictingRules = lib.filter (
        rule:
        lib.any (
          otherRule:
          rule != otherRule
          && rule.protocol == otherRule.protocol
          && rule.portRange == otherRule.portRange
          && rule.type == otherRule.type
          && rule.sources == otherRule.sources
        ) allRules
      ) allRules;
    in
    if conflictingRules != [ ] then
      builtins.trace "Warning: Conflicting security group rules detected" conflictingRules
    else
      [ ];

in
{
  inherit
    generateFirewallRules
    validateSecurityGroups
    generateDefaultSecurityGroups
    mergeSecurityGroups
    generateInstanceSecurityGroups
    createSecurityGroupChains
    applySecurityGroupsToInterface
    generateAuditRules
    checkSecurityConflicts
    ;
}

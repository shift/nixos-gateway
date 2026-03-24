{ lib }:

let
  types = import ./types.nix { inherit lib; };
  validators = import ./validators.nix { inherit lib; };
in
{
  # Enhanced validation with detailed error reporting
  validateWithDetails =
    validator: value:
    let
      result = builtins.tryEval (validator value);
    in
    if result.success then
      {
        success = true;
        value = result.value;
        errors = [ ];
      }
    else
      {
        success = false;
        value = null;
        errors = [ "Validation failed for value: ${toString value}" ];
      };

  # Data migration support
  migrateData =
    currentVersion: targetVersion: data:
    let
      migrate_1_0_to_1_1 =
        oldData:
        # Example migration: rename firewall.rules to firewall.policies
        if oldData ? firewall && oldData.firewall ? rules then
          let
            newFirewall = oldData.firewall // {
              policies = oldData.firewall.rules;
            };
          in
          oldData // { firewall = newFirewall; }
        else
          oldData;

      migrate_1_1_to_1_2 =
        oldData:
        # Example migration: convert port strings to integers
        let
          migratePort = port: if builtins.isString port then lib.toInts port else port;
          migrateRule =
            rule:
            rule
            // {
              sourcePort = if rule ? sourcePort then migratePort rule.sourcePort else null;
              destinationPort = if rule ? destinationPort then migratePort rule.destinationPort else null;
            };
        in
        if oldData ? firewall && oldData.firewall ? rules then
          let
            newFirewall = oldData.firewall // {
              rules = map migrateRule oldData.firewall.rules;
            };
          in
          oldData // { firewall = newFirewall; }
        else
          oldData;

      applyMigration =
        from: to: data:
        if from == to then
          data
        else if from == "1.0" && to == "1.1" then
          migrate_1_0_to_1_1 data
        else if from == "1.1" && to == "1.2" then
          migrate_1_1_to_1_2 data
        else
          data;
    in
    applyMigration currentVersion targetVersion data;

  # Configuration linting
  lintConfiguration =
    data:
    let
      lintRules = [
        {
          name = "check-empty-arrays";
          check =
            d:
            if d ? firewall && d.firewall ? rules && d.firewall.rules == [ ] then
              { warning = "Firewall rules array is empty - no protection configured"; }
            else
              null;
        }
        {
          name = "check-default-passwords";
          check =
            d:
            if
              d ? hosts
              && lib.any (host: host ? password && host.password == "password") d.hosts.staticDHCPv4Assignments
            then
              { warning = "Host using default password 'password'"; }
            else
              null;
        }
        {
          name = "check-dhcp-range-size";
          check =
            d:
            if d ? network && d.network ? subnets then
              let
                checkSubnet =
                  subnet:
                  if subnet ? dhcpRange then
                    let
                      start = lib.toInts (builtins.head (builtins.split "\\." subnet.dhcpRange.start));
                      end = lib.toInts (builtins.head (builtins.split "\\." subnet.dhcpRange.end));
                      rangeSize = end - start + 1;
                    in
                    if rangeSize > 1000 then
                      {
                        warning = "DHCP range for ${subnet.name} is large (${toString rangeSize} addresses) - consider reducing";
                      }
                    else
                      null
                  else
                    null;
                warnings = map checkSubnet d.network.subnets;
              in
              if warnings == [ ] then null else builtins.head warnings
            else
              null;
        }
      ];

      results = map (rule: rule.check data) lintRules;
      warnings = builtins.filter (x: x != null) results;
    in
    {
      warnings = warnings;
      suggestions = map (w: w.warning) warnings;
    };

  # Performance impact analysis
  analyzePerformance =
    data:
    let
      countRules =
        if data ? firewall && data.firewall ? rules then builtins.length data.firewall.rules else 0;
      countHosts =
        if data ? hosts && data.hosts ? staticDHCPv4Assignments then
          builtins.length data.hosts.staticDHCPv4Assignments
        else
          0;
      countSubnets =
        if data ? network && data.network ? subnets then builtins.length data.network.subnets else 0;

      impact = {
        firewall = {
          ruleCount = countRules;
          impact =
            if countRules < 50 then
              "low"
            else if countRules < 200 then
              "medium"
            else
              "high";
          recommendation =
            if countRules > 200 then "Consider consolidating firewall rules for better performance" else "";
        };
        dhcp = {
          hostCount = countHosts;
          impact =
            if countHosts < 100 then
              "low"
            else if countHosts < 500 then
              "medium"
            else
              "high";
          recommendation =
            if countHosts > 500 then
              "Consider using DHCP ranges instead of static assignments where possible"
            else
              "";
        };
        network = {
          subnetCount = countSubnets;
          impact =
            if countSubnets < 10 then
              "low"
            else if countSubnets < 50 then
              "medium"
            else
              "high";
          recommendation =
            if countSubnets > 50 then "Large number of subnets may impact routing performance" else "";
        };
      };
    in
    impact;

  # Version compatibility checking
  checkCompatibility =
    data:
    let
      dataVersion = data.version or "1.0";
      currentVersion = "1.2";

      compatibility = {
        "1.0" = {
          compatible = true;
          warnings = [ "Consider migrating to version 1.2 for enhanced features" ];
          migrationAvailable = true;
        };
        "1.1" = {
          compatible = true;
          warnings = [ "Minor migration available to version 1.2" ];
          migrationAvailable = true;
        };
        "1.2" = {
          compatible = true;
          warnings = [ ];
          migrationAvailable = false;
        };
      };

      result =
        compatibility.${dataVersion} or {
          compatible = false;
          warnings = [ "Unsupported configuration version: ${dataVersion}" ];
          migrationAvailable = false;
        };
    in
    result // { currentVersion = currentVersion; };

}

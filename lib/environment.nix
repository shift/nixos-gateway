{ lib }:

let
  validators = import ./validators.nix { inherit lib; };
  validation = import ./validation-enhanced.nix { inherit lib; };

  # Environment type definitions
  environmentTypes = {
    development = {
      description = "Development environment with debug features";
      characteristics = {
        debug = true;
        security = "relaxed";
        performance = "optimized-for-development";
        monitoring = "enhanced";
      };
    };
    staging = {
      description = "Staging environment mirroring production";
      characteristics = {
        debug = false;
        security = "production-like";
        performance = "production-like";
        monitoring = "production-like";
      };
    };
    production = {
      description = "Production environment optimized for performance and security";
      characteristics = {
        debug = false;
        security = "strict";
        performance = "optimized";
        monitoring = "essential";
      };
    };
    testing = {
      description = "Testing environment with isolated services";
      characteristics = {
        debug = true;
        security = "minimal";
        performance = "minimal";
        monitoring = "comprehensive";
      };
    };
  };

  # Validate environment type
  validateEnvironmentType =
    envType:
    let
      validTypes = lib.attrNames environmentTypes;
      isValid = builtins.elem envType validTypes;
    in
    assert lib.assertMsg isValid
      "Invalid environment type: ${envType}. Valid types: ${lib.concatStringsSep ", " validTypes}";
    envType;

  # Validate environment configuration
  validateEnvironmentConfig =
    envConfig:
    let
      hasValidType = envConfig ? environment;
      hasValidOverrides = envConfig ? overrides && builtins.isAttrs envConfig.overrides;
      hasValidMetadata = envConfig ? metadata -> builtins.isAttrs envConfig.metadata;
      _ = if hasValidType then validateEnvironmentType envConfig.environment else null;
    in
    assert lib.assertMsg hasValidType "Environment config must specify a valid 'environment' type";
    assert lib.assertMsg hasValidOverrides "Environment config must have 'overrides' attribute set";
    envConfig;

  # Deep merge two attribute sets with conflict resolution
  deepMergeWithConflictResolution =
    left: right: conflictStrategy:
    let
      mergeAttr =
        name: lValue: rValue:
        if builtins.isAttrs lValue && builtins.isAttrs rValue then
          deepMergeWithConflictResolution lValue rValue conflictStrategy
        else if conflictStrategy == "right-wins" then
          rValue
        else if conflictStrategy == "left-wins" then
          lValue
        else if conflictStrategy == "error" && lValue != rValue then
          throw "Conflict detected for attribute '${name}': left=${builtins.toJSON lValue}, right=${builtins.toJSON rValue}"
        else
          rValue;
    in
    lib.foldlAttrs (
      acc: name: value:
      if acc ? ${name} then
        acc // { ${name} = mergeAttr name acc.${name} value; }
      else
        acc // { ${name} = value; }
    ) left right;

  # Apply environment overrides to base configuration
  applyEnvironmentOverrides =
    baseConfig: environmentConfig: conflictStrategy:
    let
      validatedEnv = validateEnvironmentConfig environmentConfig;
      overrides = validatedEnv.overrides;

      # Apply overrides with conflict resolution
      applyOverrides =
        config: overridePath: overrideValue:
        let
          pathParts = lib.splitString "." overridePath;
          setAttrPath =
            parts: value:
            if parts == [ ] then
              value
            else if builtins.length parts == 1 then
              { ${builtins.head parts} = value; }
            else
              { ${builtins.head parts} = setAttrPath (builtins.tail parts) value; };
        in
        lib.recursiveUpdate config (setAttrPath pathParts overrideValue);

      # Apply all overrides
      finalConfig = lib.foldlAttrs (
        acc: path: value:
        applyOverrides acc path value
      ) baseConfig overrides;
    in
    finalConfig;

  # Environment detection from build context
  detectEnvironment =
    buildEnv: fallbackEnv:
    let
      envFromEnvVar = builtins.getEnv "NIXOS_GATEWAY_ENV";
      envFromBuildAttr = if buildEnv ? environment then buildEnv.environment else null;
      detectedEnv =
        if envFromEnvVar != "" then
          envFromEnvVar
        else if envFromBuildAttr != null then
          envFromBuildAttr
        else
          fallbackEnv;
    in
    validateEnvironmentType detectedEnv;

  # Generate environment-specific defaults
  generateEnvironmentDefaults =
    envType:
    let
      envInfo = environmentTypes.${envType};
      characteristics = envInfo.characteristics;
    in
    {
      # Development environment defaults
      services.gateway = {
        data = {
          firewall = lib.mkIf (characteristics.debug) {
            zones.green.allowedTCPPorts = [
              22
              53
              80
              443
              8080
              3000
              5000
              9090
            ];
            zones.mgmt.allowedTCPPorts = [
              22
              53
              80
              443
              8080
              3000
              5000
              9090
              9142
            ];
          };
          ids = lib.mkIf (characteristics.debug) {
            detectEngine.profile = "low";
            logging.eveLog.types = [
              "alert"
              "http"
              "dns"
              "tls"
              "files"
              "flow"
              "drop"
              "http2"
              "smtp"
            ];
          };
        };
        monitoring = lib.mkIf (characteristics.monitoring == "enhanced") {
          enable = true;
          exporters = {
            node.enable = true;
            systemd.enable = true;
            process.enable = true;
            postgresql.enable = true;
            redis.enable = false;
          };
          grafana = {
            enable = true;
            port = 3000;
          };
        };
      };

      # Production environment defaults
      boot.kernel.sysctl = lib.mkIf (characteristics.performance == "optimized") {
        "net.core.rmem_max" = 134217728;
        "net.core.wmem_max" = 134217728;
        "net.ipv4.tcp_rmem" = "4096 65536 134217728";
        "net.ipv4.tcp_wmem" = "4096 65536 134217728";
      };

      # Security settings based on environment
      security = lib.mkIf (characteristics.security == "strict") {
        sudo.wheelNeedsPassword = false;
        sudo.execWheelOnly = true;
      };
    };

  # Validate override conflicts
  validateOverrideConflicts =
    baseConfig: environmentConfigs:
    let
      envNames = lib.attrNames environmentConfigs;
      findConflicts =
        env1: env2:
        let
          overrides1 = environmentConfigs.${env1}.overrides or { };
          overrides2 = environmentConfigs.${env2}.overrides or { };
          commonPaths = lib.intersectAttrs (lib.mapAttrs (name: value: name) overrides1) overrides2;
          conflictingPaths = lib.filterAttrs (
            name: value: overrides1.${name} != overrides2.${name}
          ) commonPaths;
        in
        conflictingPaths;

      allConflicts = lib.foldlAttrs (
        acc: env1: config1:
        let
          envConflicts = lib.foldlAttrs (
            acc2: env2: config2:
            if env1 != env2 then acc2 // { "${env1}-${env2}" = findConflicts env1 env2; } else acc2
          ) { } environmentConfigs;
        in
        acc // envConflicts
      ) { } environmentConfigs;
    in
    allConflicts;

  # Generate environment comparison report
  generateEnvironmentComparison =
    environmentConfigs:
    let
      envNames = lib.attrNames environmentConfigs;
      compareAttribute =
        attrPath:
        let
          values = lib.mapAttrs (
            name: config: lib.attrByPath (lib.splitString "." attrPath) null config.overrides
          ) environmentConfigs;
          uniqueValues = lib.unique (lib.attrValues values);
        in
        if builtins.length uniqueValues > 1 then values else null;

      # Collect all override paths
      allPaths = lib.foldlAttrs (
        acc: envName: config:
        acc
        ++ lib.collect (x: builtins.isString x && builtins.match ".*\\..*" x != null) (
          lib.attrNames config.overrides
        )
      ) [ ] environmentConfigs;
      uniquePaths = lib.unique allPaths;

      comparisons = lib.filter (x: x != null) (map compareAttribute uniquePaths);
    in
    {
      environments = envNames;
      comparisons = comparisons;
      conflicts = validateOverrideConflicts { } environmentConfigs;
    };

  # Environment-specific configuration loader
  loadEnvironmentConfig =
    envPath:
    let
      envConfig = import envPath { inherit lib; };
      validated = validateEnvironmentConfig envConfig;
    in
    validated;

  # Multi-environment configuration builder
  buildMultiEnvironmentConfig =
    baseConfig: environmentConfigs: targetEnv:
    let
      envConfig = environmentConfigs.${targetEnv} or (throw "Environment '${targetEnv}' not found");
      mergedConfig = applyEnvironmentOverrides baseConfig envConfig "right-wins";
    in
    mergedConfig;

  # Environment switching utilities
  switchEnvironment =
    currentConfig: newEnvConfig: backupPath:
    let
      backup = currentConfig;
      switched = applyEnvironmentOverrides currentConfig newEnvConfig "right-wins";
    in
    {
      config = switched;
      backup = backup;
      backupPath = backupPath;
    };

  # Configuration diff between environments
  diffEnvironments =
    env1Config: env2Config:
    let
      overrides1 = env1Config.overrides or { };
      overrides2 = env2Config.overrides or { };

      added = lib.filterAttrs (name: value: !(overrides1 ? ${name})) overrides2;
      removed = lib.filterAttrs (name: value: !(overrides2 ? ${name})) overrides1;
      modified = lib.filterAttrs (
        name: value:
        overrides1 ? ${name} && overrides2 ? ${name} && overrides1.${name} != overrides2.${name}
      ) overrides1;
    in
    {
      added = added;
      removed = removed;
      modified = modified;
    };

in
{
  # Core environment management
  inherit
    environmentTypes
    validateEnvironmentType
    validateEnvironmentConfig
    detectEnvironment
    ;

  # Override system
  inherit
    applyEnvironmentOverrides
    deepMergeWithConflictResolution
    validateOverrideConflicts
    ;

  # Configuration building
  inherit
    generateEnvironmentDefaults
    buildMultiEnvironmentConfig
    loadEnvironmentConfig
    ;

  # Utilities
  inherit
    generateEnvironmentComparison
    switchEnvironment
    diffEnvironments
    ;

  # Conflict resolution strategies
  conflictStrategies = {
    right-wins = "right-wins";
    left-wins = "left-wins";
    error = "error";
  };

  # Environment validation
  validateEnvironment =
    envConfig: baseConfig:
    let
      validated = validateEnvironmentConfig envConfig;
      merged = applyEnvironmentOverrides baseConfig validated "right-wins";
      validationResult = validation.validateWithDetails validators.validateGatewayData merged;
    in
    {
      environment = validated;
      mergedConfig = merged;
      validation = validationResult;
    };
}

{ lib }:

let
  types = import ./types.nix { inherit lib; };
  validators = import ./validators.nix { inherit lib; };

  # Secret types and validation
  secretTypes = {
    tlsCertificate = {
      description = "TLS certificate file";
      validation = validators.fileExists;
      requiredFields = [
        "certificate"
        "private_key"
      ];
    };

    wireguardKey = {
      description = "WireGuard private key";
      validation = validators.base64Key;
      requiredFields = [ "private_key" ];
    };

    tsigKey = {
      description = "DNS TSIG key";
      validation = validators.base64Key;
      requiredFields = [
        "key"
        "algorithm"
        "name"
      ];
    };

    apiKey = {
      description = "API authentication key";
      validation = validators.nonEmptyString;
      requiredFields = [ "key" ];
    };

    databasePassword = {
      description = "Database connection password";
      validation = validators.nonEmptyString;
      requiredFields = [ "password" ];
    };
  };

  # Secret validation with type checking
  validateSecret =
    secretType: secretData:
    let
      typeConfig = secretTypes.${secretType} or (throw "Unknown secret type: ${secretType}");
      requiredFields = typeConfig.requiredFields or [ ];
      missingFields = builtins.filter (field: !(secretData ? ${field})) requiredFields;
      validationFunc = typeConfig.validation or (x: true);
      validationResult = validationFunc secretData;
    in
    if missingFields != [ ] then
      {
        success = false;
        error = "Missing required fields: ${lib.concatStringsSep ", " missingFields}";
        data = null;
      }
    else if !validationResult then
      {
        success = false;
        error = "Secret validation failed for type: ${secretType}";
        data = null;
      }
    else
      {
        success = true;
        error = null;
        data = secretData;
      };

  # Secret reference resolver
  resolveSecretReference =
    secrets: reference:
    let
      parts = builtins.split "\\." reference;
      path = builtins.filter (x: x != "") parts;
      followPath =
        obj: pathList:
        if pathList == [ ] then
          obj
        else if builtins.isAttrs obj && obj ? ${builtins.head pathList} then
          followPath obj.${builtins.head pathList} (builtins.tail pathList)
        else
          throw "Secret reference not found: ${reference}";
    in
    followPath secrets path;

  # Secret injection into configuration
  injectSecrets =
    config: secrets:
    let
      injectValue =
        value:
        if builtins.isString value && lib.hasPrefix "{{secret:" value && lib.hasSuffix "}}" value then
          let
            secretRef = lib.removePrefix "{{secret:" (lib.removeSuffix "}}" value);
            resolvedSecret = resolveSecretReference secrets secretRef;
          in
          resolvedSecret
        else if builtins.isAttrs value then
          lib.mapAttrs (name: injectValue) value
        else if builtins.isList value then
          map injectValue value
        else
          value;
    in
    injectValue config;

  # Secret rotation support
  rotateSecret =
    secretType: currentSecret: newSecret:
    let
      currentValidation = validateSecret secretType currentSecret;
      newValidation = validateSecret secretType newSecret;
    in
    if !currentValidation.success then
      throw "Current secret validation failed: ${currentValidation.error}"
    else if !newValidation.success then
      throw "New secret validation failed: ${newValidation.error}"
    else
      {
        old = currentValidation.data;
        new = newValidation.data;
        rotationTimestamp = builtins.currentTime;
        type = secretType;
      };

  # Environment-specific secret handling
  getEnvironmentSecrets =
    environment: allSecrets:
    let
      envSecrets = allSecrets.${environment} or { };
      commonSecrets = allSecrets.common or { };
      mergedSecrets = commonSecrets // envSecrets;
    in
    mergedSecrets;

  # Secret health checking
  checkSecretHealth =
    secretType: secretData:
    let
      validation = validateSecret secretType secretData;
      checks = {
        # Check if certificate is expiring soon (for TLS certificates)
        certExpiry =
          if secretType == "tlsCertificate" && secretData ? certificate then
            let
              # This would need OpenSSL integration in a real implementation
              expiryDays = 30; # Placeholder
            in
            if expiryDays < 7 then
              {
                status = "critical";
                message = "Certificate expires in ${toString expiryDays} days";
              }
            else if expiryDays < 30 then
              {
                status = "warning";
                message = "Certificate expires in ${toString expiryDays} days";
              }
            else
              {
                status = "healthy";
                message = "Certificate is valid";
              }
          else
            {
              status = "unknown";
              message = "Cannot check certificate expiry";
            };

        # Check key strength
        keyStrength =
          if secretData ? private_key then
            let
              keyLength = builtins.stringLength secretData.private_key;
            in
            if keyLength < 32 then
              {
                status = "warning";
                message = "Key appears to be weak";
              }
            else
              {
                status = "healthy";
                message = "Key strength appears adequate";
              }
          else
            {
              status = "unknown";
              message = "No key to check";
            };
      };
    in
    {
      validation = validation;
      health = checks;
      overall = if validation.success then "healthy" else "unhealthy";
    };

  # Secret backup and recovery
  backupSecret =
    secretType: secretData: backupPath:
    let
      validation = validateSecret secretType secretData;
      backupFile = "${backupPath}/${secretType}-${builtins.currentTime}.json";
    in
    if validation.success then
      {
        success = true;
        backupFile = backupFile;
        data = validation.data;
        timestamp = builtins.currentTime;
      }
    else
      {
        success = false;
        error = validation.error;
      };

  # Secret access control
  checkSecretAccess =
    secretType: user: permissions:
    let
      userPerms = permissions.${user} or { };
      typePerms = userPerms.${secretType} or [ ];
      hasRead = builtins.elem "read" typePerms;
      hasWrite = builtins.elem "write" typePerms;
      hasDelete = builtins.elem "delete" typePerms;
    in
    {
      read = hasRead;
      write = hasWrite;
      delete = hasDelete;
      allowed = typePerms != [ ];
    };

  # Secret audit logging
  auditSecretAccess = secretType: user: action: result: {
    timestamp = builtins.currentTime;
    secretType = secretType;
    user = user;
    action = action; # read, write, delete, rotate
    result = result; # success, failure
    details = {
      # Additional context would be added here
    };
  };

  # Secret dependency management
  resolveSecretDependencies =
    secrets:
    let
      findDependencies =
        secretPath: secretData:
        if builtins.isAttrs secretData then
          builtins.listToAttrs (
            builtins.map (
              attrName:
              let
                value = secretData.${attrName};
                childPath = "${secretPath}.${attrName}";
              in
              if builtins.isString value && lib.hasPrefix "{{secret:" value then
                {
                  name = childPath;
                  value = lib.removePrefix "{{secret:" (lib.removeSuffix "}}" value);
                }
              else if builtins.isAttrs value then
                findDependencies childPath value
              else
                {
                  name = childPath;
                  value = null;
                }
            ) (builtins.attrNames secretData)
          )
        else
          { };

      allDependencies = builtins.foldl' (
        acc: secretName: acc // findDependencies secretName secrets.${secretName}
      ) { } (builtins.attrNames secrets);
    in
    allDependencies;

  # Secret configuration generation
  generateSecretConfig =
    secrets: environment:
    let
      envSecrets = getEnvironmentSecrets environment secrets;
      dependencies = resolveSecretDependencies envSecrets;
      sortedSecrets = lib.toposort dependencies (builtins.attrNames envSecrets);
    in
    if sortedSecrets ? cycle then
      throw "Circular dependency detected in secrets: ${builtins.concatStringsSep ", " sortedSecrets.cycle}"
    else
      {
        secrets = envSecrets;
        order = sortedSecrets.result;
        dependencies = dependencies;
      };

  # Integration with sops-nix
  sopsIntegration = {
    # Generate sops configuration from secrets
    generateSopsConfig =
      secrets:
      let
        sopsSecrets = builtins.mapAttrs (
          name: value: if builtins.isAttrs value && value ? sops then value.sops else { format = "yaml"; }
        ) secrets;
      in
      sopsSecrets;

    # Validate sops secrets structure
    validateSopsSecrets =
      secrets:
      let
        validateSecret =
          name: value:
          if !(value ? sops) then
            {
              valid = true;
              warnings = [ ];
            }
          else
            let
              sopsConfig = value.sops;
              requiredSopsFields = [ "format" ];
              missingFields = builtins.filter (field: !(sopsConfig ? ${field})) requiredSopsFields;
            in
            if missingFields != [ ] then
              {
                valid = false;
                error = "Missing sops fields: ${lib.concatStringsSep ", " missingFields}";
              }
            else
              {
                valid = true;
                warnings = [ ];
              };
      in
      builtins.mapAttrs validateSecret secrets;
  };

  # Integration with agenix
  agenixIntegration = {
    # Generate agenix configuration from secrets
    generateAgenixConfig =
      secrets:
      let
        agenixSecrets = lib.filterAttrs (name: value: builtins.isAttrs value && value ? agenix) secrets;
      in
      agenixSecrets;

    # Validate agenix secrets structure
    validateAgenixSecrets =
      secrets:
      let
        validateSecret =
          name: value:
          if !(value ? agenix) then
            {
              valid = true;
              warnings = [ ];
            }
          else
            let
              agenixConfig = value.agenix;
              requiredAgenixFields = [ "file" ];
              missingFields = builtins.filter (field: !(agenixConfig ? ${field})) requiredAgenixFields;
            in
            if missingFields != [ ] then
              {
                valid = false;
                error = "Missing agenix fields: ${lib.concatStringsSep ", " missingFields}";
              }
            else
              {
                valid = true;
                warnings = [ ];
              };
      in
      builtins.mapAttrs validateSecret secrets;
  };

in
{
  inherit
    secretTypes
    validateSecret
    resolveSecretReference
    injectSecrets
    rotateSecret
    getEnvironmentSecrets
    checkSecretHealth
    backupSecret
    checkSecretAccess
    auditSecretAccess
    resolveSecretDependencies
    generateSecretConfig
    sopsIntegration
    agenixIntegration
    ;
}

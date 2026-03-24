{ lib }:

let
  validators = import ./validators.nix { inherit lib; };
  validation = import ./validation-enhanced.nix { inherit lib; };

  # Template parameter type validators
  validateParameterType =
    paramType: value:
    let
      isValid =
        if paramType.type == "string" then
          builtins.isString value
        else if paramType.type == "int" then
          builtins.isInt value
        else if paramType.type == "bool" then
          builtins.isBool value
        else if paramType.type == "array" then
          builtins.isList value
        else if paramType.type == "object" then
          builtins.isAttrs value
        else if paramType.type == "cidr" then
          (builtins.tryEval (validators.validateCIDR value)).success
        else if paramType.type == "ip" then
          (builtins.tryEval (validators.validateIPAddress value)).success
        else if paramType.type == "mac" then
          (builtins.tryEval (validators.validateMACAddress value)).success
        else if paramType.type == "port" then
          (builtins.tryEval (validators.validatePort value)).success
        else
          false;
    in
    assert lib.assertMsg isValid
      "Invalid parameter type: expected ${paramType.type}, got ${builtins.typeOf value}";
    value;

  # Validate template parameters against their definitions
  validateTemplateParameters =
    template: parameters:
    let
      requiredParams = lib.filterAttrs (name: param: param.required or false) template.parameters;
      missingParams = lib.attrNames (
        lib.filterAttrs (name: param: !(parameters ? ${name})) requiredParams
      );

      validateParam =
        name: param:
        if parameters ? ${name} then
          validateParameterType param parameters.${name}
        else if param ? default then
          param.default
        else
          throw "Required parameter '${name}' not provided for template '${template.name}'";

      validatedParams = lib.mapAttrs validateParam template.parameters;
    in
    assert lib.assertMsg (
      missingParams == [ ]
    ) "Missing required parameters: ${lib.concatStringsSep ", " missingParams}";
    validatedParams;

  # Template inheritance resolver
  resolveTemplateInheritance =
    templates: templateName: visited:
    let
      template = templates.${templateName} or (throw "Template '${templateName}' not found");
      visited' = visited ++ [ templateName ];

      # Check for circular inheritance
      hasCycle = builtins.any (t: t == templateName) visited;
    in
    assert lib.assertMsg (
      !hasCycle
    ) "Circular template inheritance detected: ${lib.concatStringsSep " -> " visited'}";

    if template ? inherits then
      let
        parentTemplate = resolveTemplateInheritance templates template.inherits visited';
        # Merge parameters and config
        mergedTemplate = {
          name = template.name;
          description = template.description;
          parameters = parentTemplate.parameters // template.parameters;
          config = template.config;
          inherits = template.inherits;
        };
      in
      mergedTemplate
    else
      template;

  # Template composition - merge multiple templates
  composeTemplates =
    templates: templateNames:
    let
      resolvedTemplates = map (name: resolveTemplateInheritance templates name [ ]) templateNames;

      # Merge all parameters (later templates override earlier ones)
      mergedParameters = lib.foldl (acc: tmpl: acc // tmpl.parameters) { } resolvedTemplates;

      # Compose config functions
      composedConfig =
        parameters:
        let
          # Apply each template's config in order
          applyConfigs =
            templates: params:
            if templates == [ ] then
              { }
            else
              let
                head = builtins.head templates;
                tail = builtins.tail templates;
                headConfig = head.config params;
                tailConfig = applyConfigs tail params;
              in
              lib.recursiveUpdate tailConfig headConfig;
        in
        applyConfigs resolvedTemplates parameters;
    in
    {
      name = "Composed: ${lib.concatStringsSep " + " templateNames}";
      description = "Composed template from ${lib.concatStringsSep ", " templateNames}";
      parameters = mergedParameters;
      config = composedConfig;
    };

  # Instantiate a template with parameters
  instantiateTemplate =
    template: parameters:
    let
      validatedParams = validateTemplateParameters template parameters;
      configFunction = template.config;
    in
    configFunction validatedParams;

  # Load and validate a single template
  loadTemplate =
    templatePath:
    let
      template = import templatePath { inherit lib; };
      requiredFields = [
        "name"
        "description"
        "parameters"
        "config"
      ];
      missingFields = lib.filter (field: !(template ? ${field})) requiredFields;
    in
    assert lib.assertMsg (
      missingFields == [ ]
    ) "Template missing required fields: ${lib.concatStringsSep ", " missingFields}";
    assert lib.assertMsg (builtins.isFunction template.config) "Template config must be a function";
    template;

  # Load all templates from a directory
  loadTemplates =
    templatesDir:
    let
      templateFiles = builtins.attrNames (builtins.readDir templatesDir);
      nixFiles = lib.filter (file: lib.hasSuffix ".nix" file) templateFiles;
      makeTemplateEntry =
        file:
        let
          name = lib.removeSuffix ".nix" file;
          path = templatesDir + "/${file}";
          template = import path { inherit lib; };
        in
        {
          inherit name template;
        };
      templateEntries = map makeTemplateEntry nixFiles;
    in
    builtins.listToAttrs (
      map (entry: {
        name = entry.name;
        value = entry.template;
      }) templateEntries
    );

  # Instantiate template by name with inheritance support
  instantiateTemplateByName =
    templates: templateName: parameters:
    let
      resolvedTemplate = resolveTemplateInheritance templates templateName [ ];
    in
    instantiateTemplate resolvedTemplate parameters;

  # Compose and instantiate multiple templates
  instantiateComposedTemplate =
    templates: templateNames: parameters:
    let
      composedTemplate = composeTemplates templates templateNames;
    in
    instantiateTemplate composedTemplate parameters;

  # Validate template definition
  validateTemplate =
    template:
    let
      validateParam =
        name: param:
        let
          hasValidType = param ? type && builtins.isString param.type;
          hasValidDefault = param ? default -> true; # Could add more validation here
          hasValidDescription = param ? description -> builtins.isString param.description;
        in
        assert lib.assertMsg hasValidType "Parameter '${name}' must have a 'type' field";
        assert lib.assertMsg hasValidDefault "Parameter '${name}' has invalid default value";
        assert lib.assertMsg hasValidDescription "Parameter '${name}' description must be a string";
        param;

      validatedParams = lib.mapAttrs validateParam template.parameters;
    in
    template // { parameters = validatedParams; };

  # Generate template documentation
  generateTemplateDocs =
    template:
    let
      paramDocs = lib.mapAttrs (
        name: param:
        let
          requiredStr = if param.required or false then " (required)" else " (optional)";
          defaultStr = if param ? default then " = ${builtins.toJSON param.default}" else "";
          descriptionStr = if param ? description then "\n    ${param.description}" else "";
        in
        "  ${name}: ${param.type}${requiredStr}${defaultStr}${descriptionStr}"
      ) template.parameters;
    in
    ''
      # ${template.name}

      ${template.description}

      ## Parameters
      ${lib.concatStringsSep "\n" (lib.attrValues paramDocs)}

    '';

  # List all available templates
  listTemplates =
    templates:
    lib.mapAttrs (name: template: {
      inherit (template) name description;
      parameters = lib.attrNames template.parameters;
      requiredParams = lib.attrNames (lib.filterAttrs (n: p: p.required or false) template.parameters);
      optionalParams = lib.attrNames (lib.filterAttrs (n: p: !(p.required or false)) template.parameters);
      inherits = template.inherits or null;
    }) templates;

  # Template dependency analysis
  analyzeDependencies =
    templates:
    let
      getDeps =
        name:
        let
          template = templates.${name};
        in
        if template ? inherits then [ template.inherits ] ++ getDeps template.inherits else [ ];

      allDeps = lib.mapAttrs (name: template: {
        direct = template.inherits or null;
        all = getDeps name;
      }) templates;
    in
    allDeps;

  # Template validation against gateway data schema
  validateTemplateOutput =
    templateOutput:
    let
      validationResult = validation.validateWithDetails validators.validateGatewayData templateOutput;
    in
    validationResult;

in
{
  # Export all functions
  inherit
    loadTemplate
    loadTemplates
    instantiateTemplate
    instantiateTemplateByName
    instantiateComposedTemplate
    validateTemplate
    generateTemplateDocs
    listTemplates
    analyzeDependencies
    validateTemplateOutput
    resolveTemplateInheritance
    composeTemplates
    validateTemplateParameters
    ;
}

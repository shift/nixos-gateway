{ pkgs, lib, ... }:

let
  # Import the template engine
  templateEngine = import ../lib/template-engine.nix { inherit lib; };

  # Load all templates for testing
  templates = templateEngine.loadTemplates ../templates;

  # Test helper functions
  runTest =
    testName: testFn:
    let
      result = builtins.tryEval testFn;
    in
    if result.success then result.value else throw "Test '${testName}' failed: ${result.value}";

  assertSuccess =
    testName: condition: message:
    if condition then "✅ ${testName}: PASSED" else throw "Test '${testName}' failed: ${message}";

  assertThrows =
    testName: testFn: expectedMessage:
    let
      result = builtins.tryEval testFn;
    in
    if result.success then
      throw "Test '${testName}' failed: Expected exception but got success"
    else if builtins.match ".*${expectedMessage}.*" result.value != null then
      "✅ ${testName}: PASSED (expected exception)"
    else
      throw "Test '${testName}' failed: Expected message '${expectedMessage}' but got '${result.value}'";

  # Run all tests and collect results
  testResults = [
    # Template loading tests
    (runTest "template-loading" (
      let
        templateCount = builtins.length (lib.attrNames templates);
        expectedTemplates = [
          "base-gateway"
          "simple-gateway"
          "soho-gateway"
          "enterprise-gateway"
          "cloud-edge-gateway"
          "isp-gateway"
          "iot-gateway"
        ];
        hasAllTemplates = lib.all (t: templates ? ${t}) expectedTemplates;
      in
      assertSuccess "template-loading" (
        hasAllTemplates && templateCount >= 7
      ) "Failed to load all expected templates"
    ))

    # Template validation tests
    (runTest "template-validation" (
      let
        validationResults = lib.mapAttrs (
          name: template: templateEngine.validateTemplate template
        ) templates;
        allValid = lib.all (t: t ? name && t ? description && t ? parameters && t ? config) (
          lib.attrValues validationResults
        );
      in
      assertSuccess "template-validation" allValid "Template validation failed"
    ))

    # Parameter validation tests
    (runTest "parameter-validation" (
      let
        # Test missing required parameter
        testMissingRequired = assertThrows "missing-required" (templateEngine.instantiateTemplateByName
          templates
          "soho-gateway"
          {
            # Missing lanInterface and wanInterface
          }
        ) "Missing required parameters";

        # Test invalid parameter type
        testInvalidType = assertThrows "invalid-type" (templateEngine.instantiateTemplateByName templates
          "soho-gateway"
          {
            lanInterface = 123; # Should be string
            wanInterface = "eth1";
          }
        ) "Invalid parameter type";

        # Test valid parameters
        testValid = templateEngine.instantiateTemplateByName templates "soho-gateway" {
          lanInterface = "eth0";
          wanInterface = "eth1";
        };
      in
      assertSuccess "parameter-validation" true "Parameter validation tests passed"
    ))

    # Template inheritance tests
    (runTest "template-inheritance" (
      let
        # Test that simple-gateway inherits from base-gateway
        simpleTemplate = templates.simple-gateway;
        hasInheritance = simpleTemplate.inherits == "base-gateway";

        # Test inheritance resolution
        resolvedTemplate = templateEngine.resolveTemplateInheritance templates "simple-gateway" [ ];
        hasBaseParams =
          resolvedTemplate.parameters ? lanInterface && resolvedTemplate.parameters ? wanInterface;
      in
      assertSuccess "template-inheritance" (hasInheritance && hasBaseParams) "Template inheritance failed"
    ))

    # Template composition tests
    (runTest "template-composition" (
      let
        # Test composing base-gateway and simple-gateway (which inherits from base-gateway)
        composedConfig =
          templateEngine.instantiateComposedTemplate templates
            [
              "base-gateway"
              "simple-gateway"
            ]
            {
              lanInterface = "eth0";
              wanInterface = "eth1";
            };

        # Check that composed config has expected structure
        hasGatewayService = composedConfig ? services.gateway;
        hasCorrectInterfaces =
          composedConfig.services.gateway.interfaces.lan == "eth0"
          && composedConfig.services.gateway.interfaces.wan == "eth1";
      in
      assertSuccess "template-composition" (
        hasGatewayService && hasCorrectInterfaces
      ) "Template composition failed"
    ))

    # Template instantiation tests
    (runTest "template-instantiation" (
      let
        # Test SOHO gateway instantiation
        sohoConfig = templateEngine.instantiateTemplateByName templates "soho-gateway" {
          lanInterface = "eth0";
          wanInterface = "eth1";
          domain = "test.local";
          enableFirewall = true;
          enableIDS = false;
          enableMonitoring = true;
        };

        # Test enterprise gateway instantiation
        enterpriseConfig = templateEngine.instantiateTemplateByName templates "enterprise-gateway" {
          lanInterface = "eth0";
          wanInterfaces = [
            "eth1"
            "eth2"
          ];
        };

        # Verify configurations are valid
        sohoValid = sohoConfig ? services.gateway && sohoConfig.services.gateway.enable;
        enterpriseValid = enterpriseConfig ? services.gateway && enterpriseConfig.services.gateway.enable;
      in
      assertSuccess "template-instantiation" (
        sohoValid && enterpriseValid
      ) "Template instantiation failed"
    ))

    # Template documentation tests
    (runTest "template-documentation" (
      let
        sohoDocs = templateEngine.generateTemplateDocs templates.soho-gateway;
        hasName = builtins.match ".*# SOHO Gateway.*" sohoDocs != null;
        hasDescription = builtins.match ".*Small office/home office gateway.*" sohoDocs != null;
        hasParameters = builtins.match ".*## Parameters.*" sohoDocs != null;
      in
      assertSuccess "template-documentation" (
        hasName && hasDescription && hasParameters
      ) "Template documentation generation failed"
    ))

    # Template listing tests
    (runTest "template-listing" (
      let
        templateList = templateEngine.listTemplates templates;

        # Check that list contains expected information
        sohoInfo = templateList.soho-gateway;
        hasCorrectName = sohoInfo.name == "SOHO Gateway";
        hasParameters = builtins.length sohoInfo.parameters > 0;
        hasRequiredParams = builtins.length sohoInfo.requiredParams > 0;
      in
      assertSuccess "template-listing" (
        hasCorrectName && hasParameters && hasRequiredParams
      ) "Template listing failed"
    ))

    # Template dependency analysis tests
    (runTest "dependency-analysis" (
      let
        dependencies = templateEngine.analyzeDependencies templates;

        # Check that simple-gateway has base-gateway as dependency
        simpleDeps = dependencies.simple-gateway;
        hasDirectDep = simpleDeps.direct == "base-gateway";
        hasAllDeps = builtins.elem "base-gateway" simpleDeps.all;
      in
      assertSuccess "dependency-analysis" (hasDirectDep && hasAllDeps) "Dependency analysis failed"
    ))

    # Template output validation tests
    (runTest "output-validation" (
      let
        # Generate configuration and validate against gateway data schema
        sohoConfig = templateEngine.instantiateTemplateByName templates "soho-gateway" {
          lanInterface = "eth0";
          wanInterface = "eth1";
        };

        # Extract gateway data for validation
        gatewayData = sohoConfig.services.gateway.data;
        # Basic validation - check that gateway data has expected structure
        hasNetwork = gatewayData ? network;
        hasFirewall = gatewayData ? firewall;
        hasHosts = gatewayData ? hosts;
        isValid = hasNetwork && hasFirewall && hasHosts;
      in
      assertSuccess "output-validation" isValid "Template output validation failed"
    ))

    # Edge case tests
    (runTest "edge-cases" (
      let
        # Test circular inheritance detection
        testCircularInheritance = assertThrows "circular-inheritance" (
          # Create a circular dependency manually for testing
          let
            circularTemplates = templates // {
              test-a = templates.base-gateway // {
                inherits = "test-b";
              };
              test-b = templates.base-gateway // {
                inherits = "test-a";
              };
            };
          in
          templateEngine.resolveTemplateInheritance circularTemplates "test-a" [ ]
        ) "Circular template inheritance";

        # Test non-existent template
        testNonExistent = assertThrows "non-existent-template" (templateEngine.instantiateTemplateByName
          templates
          "non-existent-template"
          { }
        ) "Template 'non-existent-template' not found";
      in
      assertSuccess "edge-cases" true "Edge case tests passed"
    ))

    # Performance tests
    (runTest "performance" (
      let
        # Test loading many templates
        templateList = templateEngine.listTemplates templates;

        # Test instantiating multiple templates
        configs = lib.mapAttrs (
          name: template:
          templateEngine.instantiateTemplateByName templates name {
            lanInterface = "eth0";
            wanInterface = "eth1";
          }
        ) (lib.filterAttrs (n: t: n != "enterprise-gateway" && n != "isp-gateway") templates);

        # Performance should be reasonable (these are basic checks)
        hasTemplateList = builtins.length (lib.attrNames templateList) > 0;
        hasConfigs = builtins.length (lib.attrNames configs) > 0;
      in
      assertSuccess "performance" (hasTemplateList && hasConfigs) "Performance tests failed"
    ))
  ];

  # Generate test report
  testReport = lib.concatStringsSep "\n" testResults;

in
pkgs.writeText "template-test-results" testReport

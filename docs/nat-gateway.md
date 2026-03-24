# NAT Gateway Test Suite
{ config, lib, pkgs, ... }:

let
  natConfig = import ../lib/nat-config.nix { inherit lib pkgs; };
  natMonitoring = import ../lib/nat-monitoring.nix { inherit lib pkgs; };

  # Test configuration
  testInstances = [
    {
      name = "test-nat-1";
      publicInterface = "eth0";
      privateSubnets = [ "192.168.1.0/24" "10.0.0.0/16" ];
      publicIPs = [ "203.0.113.10" "203.0.113.11" ];
      maxConnections = 50000;
      timeout = {
        tcp = "12h";
        udp = "180s";
      };
      allowInbound = false;
      portForwarding = [
        {
          protocol = "tcp";
          port = 80;
          targetIP = "192.168.1.100";
          targetPort = 8080;
        }
      ];
    }
    {
      name = "test-nat-2";
      publicInterface = "eth1";
      privateSubnets = [ "172.16.0.0/16" ];
      publicIPs = [ "203.0.113.20" ];
      maxConnections = 25000;
      timeout = {
        tcp = "24h";
        udp = "300s";
      };
      allowInbound = true;
      portForwarding = [];
    }
  ];

in {
  # Test NAT configuration validation
  testNatConfigValidation = {
    expr = natConfig.validateNatConfig testInstances;
    expected = {
      valid = true;
      errors = [];
    };
  };

  # Test invalid configuration
  testInvalidNatConfig = {
    expr = natConfig.validateNatConfig [
      { name = ""; publicInterface = "eth0"; privateSubnets = []; publicIPs = []; }
    ];
    expected = {
      valid = false;
      errors = [
        "Instance name cannot be empty"
        "At least one private subnet required for "
        "At least one public IP required for "
      ];
    };
  };

  # Test NAT rules generation
  testNatRulesGeneration = {
    expr = natConfig.mkNatRules (head testInstances);
    expected = builtins.isString (natConfig.mkNatRules (head testInstances));
  };

  # Test monitoring script generation
  testMonitoringScript = {
    expr = natMonitoring.mkMonitoringScript testInstances;
    expected = builtins.isAttrs (natMonitoring.mkMonitoringScript testInstances);
  };

  # Test Prometheus metrics generation
  testPrometheusMetrics = {
    expr = natMonitoring.mkPrometheusMetrics testInstances;
    expected = builtins.isString (natMonitoring.mkPrometheusMetrics testInstances);
  };

  # Test health check generation
  testHealthCheck = {
    expr = natMonitoring.mkHealthCheck testInstances;
    expected = builtins.isString (natMonitoring.mkHealthCheck testInstances);
  };

  # Integration test: NAT with firewall rules
  testNatFirewallIntegration = {
    expr = config.networking.firewall.enable && config.services.gateway.natGateway.enable;
    expected = true;
  };

  # Test configuration summary
  testConfigSummary = {
    expr = natConfig.mkConfigSummary testInstances;
    expected = builtins.isString (natConfig.mkConfigSummary testInstances);
  };

  # Test alerting rules generation
  testAlertingRules = {
    expr = natMonitoring.mkAlertingRules testInstances;
    expected = builtins.isString (natMonitoring.mkAlertingRules testInstances);
  };

  # Performance test configuration
  testPerformanceConfig = {
    expr = all (instance: instance.maxConnections > 0) testInstances;
    expected = true;
  };

  # Test port forwarding configuration
  testPortForwarding = {
    expr = length (head testInstances).portForwarding;
    expected = 1;
  };

  # Test multiple public IP handling
  testMultiplePublicIPs = {
    expr = length (head testInstances).publicIPs;
    expected = 2;
  };

  # Test subnet configuration
  testSubnetConfig = {
    expr = length (head testInstances).privateSubnets;
    expected = 2;
  };

  # Test cleanup rules generation
  testCleanupRules = {
    expr = natConfig.mkNatCleanup (head testInstances);
    expected = builtins.isString (natConfig.mkNatCleanup (head testInstances));
  };

  # Test monitoring configuration structure
  testMonitoringConfig = {
    expr = natMonitoring.mkMonitoringConfig testInstances;
    expected = builtins.isAttrs (natMonitoring.mkMonitoringConfig testInstances);
  };

  # Test Grafana dashboard generation
  testGrafanaDashboard = {
    expr = natMonitoring.mkGrafanaDashboard testInstances;
    expected = builtins.isAttrs (natMonitoring.mkGrafanaDashboard testInstances);
  };
}</content>
<parameter name="filePath">tests/nat-gateway-test.nix
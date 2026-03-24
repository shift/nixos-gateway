{ lib }:

let
  # Import the template engine
  templateEngine = import ../../lib/template-engine.nix { inherit lib; };

  # Load all available templates
  templates = templateEngine.loadTemplates ../../templates;

in
{
  # SOHO Gateway Example
  soho-gateway = templateEngine.instantiateTemplateByName templates "soho-gateway" {
    lanInterface = "eth0";
    wanInterface = "eth1";
    domain = "home.local";
    lanNetwork = "192.168.1.0/24";
    lanGateway = "192.168.1.1";
    dhcpRangeStart = "192.168.1.100";
    dhcpRangeEnd = "192.168.1.200";
    enableFirewall = true;
    enableIDS = false;
    enableMonitoring = true;
  };

  # Enterprise Gateway Example
  enterprise-gateway = templateEngine.instantiateTemplateByName templates "enterprise-gateway" {
    lanInterface = "eth0";
    wanInterfaces = [
      "eth1"
      "eth2"
    ];
    domain = "corp.local";
    lanNetwork = "10.0.0.0/16";
    lanGateway = "10.0.0.1";
    dmzNetwork = "10.0.1.0/24";
    dmzGateway = "10.0.1.1";
    vpnNetwork = "10.0.2.0/24";
    enableVPN = true;
    enableIDS = true;
    enableMonitoring = true;
    enableQoS = true;
    idsProfile = "high";
  };

  # Cloud Edge Gateway Example
  cloud-edge-gateway = templateEngine.instantiateTemplateByName templates "cloud-edge-gateway" {
    lanInterface = "eth0";
    wanInterface = "eth1";
    domain = "edge.local";
    lanNetwork = "172.16.0.0/16";
    lanGateway = "172.16.0.1";
    containerNetwork = "172.17.0.0/16";
    cloudProvider = "aws";
    enableContainers = true;
    enableCloudVPN = true;
    enableMonitoring = true;
    cloudRegion = "us-east-1";
  };

  # ISP Gateway Example
  isp-gateway = templateEngine.instantiateTemplateByName templates "isp-gateway" {
    lanInterface = "eth0";
    wanInterfaces = [
      "eth1"
      "eth2"
    ];
    asn = 65001;
    bgpNeighbors = [
      {
        ip = "203.0.113.1";
        asn = 64496;
        description = "Upstream Provider 1";
      }
      {
        ip = "203.0.113.2";
        asn = 64497;
        description = "Upstream Provider 2";
      }
    ];
    domain = "isp.local";
    customerNetworks = [
      "192.168.0.0/16"
      "10.0.0.0/8"
    ];
    enableQoS = true;
    enableBGP = true;
    enableMonitoring = true;
    maxBandwidth = 1000;
  };

  # IoT Gateway Example
  iot-gateway = templateEngine.instantiateTemplateByName templates "iot-gateway" {
    lanInterface = "eth0";
    iotInterface = "eth1";
    wanInterface = "eth2";
    domain = "iot.local";
    iotNetwork = "192.168.100.0/24";
    iotGateway = "192.168.100.1";
    managementNetwork = "192.168.1.0/24";
    managementGateway = "192.168.1.1";
    enableMQTT = true;
    enableCoAP = true;
    enableModbus = false;
    enableEdgeProcessing = true;
    deviceTypes = [
      "sensor"
      "actuator"
      "camera"
      "controller"
    ];
  };

  # Template Inheritance Example
  simple-gateway = templateEngine.instantiateTemplateByName templates "simple-gateway" {
    lanInterface = "eth0";
    wanInterface = "eth1";
    domain = "simple.local";
    lanNetwork = "192.168.1.0/24";
    lanGateway = "192.168.1.1";
    dhcpRangeStart = "192.168.1.100";
    dhcpRangeEnd = "192.168.1.200";
    enableLogging = true;
    enableMonitoring = false;
    logLevel = "info";
  };

  # Template Composition Example
  composed-gateway =
    templateEngine.instantiateComposedTemplate templates
      [
        "base-gateway"
        "soho-gateway"
      ]
      {
        lanInterface = "eth0";
        wanInterface = "eth1";
        domain = "composed.local";
        lanNetwork = "192.168.1.0/24";
        lanGateway = "192.168.1.1";
        dhcpRangeStart = "192.168.1.100";
        dhcpRangeEnd = "192.168.1.200";
        enableFirewall = true;
        enableIDS = false;
        enableMonitoring = true;
        enableLogging = true;
        logLevel = "info";
      };
}

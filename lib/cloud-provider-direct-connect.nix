{ lib }:

let
  # Cloud provider configurations for Direct Connect
  providerConfigs = {
    aws = {
      asn = 7224; # AWS Direct Connect ASN
      locations = {
        "us-east-1" = {
          facilities = [
            "Equinix DC2"
            "Equinix DC3"
            "CoreSite VA1"
          ];
          metro = "Washington DC";
        };
        "us-west-2" = {
          facilities = [
            "Equinix SE2"
            "CoreSite LA1"
          ];
          metro = "Los Angeles";
        };
        "eu-west-1" = {
          facilities = [
            "Equinix LD5"
            "Telehouse North"
          ];
          metro = "London";
        };
      };
      bandwidths = [
        "50Mbps"
        "100Mbps"
        "200Mbps"
        "300Mbps"
        "400Mbps"
        "500Mbps"
        "1Gbps"
        "2Gbps"
        "5Gbps"
        "10Gbps"
        "100Gbps"
      ];
      connectionTypes = [
        "dedicated"
        "hosted"
      ];
      defaultRouterId = "169.254.0.1";
      ipRanges = {
        ipv4 = "169.254.0.0/16";
        ipv6 = "2001:db8::/32";
      };
      capabilities = {
        multipath = true;
        extendedNexthop = true;
        largeCommunities = true;
        flowspec = false;
      };
    };

    azure = {
      asn = 12076; # Azure ASN
      locations = {
        "East US" = {
          facilities = [
            "Equinix DC2"
            "CoreSite VA1"
          ];
          metro = "Washington DC";
        };
        "West Europe" = {
          facilities = [
            "Equinix AM1"
            "Interxion AMS1"
          ];
          metro = "Amsterdam";
        };
      };
      bandwidths = [
        "50Mbps"
        "100Mbps"
        "200Mbps"
        "500Mbps"
        "1Gbps"
        "2Gbps"
        "5Gbps"
        "10Gbps"
      ];
      connectionTypes = [ "ExpressRoute" ];
      defaultRouterId = "169.254.1.1";
      ipRanges = {
        ipv4 = "169.254.1.0/24";
        ipv6 = "2001:db8:1::/48";
      };
      capabilities = {
        multipath = true;
        extendedNexthop = true;
        largeCommunities = false;
        flowspec = false;
      };
    };

    gcp = {
      asn = 15169; # Google ASN
      locations = {
        "us-central1" = {
          facilities = [
            "Equinix CH1"
            "CoreSite LA1"
          ];
          metro = "Chicago";
        };
        "europe-west1" = {
          facilities = [
            "Equinix LD5"
            "Interxion FRA1"
          ];
          metro = "London";
        };
      };
      bandwidths = [
        "50Mbps"
        "100Mbps"
        "200Mbps"
        "300Mbps"
        "400Mbps"
        "500Mbps"
        "1Gbps"
        "2Gbps"
        "5Gbps"
        "10Gbps"
      ];
      connectionTypes = [
        "Dedicated Interconnect"
        "Partner Interconnect"
      ];
      defaultRouterId = "169.254.2.1";
      ipRanges = {
        ipv4 = "169.254.2.0/24";
        ipv6 = "2001:db8:2::/48";
      };
      capabilities = {
        multipath = true;
        extendedNexthop = true;
        largeCommunities = false;
        flowspec = true;
      };
    };

    oracle = {
      asn = 31898; # Oracle ASN
      locations = {
        "us-ashburn-1" = {
          facilities = [
            "Equinix DC2"
            "CoreSite VA1"
          ];
          metro = "Ashburn";
        };
        "eu-amsterdam-1" = {
          facilities = [ "Equinix AM1" ];
          metro = "Amsterdam";
        };
      };
      bandwidths = [
        "1Gbps"
        "2Gbps"
        "5Gbps"
        "10Gbps"
      ];
      connectionTypes = [ "FastConnect" ];
      defaultRouterId = "169.254.3.1";
      ipRanges = {
        ipv4 = "169.254.3.0/24";
        ipv6 = "2001:db8:3::/48";
      };
      capabilities = {
        multipath = false;
        extendedNexthop = true;
        largeCommunities = false;
        flowspec = false;
      };
    };

    ibm = {
      asn = 36351; # IBM Cloud ASN
      locations = {
        "us-south" = {
          facilities = [ "Equinix DC2" ];
          metro = "Dallas";
        };
        "eu-gb" = {
          facilities = [ "Equinix LD5" ];
          metro = "London";
        };
      };
      bandwidths = [
        "50Mbps"
        "100Mbps"
        "200Mbps"
        "500Mbps"
        "1Gbps"
        "2Gbps"
        "5Gbps"
      ];
      connectionTypes = [ "Direct Link" ];
      defaultRouterId = "169.254.4.1";
      ipRanges = {
        ipv4 = "169.254.4.0/24";
        ipv6 = "2001:db8:4::/48";
      };
      capabilities = {
        multipath = true;
        extendedNexthop = true;
        largeCommunities = false;
        flowspec = false;
      };
    };
  };

  # Get provider configuration
  getProviderConfig =
    provider: providerConfigs.${provider} or (throw "Unsupported Direct Connect provider: ${provider}");

  # Generate provider-specific BGP configuration
  generateProviderSpecificBGP =
    name: connection:
    let
      provider = connection.provider;
      providerCfg = getProviderConfig provider;
      bgp = connection.bgp;

      # Provider-specific BGP features
      multipathConfig = lib.optionalString providerCfg.capabilities.multipath ''
        bgp bestpath as-path multipath-relax
        maximum-paths 8
        maximum-paths ibgp 8
      '';

      extendedNexthopConfig = lib.optionalString providerCfg.capabilities.extendedNexthop ''
        neighbor * capability extended-nexthop
      '';

      largeCommunitiesConfig = lib.optionalString providerCfg.capabilities.largeCommunities ''
        bgp large-community receive
        bgp large-community send
      '';

      flowspecConfig = lib.optionalString providerCfg.capabilities.flowspec ''
        bgp flowspec
      '';

      # Provider-specific route policies
      providerPolicies = {
        aws = ''
          # AWS-specific policies
          ip community-list standard aws-well-known permit 7224:*
          route-map aws-in permit 10
            match community aws-well-known
            set local-preference 150
        '';

        azure = ''
          # Azure-specific policies
          ip community-list standard azure-well-known permit 12076:*
          route-map azure-in permit 10
            match community azure-well-known
            set local-preference 140
        '';

        gcp = ''
          # GCP-specific policies
          ip community-list standard gcp-well-known permit 15169:*
          route-map gcp-in permit 10
            match community gcp-well-known
            set local-preference 130
        '';

        oracle = ''
          # Oracle-specific policies
          ip as-path access-list oracle-as permit _31898_
          route-map oracle-in permit 10
            match as-path oracle-as
            set local-preference 120
        '';

        ibm = ''
          # IBM-specific policies
          ip as-path access-list ibm-as permit _36351_
          route-map ibm-in permit 10
            match as-path ibm-as
            set local-preference 110
        '';
      };

      providerSpecificPolicies = providerPolicies.${provider} or "";
    in
    ''
      # Provider-specific BGP configuration for ${provider}
      ${multipathConfig}
      ${extendedNexthopConfig}
      ${largeCommunitiesConfig}
      ${flowspecConfig}
      ${providerSpecificPolicies}
    '';

  # Generate provider-specific interface configuration
  generateProviderSpecificInterface =
    name: connection:
    let
      provider = connection.provider;
      providerCfg = getProviderConfig provider;
      interfaceName = "dx-${name}";
    in
    {
      ${interfaceName} = {
        enable = true;
        type = "direct-connect";
        provider = provider;
        bandwidth = connection.bandwidth;
        location = connection.location;
        mtu = 9001; # Jumbo frames
        description = "Direct Connect to ${provider} at ${connection.location}";

        # Provider-specific settings
        providerSettings = providerCfg // {
          facilities = providerCfg.locations.${connection.location}.facilities or [ ];
          metro = providerCfg.locations.${connection.location}.metro or connection.location;
        };
      };
    };

  # Validate provider-specific requirements
  validateProviderRequirements =
    name: connection:
    let
      provider = connection.provider;
      providerCfg = getProviderConfig provider;
      location = connection.location;
      bandwidth = connection.bandwidth;
      connectionType = connection.connectionType;

      # Check if location is supported
      locationSupported = providerCfg ? locations && providerCfg.locations ? ${location};

      # Check if bandwidth is supported
      bandwidthSupported = builtins.elem bandwidth providerCfg.bandwidths;

      # Check if connection type is supported
      connectionTypeSupported = builtins.elem connectionType providerCfg.connectionTypes;
    in
    assert lib.assertMsg locationSupported
      "Location ${location} not supported for provider ${provider}";
    assert lib.assertMsg bandwidthSupported
      "Bandwidth ${bandwidth} not supported for provider ${provider}";
    assert lib.assertMsg connectionTypeSupported
      "Connection type ${connectionType} not supported for provider ${provider}";
    connection;

  # Generate provider-specific monitoring
  generateProviderSpecificMonitoring =
    name: connection: pkgs:
    let
      provider = connection.provider;
      providerCfg = getProviderConfig provider;

      # Provider-specific health checks
      providerHealthChecks = {
        aws = {
          endpoints = [
            "dynamodb.us-east-1.amazonaws.com"
            "s3.amazonaws.com"
          ];
          icmpTargets = [
            "8.8.8.8"
            "1.1.1.1"
          ];
        };
        azure = {
          endpoints = [
            "azure.microsoft.com"
            "login.microsoftonline.com"
          ];
          icmpTargets = [
            "8.8.8.8"
            "1.1.1.1"
          ];
        };
        gcp = {
          endpoints = [
            "www.googleapis.com"
            "storage.googleapis.com"
          ];
          icmpTargets = [
            "8.8.8.8"
            "1.1.1.1"
          ];
        };
        oracle = {
          endpoints = [
            "oracle.com"
            "cloud.oracle.com"
          ];
          icmpTargets = [
            "8.8.8.8"
            "1.1.1.1"
          ];
        };
        ibm = {
          endpoints = [
            "cloud.ibm.com"
            "api.ibm.com"
          ];
          icmpTargets = [
            "8.8.8.8"
            "1.1.1.1"
          ];
        };
      };

      healthCheckCfg =
        providerHealthChecks.${provider} or {
          endpoints = [ ];
          icmpTargets = [ "8.8.8.8" ];
        };
    in
    {
      services.prometheus.exporters.blackbox = {
        enable = true;
        configFile = pkgs.writeText "dx-${name}-blackbox.yml" ''
          modules:
            http_2xx:
              prober: http
              timeout: 5s
            icmp:
              prober: icmp
              timeout: 5s
            tcp_connect:
              prober: tcp
              timeout: 5s
        '';
      };

      services.prometheus.scrapeConfigs = [
        {
          job_name = "direct-connect-${name}-provider";
          static_configs = [
            {
              targets = map (endpoint: "${endpoint}:443") healthCheckCfg.endpoints;
            }
          ];
          metrics_path = "/probe";
          params = {
            module = [ "http_2xx" ];
          };
        }
        {
          job_name = "direct-connect-${name}-connectivity";
          static_configs = [
            {
              targets = map (target: "${target}:0") healthCheckCfg.icmpTargets;
            }
          ];
          metrics_path = "/probe";
          params = {
            module = [ "icmp" ];
          };
        }
      ];
    };

  # Generate provider-specific alerts
  generateProviderSpecificAlerts =
    name: connection: pkgs:
    let
      provider = connection.provider;
      providerCfg = getProviderConfig provider;

      # Provider-specific alert thresholds
      alertThresholds = {
        aws = {
          latencyThreshold = "50ms";
          packetLossThreshold = "0.1";
        };
        azure = {
          latencyThreshold = "60ms";
          packetLossThreshold = "0.1";
        };
        gcp = {
          latencyThreshold = "40ms";
          packetLossThreshold = "0.05";
        };
        oracle = {
          latencyThreshold = "55ms";
          packetLossThreshold = "0.1";
        };
        ibm = {
          latencyThreshold = "65ms";
          packetLossThreshold = "0.1";
        };
      };

      thresholds =
        alertThresholds.${provider} or {
          latencyThreshold = "50ms";
          packetLossThreshold = "0.1";
        };
    in
    {
      services.prometheus.ruleFiles = [
        (pkgs.writeText "direct-connect-provider-${name}-alerts.yml" ''
          groups:
          - name: direct_connect_provider_${name}
            rules:
            - alert: DirectConnectProviderConnectivityDegraded
              expr: probe_success{job="direct-connect-${name}-provider"} < 0.95
              for: 5m
              labels:
                severity: warning
                connection: ${name}
                provider: ${connection.provider}
              annotations:
                summary: "Direct Connect ${name} provider connectivity degraded"
                description: "Connectivity to ${connection.provider} services is degraded for Direct Connect connection ${name}"
            - alert: DirectConnectHighLatency
              expr: probe_duration_seconds{job="direct-connect-${name}-connectivity"} > ${thresholds.latencyThreshold}
              for: 5m
              labels:
                severity: warning
                connection: ${name}
                provider: ${connection.provider}
              annotations:
                summary: "Direct Connect ${name} high latency to provider"
                description: "Latency to ${connection.provider} services exceeds ${thresholds.latencyThreshold} for connection ${name}"
        '')
      ];
    };
in
{
  inherit
    providerConfigs
    getProviderConfig
    generateProviderSpecificBGP
    generateProviderSpecificInterface
    validateProviderRequirements
    generateProviderSpecificMonitoring
    generateProviderSpecificAlerts
    ;
}

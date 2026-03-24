{ lib }:

# Private DNS Configuration Library
# Provides functions for managing private DNS zones and resolution

rec {
  # Generate private DNS zone configuration
  mkPrivateDnsZone =
    {
      name,
      vpcId,
      region,
      records ? [ ],
      tags ? { },
    }:
    {
      inherit
        name
        vpcId
        region
        records
        tags
        ;

      # Zone configuration
      zoneConfig = {
        name = name;
        privateZone = true;
        vpc = {
          vpcId = vpcId;
          region = region;
        };
      };

      # Generate zone records
      zoneRecords = lib.concatMap (record: [
        {
          name = record.name;
          type = record.type;
          ttl = record.ttl or 300;
          value = record.value;
        }
      ]) records;
    };

  # Generate DNS records for VPC endpoints
  mkEndpointDnsRecords =
    endpointConfig:
    if endpointConfig.privateDns.enable then
      let
        hostname =
          endpointConfig.privateDns.hostname or "${endpointConfig.service}.${endpointConfig.region}";
        endpointIPs =
          if endpointConfig.type == "interface" then
            # For interface endpoints, we'd need to get ENI IPs
            # This is a placeholder - actual IPs would come from cloud provider
            [
              "192.168.1.10"
              "192.168.1.11"
            ] # Example IPs
          else
            # Gateway endpoints don't have IPs, they use route tables
            [ ];
      in
      lib.concatMap (ip: [
        {
          name = hostname;
          type = "A";
          ttl = 300;
          value = ip;
        }
      ]) endpointIPs
    else
      [ ];

  # Generate split-horizon DNS configuration
  mkSplitHorizonConfig =
    {
      privateZones,
      publicResolvers ? [
        "8.8.8.8"
        "1.1.1.1"
      ],
      privateResolvers ? [ "127.0.0.1" ],
    }:
    {
      inherit privateZones publicResolvers privateResolvers;

      # DNS resolution rules
      resolutionRules =
        lib.concatMap (zone: [
          {
            domain = zone.name;
            resolvers = privateResolvers;
            private = true;
          }
        ]) privateZones
        ++ [
          {
            domain = "*";
            resolvers = publicResolvers;
            private = false;
          }
        ];
    };

  # Generate DNS forward zones for private endpoints
  mkDnsForwardZones =
    endpointConfigs: domain:
    let
      endpointZones = lib.concatMap (
        endpoint:
        if endpoint.privateDns.enable then
          let
            hostname = endpoint.privateDns.hostname or "${endpoint.service}.${endpoint.region}";
            zoneName = "${hostname}.${domain}";
          in
          [
            {
              name = zoneName;
              type = "forward";
              forwarders =
                if endpoint.type == "interface" then
                  # Interface endpoints - forward to cloud provider DNS
                  [ "169.254.169.253" ] # AWS VPC DNS
                else
                  # Gateway endpoints - no forwarding needed
                  [ ];
            }
          ]
        else
          [ ]
      ) endpointConfigs;
    in
    endpointZones;

  # Generate DNS zone files
  mkZoneFile =
    zone: domain: records:
    let
      serial = 2024121601; # YYYYMMDDNN format
      soaRecord = ''
        @ IN SOA ns1.${domain}. admin.${domain}. (
            ${toString serial}  ; serial
            3600                ; refresh
            1800                ; retry
            604800              ; expire
            300                 ; minimum
        )
      '';
      nsRecords = ''
        @ IN NS ns1.${domain}.
        ns1 IN A 127.0.0.1
      '';
      resourceRecords = lib.concatMapStrings (record: ''
        ${record.name} IN ${record.type} ${record.value}
      '') records;
    in
    ''
      $ORIGIN ${zone}.
      $TTL 300
      ${soaRecord}
      ${nsRecords}
      ${resourceRecords}
    '';

  # Validate DNS configuration
  validateDnsConfig =
    config:
    let
      hasValidZones = config ? privateZones && lib.isList config.privateZones;
      hasValidResolvers =
        config ? publicResolvers
        && config ? privateResolvers
        && lib.isList config.publicResolvers
        && lib.isList config.privateResolvers;
    in
    hasValidZones && hasValidResolvers;
}

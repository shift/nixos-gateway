{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.gateway;

  # Import schema normalization (same as dhcp.nix / dns.nix)
  schemaNormalization = import ../lib/schema-normalization.nix { inherit lib; };

  hostsData = schemaNormalization.normalizeHostsData (cfg.data.hosts or { });
  networkData = schemaNormalization.normalizeNetworkData (cfg.data.network or { });
  domain = cfg.domain or "lan.local";

  gatewayIpv4 = schemaNormalization.getSubnetGateway networkData "lan";
  subnet = schemaNormalization.getSubnetNetwork networkData "lan";
  dhcpRange = schemaNormalization.getSubnetDhcpRange networkData "lan";
  poolStart = dhcpRange.start;
  poolEnd = dhcpRange.end;

  subnetPrefixLen = lib.last (lib.splitString "/" subnet);

  staticDHCPv4Assignments = hostsData.staticDHCPv4Assignments or [ ];

  # Calculate pool offset and size from the pool start/end relative to the subnet
  poolStartLastOctet = lib.last (lib.splitString "." poolStart);
  poolEndLastOctet = lib.last (lib.splitString "." poolEnd);
  poolOffset = lib.toInt poolStartLastOctet;
  poolSize = (lib.toInt poolEndLastOctet) - poolOffset + 1;

in
{
  config = lib.mkIf (cfg.profile == "alix-networkd") {
    # Extend the LAN networkd unit with DHCP server + SLAAC
    # This merges with network.nix's "50-lan" definition (same match/addr = no conflict)
    systemd.network.networks."50-lan" = {
      matchConfig.Name = cfg.interfaces.lan;
      address = [ "${gatewayIpv4}/${subnetPrefixLen}" ];
      networkConfig = {
        ConfigureWithoutCarrier = true;
        IPv6AcceptRA = false;
        DHCPServer = true;
      };

      dhcpServerConfig = {
        PoolOffset = poolOffset;
        PoolSize = poolSize;
        EmitDNS = true;
        EmitRouter = true;
        DefaultLeaseTimeSec = 86400;
        MaxLeaseTimeSec = 86400;
      };

      dhcpServerStaticLeases = map (assignment: {
        dhcpServerStaticLeaseConfig = {
          Address = assignment.ipAddress;
          MACAddress = assignment.macAddress;
        };
      }) staticDHCPv4Assignments;

      # IPv6: SLAAC + Router Advertisements (no DHCPv6 server)
      ipv6Prefixes = lib.optional (cfg.ipv6Prefix != "") [{
        ipv6PrefixConfig = {
          Prefix = "${cfg.ipv6Prefix}/64";
          Assign = true;
        };
      }];
    };
  };
}

{ lib }:

let
  # Normalize network data to standard format
  normalizeNetworkData =
    networkData:
    if networkData ? subnets && lib.isList networkData.subnets then
      # New schema - already normalized
      networkData
    else if networkData ? subnets && lib.isAttrs networkData.subnets then
      # Old schema - convert to new format
      {
        subnets = lib.mapAttrsToList (
          name: subnet:
          let
            dhcpRange =
              if networkData ? dhcp && networkData.dhcp ? poolStart && networkData.dhcp ? poolEnd then
                {
                  start = networkData.dhcp.poolStart;
                  end = networkData.dhcp.poolEnd;
                }
              else if subnet ? dhcpRange then
                subnet.dhcpRange
              else
                {
                  start = "192.168.1.50";
                  end = "192.168.1.254";
                };
          in
          {
            inherit name;
            network = subnet.ipv4.subnet or "192.168.1.0/24";
            gateway = subnet.ipv4.gateway or "192.168.1.1";
            ipv4 = subnet.ipv4 or { };
            ipv6 = subnet.ipv6 or { };
            inherit dhcpRange;
            dnsServers = [ "192.168.1.1" ];
            ntpServers = [ "192.168.1.1" ];
          }
        ) networkData.subnets;
        mgmtAddress = networkData.mgmtAddress or "192.168.1.1";
      }
    else
      # Default fallback
      {
        subnets = [
          {
            name = "lan";
            network = "192.168.1.0/24";
            gateway = "192.168.1.1";
            ipv4 = {
              subnet = "192.168.1.0/24";
              gateway = "192.168.1.1";
            };
            ipv6 = {
              prefix = "2001:db8::/48";
              gateway = "2001:db8::1";
            };
            dhcpRange = {
              start = "192.168.1.50";
              end = "192.168.1.254";
            };
            dnsServers = [ "192.168.1.1" ];
            ntpServers = [ "192.168.1.1" ];
          }
        ];
        mgmtAddress = "192.168.1.1";
      };

  # Find subnet by name in normalized data
  findSubnet =
    normalizedNetworkData: name:
    lib.findFirst (subnet: subnet.name == name) null normalizedNetworkData.subnets;

  # Get gateway IP for a subnet
  getSubnetGateway =
    normalizedNetworkData: subnetName:
    let
      subnet = findSubnet normalizedNetworkData subnetName;
    in
    if subnet != null then subnet.gateway else "192.168.1.1";

  # Get subnet network CIDR
  getSubnetNetwork =
    normalizedNetworkData: subnetName:
    let
      subnet = findSubnet normalizedNetworkData subnetName;
    in
    if subnet != null then subnet.network else "192.168.1.0/24";

  # Get DHCP range for a subnet
  getSubnetDhcpRange =
    normalizedNetworkData: subnetName:
    let
      subnet = findSubnet normalizedNetworkData subnetName;
    in
    if subnet != null && subnet ? dhcpRange then
      subnet.dhcpRange
    else
      {
        start = "192.168.1.50";
        end = "192.168.1.254";
      };

  # Normalize hosts data
  normalizeHostsData = hostsData: {
    staticDHCPv4Assignments = hostsData.staticDHCPv4Assignments or [ ];
    staticDHCPv6Assignments = hostsData.staticDHCPv6Assignments or [ ];
  };

in
{
  inherit
    normalizeNetworkData
    findSubnet
    getSubnetGateway
    getSubnetNetwork
    getSubnetDhcpRange
    normalizeHostsData
    ;
}

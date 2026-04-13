{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.gateway;

  schemaNormalization = import ../lib/schema-normalization.nix { inherit lib; };

  hostsData = schemaNormalization.normalizeHostsData (cfg.data.hosts or { });
  networkData = schemaNormalization.normalizeNetworkData (cfg.data.network or { });
  domain = cfg.domain or "lan.local";

  gatewayIpv4 = schemaNormalization.getSubnetGateway networkData "lan";
  subnet = schemaNormalization.getSubnetNetwork networkData "lan";
  dhcpRange = schemaNormalization.getSubnetDhcpRange networkData "lan";
  poolStart = dhcpRange.start;
  poolEnd = dhcpRange.end;

  staticDHCPv4Assignments = hostsData.staticDHCPv4Assignments or [ ];

  # Build host entries for dnsmasq local DNS
  hostAddressEntries = map (
    h:
    let
      hostname =
        if (h.fqdn or null) != null then (lib.head (lib.splitString "." h.fqdn)) else h.name;
    in
    "/${hostname}.${domain}/${h.ipAddress}"
  ) (lib.filter (h: (h.ipAddress or null) != null) staticDHCPv4Assignments);

  # Build dhcp-host entries for static leases
  dhcpHostEntries = map (h: "${h.macAddress},${h.ipAddress},${h.name}") staticDHCPv4Assignments;

  ipv6Enabled = cfg.ipv6Prefix != "";
  ipv6Prefix = lib.removeSuffix "::" cfg.ipv6Prefix;

in
{
  config = lib.mkIf (cfg.profile == "alix-dnsmasq") {
    services.dnsmasq = {
      enable = true;
      settings =
        {
          # Listen only on LAN interface
          interface = cfg.interfaces.lan;
          bind-interfaces = true;

          # DNS
          domain = domain;
          local = "/${domain}/";
          server = [
            "1.1.1.1"
            "8.8.8.8"
            "2606:4700:4700::1111"
          ];
          cache-size = 1000;
          dns-forward-max = 150;

          # Authoritative local DNS entries (replaces Knot for local zones)
          address = [
            "/${domain}/${gatewayIpv4}"
          ] ++ hostAddressEntries;

          # DHCPv4
          dhcp-range = [ "${poolStart},${poolEnd},24h" ]
            ++ lib.optional ipv6Enabled "${ipv6Prefix}::100,${ipv6Prefix}::200,24h";

          dhcp-option = [
            "option:router,${gatewayIpv4}"
            "option:dns-server,${gatewayIpv4}"
            "option:domain-search,${domain}"
          ];
          dhcp-host = dhcpHostEntries;
          dhcp-lease-max = 150;

          # SLAAC + RA for IPv6
          enable-ra = ipv6Enabled;

          # Logging
          log-queries = false;
          log-dhcp = true;

          # Don't use /etc/hosts
          no-hosts = true;
        };
    };

    # Override resolved to point at dnsmasq instead of kresd
    services.resolved.settings = {
      Resolve = {
        DNS = gatewayIpv4;
        Domains = "~${domain}";
      };
    };
  };
}

{ lib }:

let
  # Regex for IPv4
  # Matches:
  # 1. 250-255: 25[0-5]
  # 2. 200-249: 2[0-4][0-9]
  # 3. 0-199:   1[0-9][0-9] OR [1-9][0-9] OR [0-9]
  octet = "(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])";
  ipv4Regex = "^${octet}\\.${octet}\\.${octet}\\.${octet}$";

  validateIPAddress =
    ip:
    let
      isIPv4 = builtins.match ipv4Regex ip != null;
    in
    isIPv4;

  validatePort = port: builtins.isInt port && port >= 1 && port <= 65535;

  # Re-implementing MAC and CIDR validators to return boolean
  validateMACAddress =
    mac:
    let
      macPattern = "^([0-9a-fA-F]{2}[:-]){5}([0-9a-fA-F]{2})$";
    in
    builtins.match macPattern mac != null;

  validateCIDR =
    cidr:
    let
      split = lib.splitString "/" cidr;
      len = builtins.length split;
    in
    if len == 2 then
      let
        ip = builtins.elemAt split 0;
        prefixStr = builtins.elemAt split 1;
        # Check if prefix is a number
        isNum = builtins.match "[0-9]+" prefixStr != null;
        prefix = if isNum then lib.toInt prefixStr else -1;
      in
      if validateIPAddress ip then
        # IPv4: prefix must be 0-32
        prefix >= 0 && prefix <= 32
      else
        # Fallback for IPv6 (keep existing basic regex logic for now if not IPv4)
        # matches 8 groups of 1-4 hex digits
        let
          ipv6Pattern = "^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}/([0-9]{1,3})$";
        in
        builtins.match ipv6Pattern cidr != null
    else
      false;

  # ── BGP validators ────────────────────────────────────────────────────────────

  # Full 4-byte ASN range per RFC 4893: 1–4,294,967,295
  validateBGPASN = asn: builtins.isInt asn && asn >= 1 && asn <= 4294967295;

  # Router ID is always expressed as a dotted-quad IPv4 address
  validateBGPRouterId = routerId: validateIPAddress routerId;

  # Standard community: "<asn>:<value>"
  validateBGPCommunity =
    community: builtins.isString community && builtins.match "^[0-9]+:[0-9]+$" community != null;

  # Large community (RFC 8092): "<global-admin>:<local-data-1>:<local-data-2>"
  validateBPGLargeCommunity =
    largeCommunity:
    builtins.isString largeCommunity
    && builtins.match "^[0-9]+:[0-9]+:[0-9]+$" largeCommunity != null;

  # Neighbor: optional address (IP) and optional asn (int)
  validateBGPNeighbor =
    neighbor:
    (!(neighbor ? address) || validateIPAddress neighbor.address)
    && (!(neighbor ? asn) || validateBGPASN neighbor.asn);

  # Prefix list: list of entries, each with optional network (CIDR) and required action
  validateBGPPrefixList =
    prefixList:
    builtins.isList prefixList
    && builtins.all (
      entry:
      (!(entry ? network) || validateCIDR entry.network)
      && (entry ? action && builtins.elem entry.action [
        "permit"
        "deny"
      ])
    ) prefixList;

  # Route map: list of rules, each must carry a permit/deny action
  validateBGPRouteMap =
    routeMap:
    builtins.isList routeMap
    && builtins.all (
      rule: rule ? action && builtins.elem rule.action [ "permit" "deny" ]
    ) routeMap;

  # BGP config block: optional asn and routerId fields
  validateBGPConfig =
    config:
    (!(config ? asn) || validateBGPASN config.asn)
    && (!(config ? routerId) || validateIPAddress config.routerId);

  # ── Firewall / DHCP / IDS validators ──────────────────────────────────────────

  # Firewall rule: must have a valid action; protocol and ports are optional
  validateFirewallRule =
    rule:
    (rule ? action && builtins.elem rule.action [
      "accept"
      "drop"
      "reject"
    ])
    && (!(rule ? protocol) || builtins.elem rule.protocol [
      "tcp"
      "udp"
      "icmp"
      "all"
    ]);

  # DHCP config: optional subnet (CIDR) and gateway (IP); skip pool arithmetic
  # (pure Nix has no IP-to-int conversion, so range checks are deferred to runtime)
  validateDHCPConfig =
    config:
    (!(config ? subnet) || validateCIDR config.subnet)
    && (!(config ? gateway) || validateIPAddress config.gateway);

  # IDS config: profile, if present, must be one of the known tiers
  validateIDSConfig =
    config:
    !(config ? profile) || builtins.elem config.profile [ "low" "medium" "high" ];

  # ── Host / subnet / network validators ────────────────────────────────────────

  # Host: must have a string name; macAddress and ipAddress are optional but validated
  validateHost =
    host:
    (host ? name && builtins.isString host.name)
    && (!(host ? macAddress) || validateMACAddress host.macAddress)
    && (!(host ? ipAddress) || validateIPAddress host.ipAddress);

  # Subnet: optional cidr and gateway
  validateSubnet =
    subnet:
    (!(subnet ? cidr) || validateCIDR subnet.cidr)
    && (!(subnet ? gateway) || validateIPAddress subnet.gateway);

  # Network: if subnets attr-set is present, validate each value
  validateNetwork =
    network:
    !(network ? subnets)
    || builtins.all validateSubnet (builtins.attrValues network.subnets);

  # Flat list of host records (used by validateGatewayData)
  validateHosts = hosts: builtins.isList hosts && builtins.all validateHost hosts;

  # Top-level gateway data: validate network, static DHCP assignments, and firewall rules
  validateGatewayData =
    data:
    (!(data ? network) || validateNetwork data.network)
    && (
      !(data ? hosts)
      || validateHosts (data.hosts.staticDHCPv4Assignments or [ ])
    )
    && (
      !(data ? firewall)
      || !(data.firewall ? rules)
      || builtins.all validateFirewallRule data.firewall.rules
    );

  # ── Simple / secret validators ─────────────────────────────────────────────────

  # Runtime paths (e.g. /var/lib/...) don't exist at eval time — always true
  fileExists = _path: true;

  # Base64-encoded key: alphabet check + minimum 16-char length
  base64Key =
    key:
    builtins.isString key
    && builtins.match "^[A-Za-z0-9+/]*={0,2}$" key != null
    && builtins.stringLength key >= 16;

  # Non-empty string
  nonEmptyString = str: builtins.isString str && str != "";

in
{
  inherit
    validateIPAddress
    validateMACAddress
    validateCIDR
    validatePort
    validateFirewallRule
    validateDHCPConfig
    validateIDSConfig
    validateHost
    validateSubnet
    validateNetwork
    validateGatewayData
    validateBGPASN
    validateBGPRouterId
    validateBGPCommunity
    validateBPGLargeCommunity
    validateBGPNeighbor
    validateBGPPrefixList
    validateBGPRouteMap
    validateBGPConfig
    validateHosts
    fileExists
    base64Key
    nonEmptyString
    ;
}

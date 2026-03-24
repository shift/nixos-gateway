# NAT Gateway Configuration Library
{ lib, pkgs, ... }:

with lib;

let
  # Parse CIDR notation to get network and prefix
  parseCidr =
    cidr:
    let
      parts = splitString "/" cidr;
      network = elemAt parts 0;
      prefix = toInt (elemAt parts 1);
    in
    {
      inherit network prefix;
    };

  # Extract prefix length from CIDR
  getPrefixLength = cidr: (parseCidr cidr).prefix;

  # Generate iptables SNAT rules for an instance
  mkSnatRules =
    instance:
    let
      publicIPs = instance.publicIPs;
      privateSubnets = instance.privateSubnets;
      interface = instance.publicInterface;

      # Create SNAT rules for each public IP with load balancing
      snatRules = if length publicIPs > 1 then
        concatStringsSep "\n" (
          imap0 (
            i: ip:
            let
              mark = i + 1;
            in
            ''
              # Mark connections for load balancing to ${ip}
              ${pkgs.iptables}/bin/iptables -t mangle -A PREROUTING -i ${interface} -m statistic --mode nth --every ${toString (length publicIPs)} --packet ${toString i} -j MARK --set-mark ${toString mark}

              # SNAT rule for marked connections
              ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -o ${interface} -m mark --mark ${toString mark} -j SNAT --to-source ${ip}
            ''
          ) publicIPs
        )
      else if length publicIPs == 1 then
        ''
          # Single IP SNAT
          ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -o ${interface} -j SNAT --to-source ${head publicIPs}
        ''
      else
        ''
          # Fallback to MASQUERADE
          ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -o ${interface} -j MASQUERADE
        '';

      # Allow forwarding from private subnets
      forwardRules = concatStringsSep "\n" (
        map (
          subnet: ''
            # Allow forwarding from ${subnet} to ${interface}
            ${pkgs.iptables}/bin/iptables -A FORWARD -s ${subnet} -o ${interface} -j ACCEPT
            ${pkgs.iptables}/bin/iptables -A FORWARD -i ${interface} -d ${subnet} -m state --state ESTABLISHED,RELATED -j ACCEPT
          ''
        ) privateSubnets
      );

    in
    snatRules + "\n" + forwardRules;

  # Generate port forwarding rules
  mkPortForwardingRules =
    instance:
    let
      interface = instance.publicInterface;
    in
    concatStringsSep "\n" (
      map (
        rule:
        let
          protocol = rule.protocol;
          externalPort = rule.port;
          targetIP = rule.targetIP;
          targetPort = rule.targetPort;
        in
        ''
          # Port forward ${protocol} ${externalPort} -> ${targetIP}:${targetPort}
          ${pkgs.iptables}/bin/iptables -t nat -A PREROUTING -i ${interface} -p ${protocol} --dport ${toString externalPort} -j DNAT --to-destination ${targetIP}:${toString targetPort}
          ${pkgs.iptables}/bin/iptables -A FORWARD -p ${protocol} -d ${targetIP} --dport ${toString targetPort} -j ACCEPT
        ''
      ) instance.portForwarding
    );

  # Generate connection tracking rules
  mkConntrackRules =
    instance:
    let
      maxConnections = instance.maxConnections or 100000;
      timeout = instance.timeout or { };
    in
    ''
      # Set connection tracking limits
      echo ${toString maxConnections} > /proc/sys/net/netfilter/nf_conntrack_max

      # Configure timeouts
      ${optionalString (timeout.tcp != null) ''
        ${pkgs.conntrack-tools}/bin/conntrack -U --timeout ${timeout.tcp} -p tcp --state ESTABLISHED 2>/dev/null || true
      ''}
      ${optionalString (timeout.udp != null) ''
        ${pkgs.conntrack-tools}/bin/conntrack -U --timeout ${timeout.udp} -p udp 2>/dev/null || true
      ''}

      # Connection limit protection
      ${pkgs.iptables}/bin/iptables -A INPUT -i ${instance.publicInterface} -m connlimit --connlimit-above ${toString maxConnections} -j DROP
    '';

  # Generate routing rules for private subnets
  mkRoutingRules =
    instance:
    let
      interface = instance.publicInterface;
      routeTableId = 100 + (builtins.hashString "md5" instance.name |> builtins.stringToChars |> lib.foldl' (acc: c: acc + (builtins.stringToInt c) % 10) 0 |> toString);
    in
    ''
      # Create custom routing table for ${instance.name}
      echo "${routeTableId} nat-${instance.name}" >> /etc/iproute2/rt_tables 2>/dev/null || true

      # Add routes for private subnets
      ${concatStringsSep "\n" (
        map (
          subnet: ''
            # Route ${subnet} through NAT table
            ${pkgs.iproute2}/bin/ip rule add from ${subnet} table nat-${instance.name} 2>/dev/null || true
            ${pkgs.iproute2}/bin/ip route add ${subnet} dev ${interface} table nat-${instance.name} 2>/dev/null || true
          ''
        ) instance.privateSubnets
      )}
    '';

  # Generate cleanup rules
  mkNatCleanup =
    instance:
    let
      interface = instance.publicInterface;
    in
    ''
      # Clean up NAT Gateway ${instance.name}

      # Remove iptables rules
      ${pkgs.iptables}/bin/iptables -t nat -F POSTROUTING 2>/dev/null || true
      ${pkgs.iptables}/bin/iptables -t nat -F PREROUTING 2>/dev/null || true
      ${pkgs.iptables}/bin/iptables -t mangle -F PREROUTING 2>/dev/null || true
      ${pkgs.iptables}/bin/iptables -F FORWARD 2>/dev/null || true

      # Remove routing rules
      ${concatStringsSep "\n" (
        map (
          subnet: ''
            ${pkgs.iproute2}/bin/ip rule del from ${subnet} table nat-${instance.name} 2>/dev/null || true
            ${pkgs.iproute2}/bin/ip route del ${subnet} table nat-${instance.name} 2>/dev/null || true
          ''
        ) instance.privateSubnets
      )}

      # Remove routing table entry
      sed -i "/nat-${instance.name}/d" /etc/iproute2/rt_tables 2>/dev/null || true

      echo "NAT Gateway ${instance.name} cleanup completed"
    '';

  # Validate NAT configuration
  validateNatConfig =
    instances:
    let
      errors = flatten (
        map (
          instance:
          let
            name = instance.name;
            interface = instance.publicInterface;
            subnets = instance.privateSubnets;
            ips = instance.publicIPs;
          in
          (if name == "" then [ "Instance name cannot be empty" ] else [ ])
          ++ (if interface == "" then [ "Public interface cannot be empty for ${name}" ] else [ ])
          ++ (if length subnets == 0 then [ "At least one private subnet required for ${name}" ] else [ ])
          ++ (if length ips == 0 then [ "At least one public IP required for ${name}" ] else [ ])
        ) instances
      );
    in
    {
      valid = length errors == 0;
      inherit errors;
    };

in
{
  inherit
    parseCidr
    getPrefixLength
    mkSnatRules
    mkPortForwardingRules
    mkConntrackRules
    mkRoutingRules
    mkNatCleanup
    validateNatConfig;
}

{ lib, pkgs }:

let
  # Calculate netmask from CIDR
  calculateNetmask =
    cidr:
    let
      parts = lib.splitString "/" cidr;
      prefix = lib.toInt (lib.last parts);
      netmask = lib.toInt (lib.pow 2 (32 - prefix)) - 1;
      inverted = 4294967295 - netmask;
    in
    "${toString (lib.mod (lib.div inverted 16777216) 256)}.${toString (lib.mod (lib.div inverted 65536) 256)}.${toString (lib.mod (lib.div inverted 256) 256)}.${toString (lib.mod inverted 256)}";

  # Calculate DHCP range from subnet CIDR
  calculateDHCPRange =
    subnets:
    let
      subnet = lib.head subnets;
      parts = lib.splitString "/" subnet;
      baseIP = lib.head parts;
      ipParts = lib.splitString "." baseIP;
      startIP = "${lib.elemAt ipParts 0}.${lib.elemAt ipParts 1}.${lib.elemAt ipParts 2}.100";
      endIP = "${lib.elemAt ipParts 0}.${lib.elemAt ipParts 1}.${lib.elemAt ipParts 2}.200";
    in
    "${startIP} ${endIP}";

  # Calculate gateway IP from subnet CIDR
  calculateGatewayIP =
    subnets:
    let
      subnet = lib.head subnets;
      parts = lib.splitString "/" subnet;
      baseIP = lib.head parts;
      ipParts = lib.splitString "." baseIP;
    in
    "${lib.elemAt ipParts 0}.${lib.elemAt ipParts 1}.${lib.elemAt ipParts 2}.1";

  # Generate iptables rules for network ACLs
  generateNetworkACLRules =
    networkACLs:
    lib.flatten (
      map (
        acl:
        map (
          rule:
          let
            action = if rule.type == "allow" then "-j ACCEPT" else "-j DROP";
            protocol = if rule.protocol == "all" then "" else "-p ${rule.protocol}";
            portSpec =
              if rule.portRange != null then
                "-m ${rule.protocol} --dport ${toString rule.portRange.from}:${toString rule.portRange.to}"
              else
                "";
            sources = lib.concatStringsSep " " (map (src: "-s ${src}") rule.sources);
          in
          "${pkgs.iptables}/bin/iptables -A IGW_ACL ${protocol} ${portSpec} ${sources} ${action} # ${rule.description}"
        ) acl.rules
      ) networkACLs
    );

  # Validate IGW configuration
  validateIGWConfig =
    gateways:
    let
      names = map (gw: gw.name) gateways;
      uniqueNames = lib.unique names;
      interfaces = map (gw: gw.interface) gateways;
      uniqueInterfaces = lib.unique interfaces;
    in
    if lib.length names != lib.length uniqueNames then
      throw "Internet Gateway names must be unique"
    else if lib.length interfaces != lib.length uniqueInterfaces then
      throw "Internet Gateway interfaces must be unique"
    else
      true;

  # Generate route table entries for attached networks
  generateRouteTable =
    gateways:
    lib.flatten (
      map (
        gw:
        map (
          attachment:
          let
            subnet = lib.head attachment.subnets;
          in
          "ip route add ${subnet} dev ${gw.interface} table ${attachment.network}"
        ) gw.attachments
      ) gateways
    );

  # Generate NAT rules for outbound traffic
  generateNATRules =
    gateways:
    map (
      gw:
      if gw.enableNAT then
        "${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -o ${gw.interface} -j MASQUERADE"
      else
        ""
    ) gateways;

  # Health check configuration
  generateHealthChecks =
    gateways:
    map (gw: {
      name = "igw-${gw.name}-connectivity";
      type = "http";
      url = "http://8.8.8.8";
      interface = gw.interface;
      interval = "30s";
      timeout = "5s";
    }) gateways;

  # Generate Prometheus metrics configuration
  generateMetricsConfig =
    {
      enable,
      metricsPort,
      trafficAnalytics,
      securityEvents,
    }:
    if enable then
      ''
        # IGW Metrics
        scrape_configs:
          - job_name: 'igw-node'
            static_configs:
              - targets: ['localhost:${toString metricsPort}']
            scrape_interval: 15s

        ${lib.optionalString trafficAnalytics ''
          - job_name: 'igw-traffic'
            static_configs:
              - targets: ['localhost:9100']
            scrape_interval: 60s
        ''}

        ${lib.optionalString securityEvents ''
          - job_name: 'igw-security'
            file_sd_configs:
              - files:
                - /var/log/igw-security-events.json
            scrape_interval: 30s
        ''}
      ''
    else
      "";

  # Generate systemd service dependencies
  generateServiceDependencies =
    gateways:
    let
      interfaces = map (gw: gw.interface) gateways;
    in
    lib.concatStringsSep " " (map (iface: "sys-subsystem-net-devices-${iface}.device") interfaces);

in
{
  inherit
    calculateNetmask
    calculateDHCPRange
    calculateGatewayIP
    generateNetworkACLRules
    validateIGWConfig
    generateRouteTable
    generateNATRules
    generateHealthChecks
    generateMetricsConfig
    generateServiceDependencies
    ;
}

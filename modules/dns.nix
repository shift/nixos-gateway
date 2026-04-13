{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.gateway;
  enabled = (cfg.enable or true) && (cfg.profile or "full") == "full";

  # Import schema normalization
  schemaNormalization = import ../lib/schema-normalization.nix { inherit lib; };

  tsigKeyPath = "/var/lib/knot/keys/kea-ddns.key";

  hostsData = schemaNormalization.normalizeHostsData (cfg.data.hosts or { });
  networkData = schemaNormalization.normalizeNetworkData (cfg.data.network or { });
  domain = cfg.domain or "lan.local";

  dnscollectorConfig = pkgs.writeText "dnscollector.yml" ''
    global:
      trace:
        verbose: true

    pipelines:
      - name: tap
        dnstap:
          listen-ip: 127.0.0.1
          listen-port: 6001
        transforms:
          normalize:
            qname-lowercase: true
        routing-policy:
          forward: [ console, logfile, metrics ]
      
      - name: console
        stdout:
          mode: text
      
      - name: logfile
        logfile:
          file-path: /var/log/dnscollector/queries.log
          max-size: 100
          mode: json
      
      - name: metrics
        prometheus:
          listen-ip: 127.0.0.1
          listen-port: 9142
          prometheus-prefix: dnscollector
  '';

  generateForwardZoneRecords =
    hosts:
    let
      hostRecords = lib.concatMapStrings (
        host:
        let
          hostname =
            if (host.fqdn or null) != null then (lib.head (lib.splitString "." host.fqdn)) else host.name;
          v4Record = lib.optionalString (
            (host.ipAddress or null) != null
          ) "${hostname}   IN  A    ${host.ipAddress}\n";
          v6Record = lib.optionalString (
            (host.ipv6Address or null) != null
          ) "${hostname}   IN  AAAA ${host.ipv6Address}\n";
        in
        v4Record + v6Record
      ) hosts;
    in
    hostRecords;

  generateIPv4ReverseRecords =
    hosts:
    lib.concatMapStrings (
      host:
      let
        hasPtr = (host.ptrRecord or false) == true;
        ipParts = lib.splitString "." host.ipAddress;
        lastOctet = lib.last ipParts;
        hostname = if (host.fqdn or null) != null then host.fqdn else "${host.name}.${domain}";
      in
      lib.optionalString (
        hasPtr && (host.ipAddress or null) != null
      ) "${lastOctet}   IN  PTR  ${hostname}.\n"
    ) hosts;

  generateIPv6ReverseRecords =
    hosts:
    lib.concatMapStrings (
      host:
      let
        hasPtr = (host.ptrRecord or false) == true;
        hostname = if (host.fqdn or null) != null then host.fqdn else "${host.name}.${domain}";
      in
      lib.optionalString (hasPtr && (host.ipv6Address or null) != null) ""
    ) hosts;

  # Use normalized schema functions
  gatewayIpv4 = schemaNormalization.getSubnetGateway networkData "lan";
  gatewayIpv6 =
    let
      lanSubnet = schemaNormalization.findSubnet networkData "lan";
    in
    if lanSubnet != null && lanSubnet ? ipv6 && lanSubnet.ipv6 ? gateway then
      lanSubnet.ipv6.gateway
    else if lanSubnet != null && lanSubnet ? ipv6 && lanSubnet.ipv6 ? prefix then
      let
        prefixParts = lib.splitString "/" lanSubnet.ipv6.prefix;
        prefix = lib.head prefixParts;
        gatewayParts = lib.splitString ":" prefix;
        lastPart = lib.last gatewayParts;
        newLast = if lastPart == "::" then "1" else lastPart;
        gateway = lib.concatStringsSep ":" (lib.init gatewayParts ++ [ newLast ]);
      in
      gateway
    else
      "2001:db8::1";

  ipv4Subnet = schemaNormalization.getSubnetNetwork networkData "lan";
  ipv6Prefix =
    let
      lanSubnet = schemaNormalization.findSubnet networkData "lan";
    in
    if lanSubnet != null && lanSubnet ? ipv6 && lanSubnet.ipv6 ? prefix then
      lanSubnet.ipv6.prefix
    else
      "2001:db8::/48";

  ipv4Parts = lib.splitString "." gatewayIpv4;
  reverseZone = "${lib.elemAt ipv4Parts 2}.${lib.elemAt ipv4Parts 1}.${lib.elemAt ipv4Parts 0}.in-addr.arpa";

  ipv6ReverseZoneName =
    let
      prefix = lib.removeSuffix "::" (lib.head (lib.splitString "/" ipv6Prefix));
      parts = lib.filter (p: p != "") (lib.splitString ":" prefix);
    in
    "ip6.arpa";

  knotConfigTemplate = ''
    server:
      listen: 127.0.0.1@5353
      listen: ::1@5353

    log:
      - target: syslog
        any: info

    key:
      - id: kea-ddns
        algorithm: hmac-sha256
        secret: TSIG_SECRET_PLACEHOLDER

    acl:
      - id: kea_acl
        address: 127.0.0.1
        key: kea-ddns
        action: update

    zone:
      - domain: ${domain}
        storage: /var/lib/knot/zones
        file: ${domain}.zone
        acl: kea_acl

      - domain: ${reverseZone}
        storage: /var/lib/knot/zones
        file: ${reverseZone}.zone
        acl: kea_acl

      - domain: ${ipv6ReverseZoneName}
        storage: /var/lib/knot/zones
        file: ipv6-reverse.zone
        acl: kea_acl
  '';

  forwardZone = pkgs.writeText "${domain}.zone" (
    ''
      $ORIGIN ${domain}.
      $TTL 300

      @   IN  SOA  ns1.${domain}. admin.${domain}. (
                  2024101401  ; serial
                  3600        ; refresh
                  1800        ; retry
                  604800      ; expire
                  300 )       ; minimum

      @     IN  NS   ns1.${domain}.
      ns1   IN  A    ${gatewayIpv4}
      ns1   IN  AAAA ${gatewayIpv6}
      @     IN  A    ${gatewayIpv4}
      cache IN  A    ${gatewayIpv4}
      cache IN  AAAA ${gatewayIpv6}
    ''
    + (generateForwardZoneRecords hostsData.staticDHCPv4Assignments or [ ])
  );

  ipv4ReverseZone = pkgs.writeText "${reverseZone}.zone" (
    ''
      $ORIGIN ${reverseZone}.
      $TTL 300

      @   IN  SOA  ns1.${domain}. admin.${domain}. (
                  2024101401  ; serial
                  3600        ; refresh
                  1800        ; retry
                  604800      ; expire
                  300 )       ; minimum

      @   IN  NS   ns1.${domain}.
    ''
    + (generateIPv4ReverseRecords hostsData.staticDHCPv4Assignments or [ ])
  );

  ipv6ReverseZone = pkgs.writeText "ipv6-reverse.zone" ''
    $ORIGIN ${ipv6ReverseZoneName}.
    $TTL 300

    @   IN  SOA  ns1.${domain}. admin.${domain}. (
                2024101401  ; serial
                3600        ; refresh
                1800        ; retry
                604800      ; expire
                300 )       ; minimum

    @   IN  NS   ns1.${domain}.
  '';
in
{
  config = lib.mkIf enabled {
    systemd.services.knot-setup = {
      description = "Setup Knot DNS TSIG key and zones";
      wantedBy = [ "multi-user.target" ];
      before = [ "knot.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
                mkdir -p /var/lib/knot/keys /var/lib/knot/zones
                
                if [ ! -f /var/lib/knot/keys/kea-ddns.secret ]; then
                  ${pkgs.knot-dns}/bin/keymgr -t kea-ddns hmac-sha256 | ${pkgs.gnugrep}/bin/grep '^secret: ' | ${pkgs.gawk}/bin/awk '{print $2}' | head -n 1 > /var/lib/knot/keys/kea-ddns.secret
                fi
                
                TSIG_SECRET=$(head -n 1 /var/lib/knot/keys/kea-ddns.secret | tr -d '[:space:]')
                
                cat > /var/lib/knot/knotd.conf << 'EOF'
        ${knotConfigTemplate}
        EOF
                
                sed -i "s|TSIG_SECRET_PLACEHOLDER|$TSIG_SECRET|g" /var/lib/knot/knotd.conf
                
                cp ${forwardZone} /var/lib/knot/zones/${domain}.zone
                cp ${ipv4ReverseZone} /var/lib/knot/zones/${reverseZone}.zone
                cp ${ipv6ReverseZone} /var/lib/knot/zones/ipv6-reverse.zone
                
                chown -R knot:knot /var/lib/knot
                chmod 640 /var/lib/knot/keys/kea-ddns.secret
                chmod 644 /var/lib/knot/knotd.conf
      '';
    };

    services.knot = {
      enable = true;
      settingsFile = "/var/lib/knot/knotd.conf";
    };

    services.kresd = {
      enable = true;
      listenPlain = [
        "127.0.0.1:53"
        "${gatewayIpv4}:53"
        "[::1]:53"
        "[${gatewayIpv6}]:53"
      ];
      extraConfig = ''
        cache.size = 100 * MB

        policy.add(policy.suffix(policy.STUB({'127.0.0.1@5353'}), {
          todname('${domain}.'),
          todname('${reverseZone}.'),
          todname('${ipv6ReverseZoneName}.')
        }))

        modules.load('dnstap')
        dnstap.config({
          socket_path = 'tcp:127.0.0.1:6001',
          identity = 'kresd',
          version = 'kresd 5.x',
          client = { log_queries = true, log_responses = true }
        })
      '';
    };

    systemd.tmpfiles.rules = [
      "d /var/cache/knot-resolver 0700 knot-resolver knot-resolver - -"
    ];

    systemd.services."kresd@1".after = [ "dnscollector.service" ];
    systemd.services."kresd@1".wants = [ "dnscollector.service" ];

    services.prometheus.exporters.bind = {
      enable = false;
    };

    systemd.services."kresd@".serviceConfig = {
      AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
      CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
    };

    systemd.services.dnscollector = {
      description = "DNS Collector for query logging and metrics";
      after = [
        "network.target"
        "kresd@1.service"
      ];
      wants = [ "kresd@1.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        User = "dnscollector";
        Group = "dnscollector";
        ExecStart = "${pkgs.go-dnscollector}/bin/go-dnscollector -config ${dnscollectorConfig}";
        Restart = "on-failure";
        RestartSec = "5s";

        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ "/var/log/dnscollector" ];

        LogsDirectory = "dnscollector";
        StateDirectory = "dnscollector";
      };
    };

    users.users.dnscollector = {
      isSystemUser = true;
      group = "dnscollector";
    };

    users.groups.dnscollector = { };
  };
}

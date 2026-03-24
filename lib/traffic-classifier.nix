{ lib }:

let
  dscpMap = {
    "CS0" = 0;
    "BE" = 0;
    "CS1" = 8;
    "CS2" = 16;
    "CS3" = 24;
    "CS4" = 32;
    "CS5" = 40;
    "CS6" = 48;
    "CS7" = 56;
    "EF" = 46;
    "AF11" = 10;
    "AF12" = 12;
    "AF13" = 14;
    "AF21" = 18;
    "AF22" = 20;
    "AF23" = 22;
    "AF31" = 26;
    "AF32" = 28;
    "AF33" = 30;
    "AF41" = 34;
    "AF42" = 36;
    "AF43" = 38;
  };

  # Enhanced protocol and application signatures
  protocolMap = {
    "ssh" = {
      proto = "tcp";
      dport = 22;
      signature = null;
    };
    "http" = {
      proto = "tcp";
      dport = 80;
      signature = {
        method = "GET|POST|PUT|DELETE|HEAD";
        header = "Host:";
      };
    };
    "https" = {
      proto = "tcp";
      dport = 443;
      signature = {
        tls = true;
        sni = true;
      };
    };
    "dns" = {
      proto = "udp";
      dport = 53;
      signature = null;
    };
    "sip" = {
      proto = "udp";
      dport = 5060;
      signature = {
        method = "INVITE|ACK|BYE|CANCEL|REGISTER";
        header = "Via:|From:|To:|Call-ID:";
      };
    };
    "rtp" = {
      proto = "udp";
      portRange = "10000-20000";
      signature = {
        rtp = true;
        payloadType = "0-127";
      };
    };
    "bgp" = {
      proto = "tcp";
      dport = 179;
      signature = null;
    };
  };

  # Application signatures for deep packet inspection
  applicationSignatures = {
    zoom = {
      ports = [ 80 443 ];
      domains = [ "*.zoom.us" "*.zoom.com" ];
      signatures = [
        { pattern = "zoom"; offset = 0; }
        { pattern = "Zoom"; offset = 0; }
      ];
    };

    teams = {
      ports = [ 80 443 ];
      domains = [ "*.teams.microsoft.com" "*.office.com" ];
      signatures = [
        { pattern = "teams"; offset = 0; }
        { pattern = "skype"; offset = 0; }
      ];
    };

    webex = {
      ports = [ 80 443 ];
      domains = [ "*.webex.com" "*.cisco.com" ];
      signatures = [
        { pattern = "webex"; offset = 0; }
        { pattern = "cisco"; offset = 0; }
      ];
    };

    steam = {
      ports = [ 80 443 27015 ];
      domains = [ "*.steam.com" "*.steampowered.com" ];
      signatures = [
        { pattern = "steam"; offset = 0; }
        { pattern = "valve"; offset = 0; }
      ];
    };

    epic-games = {
      ports = [ 80 443 ];
      domains = [ "*.epicgames.com" "*.fortnite.com" ];
      signatures = [
        { pattern = "epic"; offset = 0; }
        { pattern = "fortnite"; offset = 0; }
      ];
    };

    xbox-live = {
      ports = [ 80 443 3074 ];
      domains = [ "*.xboxlive.com" "*.xbox.com" ];
      signatures = [
        { pattern = "xbox"; offset = 0; }
        { pattern = "microsoft"; offset = 0; }
      ];
    };

    torrents = {
      ports = [ 6881 6882 6883 ];
      signatures = [
        { pattern = "BitTorrent protocol"; offset = 0; }
        { pattern = "\x13BitTorrent protocol"; offset = 0; }
      ];
    };

    social-media = {
      ports = [ 80 443 ];
      domains = [
        "*.facebook.com" "*.instagram.com" "*.twitter.com" "*.tiktok.com"
        "*.snapchat.com" "*.linkedin.com" "*.pinterest.com"
      ];
      signatures = [
        { pattern = "facebook"; offset = 0; }
        { pattern = "instagram"; offset = 0; }
        { pattern = "twitter"; offset = 0; }
      ];
    };

    gaming = {
      ports = [ 80 443 ];
      signatures = [
        { pattern = "game"; offset = 0; }
        { pattern = "gaming"; offset = 0; }
      ];
    };

    backups = {
      ports = [ 80 443 ];
      signatures = [
        { pattern = "backup"; offset = 0; }
        { pattern = "rsync"; offset = 0; }
      ];
    };
  };

  # DSCP value normalization function
  normalizeDscp =
    val:
    if builtins.isString val then
      (if builtins.hasAttr val dscpMap then dscpMap.${val} else builtins.toInt val)
    else
      val;

  # Parse schedule string
  parseSchedule =
    scheduleStr:
    let
      parts = lib.splitString " " scheduleStr;
      timePart = lib.findFirst (x: lib.hasInfix ":" x) null parts;
      dayPart = lib.findFirst (x: !lib.hasInfix ":" x) null parts;

      timeRule =
        if timePart != null then
          if lib.hasInfix "-" timePart then
            let
              times = lib.splitString "-" timePart;
              start = builtins.elemAt times 0;
              end = builtins.elemAt times 1;
            in
            "meta hour \"${start}\"-\"${end}\""
          else
            "meta hour \"${timePart}\""
        else
          "";

      dayRule =
        if dayPart != null then
          "meta day \"${dayPart}\""
        else
          "";
    in
    lib.concatStringsSep " " (
      lib.filter (x: x != "") [
        timeRule
        dayRule
      ]
    );

  # Enhanced application detection using deep packet inspection
  generateApplicationRules =
    className: classConf: classId:
    let
      applications = classConf.applications or [];
      appRules = lib.concatMap (app:
        if builtins.hasAttr app applicationSignatures then
          let
            appSig = applicationSignatures.${app};
            portRules = map (port: "tcp dport ${toString port}") appSig.ports;
            domainRules = if appSig ? domains then map (domain: "ip daddr ${domain}") appSig.domains else [];
            signatureRules = map (sig:
              "payload raw @${toString sig.offset} ${sig.pattern}"
            ) appSig.signatures;
          in
          portRules ++ domainRules ++ signatureRules
        else
          []
      ) applications;

      markRule = "meta mark set ${toString classId}";
      dscpVal = if classConf.dscp != null then normalizeDscp classConf.dscp else 0;
      dscpRule = if dscpVal != 0 then "ip dscp set ${toString dscpVal}" else "";
      action = "${markRule} ${dscpRule} counter";
    in
    map (match: "${match} ${action} comment \"App: ${className}\"") appRules;

  # Generate protocol-based rules (existing functionality)
  generateProtocolRules =
    className: classConf: classId:
    let
      protocols = classConf.protocols or [];
      protoRules = map (proto:
        if builtins.hasAttr proto protocolMap then
          let
            p = protocolMap.${proto};
          in
          if p ? portRange then
            "${p.proto} dport ${p.portRange}"
          else if p ? signature && p.signature != null then
            # Use signature-based matching for protocols with signatures
            if p.signature ? tls then
              "tcp dport ${toString p.dport} ct state established"
            else if p.signature ? method then
              "tcp dport ${toString p.dport} payload raw @0 \"${p.signature.method}\""
            else
              "${p.proto} dport ${toString p.dport}"
          else
            "${p.proto} dport ${toString p.dport}"
        else
          "meta l4proto ${proto}"
      ) protocols;

      markRule = "meta mark set ${toString classId}";
      dscpVal = if classConf.dscp != null then normalizeDscp classConf.dscp else 0;
      dscpRule = if dscpVal != 0 then "ip dscp set ${toString dscpVal}" else "";
      action = "${markRule} ${dscpRule} counter";
    in
    map (match: "${match} ${action} comment \"Proto: ${className}\"") protoRules;

  # Combined class rules (applications + protocols)
  generateClassRules =
    className: classConf: classId:
    let
      appRules = generateApplicationRules className classConf classId;
      protoRules = generateProtocolRules className classConf classId;
    in
    appRules ++ protoRules;

  # Enhanced policy rules with user and time-based matching
  generatePolicyRules =
    policyName: policy: classes:
    let
      scheduleMatch = if policy.schedule != null then parseSchedule policy.schedule else "";
    in
    lib.concatMap (rule:
      let
        targetClass = if classes ? ${rule.action.class} then classes.${rule.action.class} else null;
        classId = if targetClass != null then targetClass.id else 0;

        userMatch = if (rule.match.user or null) != null then
          if lib.hasPrefix "user:" rule.match.user then
            "meta skuid ${lib.removePrefix "user:" rule.match.user}"
          else
            "meta skuid ${rule.match.user}"
        else "";

        groupMatch = if (rule.match.group or null) != null then
          "meta skgid ${rule.match.group}"
        else "";

        appMatch = if (rule.match.application or null) != null then
          if builtins.hasAttr rule.match.application applicationSignatures then
            let
              appSig = applicationSignatures.${rule.match.application};
              portMatches = map (port: "tcp dport ${toString port}") appSig.ports;
              domainMatches = map (domain: "ip daddr ${domain}") appSig.domains;
            in
            lib.concatStringsSep " " (portMatches ++ domainMatches)
          else ""
        else "";

        timeMatch = scheduleMatch;

        matches = lib.concatStringsSep " " (
          lib.filter (x: x != "") [
            userMatch
            groupMatch
            appMatch
            timeMatch
          ]
        );

        markRule = "meta mark set ${toString classId}";
        action = "${markRule} counter comment \"Policy: ${policyName}\"";
      in
      if classId != 0 && matches != "" then
        [ "${matches} ${action}" ]
      else
        [ ]
    ) policy.rules;

  # HTB class generation (existing)
  generateHtbClass = tcCmd: iface: parentId: classId: leafHandle: rate: ceil: prio: ''
    ${tcCmd} class replace dev ${iface} parent ${parentId} classid ${classId} htb rate ${rate} ceil ${ceil} prio ${toString prio} quantum 1514
    ${tcCmd} qdisc replace dev ${iface} parent ${classId} handle ${toString leafHandle}: cake bandwidth ${ceil} diffserv4 split-gso
  '';

  # Deep packet inspection helpers
  generateDpiRules =
    className: classConf: classId:
    let
      dpiRules = lib.concatMap (app:
        if builtins.hasAttr app applicationSignatures then
          let
            appSig = applicationSignatures.${app};
          in
          map (sig: "payload raw @${toString sig.offset} \"${sig.pattern}\"") appSig.signatures
        else
          []
      ) (classConf.applications or []);

      markRule = "meta mark set ${toString classId}";
      action = "${markRule} counter comment \"DPI: ${className}\"";
    in
    map (match: "${match} ${action}") dpiRules;

in
{
  inherit dscpMap applicationSignatures normalizeDscp generateApplicationRules generateProtocolRules generateClassRules generatePolicyRules generateHtbClass generateDpiRules;
}
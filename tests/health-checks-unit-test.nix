# Pure-eval unit tests for the 5 implemented health check scripts in lib/health-checks.nix
#
# Strategy: generate the shell script text for each check type and assert that
# the expected commands and keywords appear in the output.  No VM required.
#
# Wire into flake.nix checks:
#   health-checks-unit-test = import ./tests/health-checks-unit-test.nix { inherit pkgs; inherit (nixpkgs) lib; };

{ pkgs, lib }:

let
  hc = import ../lib/health-checks.nix { inherit lib; };

  # ── helpers ──────────────────────────────────────────────────────────────────

  assertContains = label: needle: haystack:
    if lib.hasInfix needle haystack then null
    else throw "FAIL [${label}]: expected to find '${needle}' in generated script";

  assertNotContains = label: needle: haystack:
    if !(lib.hasInfix needle haystack) then null
    else throw "FAIL [${label}]: expected NOT to find '${needle}' in generated script";

  # ── generate scripts for each check under test ───────────────────────────────

  dhcpScript = hc.generateHealthCheckScript {
    type = "dhcp-server";
    interface = "eth1";
    poolUtilization = { poolSize = 150; threshold = "0.9"; };
    responseTime = { serverIp = "10.0.0.1"; clientIp = "10.0.0.100"; maxMs = 300; };
  };

  dhcpNoOptScript = hc.generateHealthCheckScript {
    type = "dhcp-server";
    interface = "eth0";
    # no poolUtilization or responseTime — those blocks must be absent
  };

  idsScript = hc.generateHealthCheckScript {
    type = "ids";
    process = "suricata";
    packetRate = { maxPps = 500000; };
    dropRate   = { maxPct = "0.005"; };
  };

  idsNoStatsScript = hc.generateHealthCheckScript {
    type = "ids";
    process = "suricata";
    # no packetRate or dropRate — those blocks must be absent
  };

  promScript = hc.generateHealthCheckScript {
    type = "metric";
    source = "prometheus";
    metric = "node_load1";
    operator = "lt";
    threshold = 2.0;
    prometheusUrl = "http://localhost:9090";
  };

  promGtScript = hc.generateHealthCheckScript {
    type = "metric";
    source = "prometheus";
    metric = "http_requests_total";
    operator = "gt";
    threshold = 1000;
  };

  # ── DHCP pool utilization checks ─────────────────────────────────────────────
  dhcpPoolChecks = [
    (assertContains "dhcp-pool/kea-ctrl-agent"   "kea-ctrl-agent"             dhcpScript)
    (assertContains "dhcp-pool/lease4-get-all"   "lease4-get-all"             dhcpScript)
    (assertContains "dhcp-pool/jq-state0"        "select(.state == 0)"        dhcpScript)
    (assertContains "dhcp-pool/pool-size"        "150"                        dhcpScript)
    (assertContains "dhcp-pool/threshold"        "0.9"                        dhcpScript)
    (assertContains "dhcp-pool/bc-fallback"      "awk"                        dhcpScript)
    (assertContains "dhcp-pool/warn-unreachable" "kea-ctrl-agent unreachable" dhcpScript)
    # absent when options not set
    (assertNotContains "dhcp-pool/absent"        "kea-ctrl-agent"             dhcpNoOptScript)
  ];

  # ── DHCP response time checks ────────────────────────────────────────────────
  dhcpRtChecks = [
    (assertContains "dhcp-rt/dhcping"            "dhcping"                    dhcpScript)
    (assertContains "dhcp-rt/server-ip"          "10.0.0.1"                   dhcpScript)
    (assertContains "dhcp-rt/client-ip"          "10.0.0.100"                 dhcpScript)
    (assertContains "dhcp-rt/max-ms"             "300"                        dhcpScript)
    (assertContains "dhcp-rt/date-ms"            "date +%s%3N"                dhcpScript)
    (assertContains "dhcp-rt/no-discover"        "did not respond to DISCOVER" dhcpScript)
    # absent when options not set
    (assertNotContains "dhcp-rt/absent"          "dhcping"                    dhcpNoOptScript)
  ];

  # ── IDS packet-rate checks ───────────────────────────────────────────────────
  idsPktChecks = [
    (assertContains "ids-pkt/suricatasc"         "suricatasc"                 idsScript)
    (assertContains "ids-pkt/socket-path"        "suricata-command.socket"    idsScript)
    (assertContains "ids-pkt/dump-counters"      "dump-counters"              idsScript)
    (assertContains "ids-pkt/kernel-packets"     "kernel_packets"             idsScript)
    (assertContains "ids-pkt/max-pps"            "500000"                     idsScript)
    (assertContains "ids-pkt/warn-no-socket"     "socket not found"           idsScript)
    # absent when option not set
    (assertNotContains "ids-pkt/absent-pkt"      "kernel_packets"             idsNoStatsScript)
  ];

  # ── IDS drop-rate checks ──────────────────────────────────────────────────────
  idsDropChecks = [
    (assertContains "ids-drop/kernel-drops"      "kernel_drops"               idsScript)
    (assertContains "ids-drop/max-pct"           "0.005"                      idsScript)
    (assertContains "ids-drop/ratio-calc"        "drops / $_pkts"             idsScript)
    (assertContains "ids-drop/zero-guard"        "packet count is 0"          idsScript)
    # absent when option not set
    (assertNotContains "ids-drop/absent"         "kernel_drops"               idsNoStatsScript)
  ];

  # ── Prometheus metric checks ──────────────────────────────────────────────────
  promChecks = [
    (assertContains "prom/api-query"             "api/v1/query"               promScript)
    (assertContains "prom/metric-name"           "node_load1"                 promScript)
    (assertContains "prom/jq-value"              ".data.result[0].value[1]"   promScript)
    (assertContains "prom/warn-unreachable"      "is unreachable"             promScript)
    (assertContains "prom/warn-no-data"          "returned no data"           promScript)
    (assertContains "prom/lt-operator"           "lt"                         promScript)
    (assertContains "prom/threshold"             "2"                          promScript)
    (assertContains "prom/prom-url"              "http://localhost:9090"      promScript)
    # gt operator variant
    (assertContains "prom/gt-operator"           "gt"                         promGtScript)
    (assertContains "prom/gt-metric"             "http_requests_total"        promGtScript)
    (assertContains "prom/gt-threshold"          "1000"                       promGtScript)
  ];

  allChecks =
    dhcpPoolChecks
    ++ dhcpRtChecks
    ++ idsPktChecks
    ++ idsDropChecks
    ++ promChecks;

  totalChecks = builtins.length allChecks;
  passed = builtins.length (builtins.filter (x: x == null) allChecks);
  allPassed = passed == totalChecks;

in
pkgs.runCommand "health-checks-unit-test" { } ''
  ${if allPassed
    then "echo 'All health-check unit tests passed (${toString totalChecks} checks)' > $out"
    else throw "One or more health-check unit tests failed"}
''

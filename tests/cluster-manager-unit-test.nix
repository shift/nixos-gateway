# Pure-eval unit tests for the 7 implemented cluster-manager HA stubs
# in lib/cluster-manager.nix.
#
# Strategy: generate the bash script text for each generator and assert
# that expected commands and keywords appear (or are absent).  No VM needed.
#
# Wire into flake.nix checks:
#   cluster-manager-unit-test = import ./tests/cluster-manager-unit-test.nix {
#     inherit pkgs; inherit (nixpkgs) lib;
#   };

{ pkgs, lib }:

let
  cm = (import ../lib/cluster-manager.nix { inherit lib pkgs; }).utils;

  # ── helpers ──────────────────────────────────────────────────────────────────

  assertContains = label: needle: haystack:
    if lib.hasInfix needle haystack then null
    else throw "FAIL [${label}]: expected '${needle}' in generated script";

  assertNotContains = label: needle: haystack:
    if !(lib.hasInfix needle haystack) then null
    else throw "FAIL [${label}]: expected NOT to find '${needle}' in generated script";

  assertTrue = label: cond:
    if cond then null
    else throw "FAIL [${label}]: expected true";

  # ── fixtures ─────────────────────────────────────────────────────────────────

  clusterCfg = {
    name = "test-cluster";
    vip  = "10.0.0.100";
    interface = "eth0";
  };

  lbCfg = {
    algorithm = "round-robin";
    virtualServices = [
      {
        name      = "web";
        virtualIp = "10.0.0.100";
        port      = 80;
        protocol  = "tcp";
        realServers = [
          { address = "10.0.0.10"; port = 80; weight = 1; }
          { address = "10.0.0.11"; port = 80; weight = 1; }
        ];
      }
    ];
  };

  failCfg = {
    primaryHost = "10.0.0.1";
    virtualIp   = "10.0.0.100";
    interface   = "eth0";
    dataDir     = "/var/lib/postgresql/dns/data";
  };

  commScript   = cm.generateClusterCommunicationScript clusterCfg;
  lbScript     = cm.generateLoadBalancerConfig lbCfg;
  failScript   = cm.generateServiceFailoverScript "dns" failCfg;

  # ── Stub 3: cluster communication (keepalived SIGUSR1/SIGUSR2) ───────────────
  commChecks = [
    (assertContains "comm/sigusr2"          "SIGUSR2"                    commScript)
    (assertContains "comm/sigusr1"          "SIGUSR1"                    commScript)
    (assertContains "comm/keepalived-pid"   "keepalived.pid"             commScript)
    (assertContains "comm/vrrp-state-file"  "vrrp-state"                 commScript)
    (assertContains "comm/notify-script"    "keepalived-notify.sh"       commScript)
    (assertContains "comm/chmod"            "chmod +x"                   commScript)
    (assertContains "comm/ready-sentinel"   "comm-ready"                 commScript)
    (assertContains "comm/master-case"      "MASTER"                     commScript)
    (assertContains "comm/backup-case"      "BACKUP"                     commScript)
    (assertContains "comm/cluster-name"     "test-cluster"               commScript)
  ];

  # ── Stub 4: HAProxy load balancer reload ─────────────────────────────────────
  lbChecks = [
    (assertContains "lb/socat"              "socat"                      lbScript)
    (assertContains "lb/admin-sock"         "admin.sock"                 lbScript)
    (assertContains "lb/haproxy-cfg"        "haproxy.cfg"                lbScript)
    (assertContains "lb/haproxy-pid"        "haproxy.pid"                lbScript)
    (assertContains "lb/reload-cmd"         "reload"                     lbScript)
    (assertContains "lb/fallback-sf"        "-sf"                        lbScript)
    (assertContains "lb/fallback-systemctl" "systemctl restart haproxy"  lbScript)
    (assertContains "lb/backend-server1"    "10.0.0.10"                  lbScript)
    (assertContains "lb/backend-server2"    "10.0.0.11"                  lbScript)
    (assertContains "lb/frontend"           "frontend"                   lbScript)
    (assertContains "lb/backend"            "backend"                    lbScript)
    (assertContains "lb/balance-algo"       "roundrobin"                 lbScript)
    (assertContains "lb/mkdir-run"          "mkdir -p /run/haproxy"      lbScript)
  ];

  # ── Stubs 5, 6, 7: service failover ──────────────────────────────────────────
  failChecks = [
    # Stub 5 — VIP remove / VRRP demotion
    (assertContains "fail/sigusr1"          "SIGUSR1"                    failScript)
    (assertContains "fail/vrrp-state"       "vrrp-state"                 failScript)
    (assertContains "fail/backup-confirm"   "BACKUP"                     failScript)
    (assertContains "fail/keepalived-pid"   "keepalived.pid"             failScript)
    # Stub 6 — PostgreSQL promotion
    (assertContains "fail/pg-promote"       "pg_ctl promote"             failScript)
    (assertContains "fail/standby-signal"   "standby.signal"             failScript)
    (assertContains "fail/pg-rewind"        "pg_rewind"                  failScript)
    (assertContains "fail/primary-host"     "10.0.0.1"                   failScript)
    (assertContains "fail/data-dir"         "/var/lib/postgresql/dns"    failScript)
    # Stub 7 — VIP add / VRRP promotion
    (assertContains "fail/sigusr2"          "SIGUSR2"                    failScript)
    (assertContains "fail/arping"           "arping"                     failScript)
    (assertContains "fail/arping-U"         "arping -U"                  failScript)
    (assertContains "fail/vip-addr"         "10.0.0.100"                 failScript)
    (assertContains "fail/iface"            "eth0"                       failScript)
    # Service name interpolated correctly
    (assertContains "fail/service-name"     "dns"                        failScript)
  ];

  # ── Aggregate ─────────────────────────────────────────────────────────────────

  allChecks =
    commChecks
    ++ lbChecks
    ++ failChecks;

  totalChecks = builtins.length allChecks;
  passed      = builtins.length (builtins.filter (x: x == null) allChecks);
  allPassed   = passed == totalChecks;

in
pkgs.runCommand "cluster-manager-unit-test" { } ''
  ${if allPassed
    then "echo 'All cluster-manager unit tests passed (${toString totalChecks} checks)' > $out"
    else throw "One or more cluster-manager unit tests failed"}
''

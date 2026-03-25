# Pure-eval unit tests for lib/validators.nix
#
# This is a pkgs.runCommand derivation (no VM required).  It evaluates every
# validator with known-good and known-bad inputs and asserts the expected
# boolean result.  The build succeeds iff every assertion holds.
#
# Wire up in flake.nix checks:
#   validators-unit-test = import ./tests/validators-unit-test.nix { inherit pkgs; inherit (nixpkgs) lib; };

{ pkgs, lib }:

let
  v = import ../lib/validators.nix { inherit lib; };

  # assert that `expr` is `true`; tag with `label` for readable errors
  check = label: expr:
    if expr == true then null
    else throw "FAIL [${label}]: expected true, got ${builtins.toJSON expr}";

  # assert that `expr` is `false`
  checkNot = label: expr:
    if expr == false then null
    else throw "FAIL [${label}]: expected false, got ${builtins.toJSON expr}";

  results = [
    # ── validateIPAddress ──────────────────────────────────────────────────────
    (check    "ip/valid-private"     (v.validateIPAddress "192.168.1.1"))
    (check    "ip/valid-0"          (v.validateIPAddress "0.0.0.0"))
    (check    "ip/valid-255"        (v.validateIPAddress "255.255.255.255"))
    (checkNot "ip/octet-too-large"  (v.validateIPAddress "256.0.0.1"))
    (checkNot "ip/missing-octet"    (v.validateIPAddress "192.168.1"))
    (checkNot "ip/empty"            (v.validateIPAddress ""))

    # ── validateMACAddress ─────────────────────────────────────────────────────
    (check    "mac/colon"           (v.validateMACAddress "aa:bb:cc:dd:ee:ff"))
    (check    "mac/hyphen"          (v.validateMACAddress "AA-BB-CC-DD-EE-FF"))
    (checkNot "mac/too-short"       (v.validateMACAddress "aa:bb:cc"))
    (checkNot "mac/bad-chars"       (v.validateMACAddress "zz:zz:zz:zz:zz:zz"))

    # ── validateCIDR ───────────────────────────────────────────────────────────
    (check    "cidr/host"           (v.validateCIDR "10.0.0.1/32"))
    (check    "cidr/network"        (v.validateCIDR "10.0.0.0/8"))
    (check    "cidr/slash0"         (v.validateCIDR "0.0.0.0/0"))
    (checkNot "cidr/prefix-too-big" (v.validateCIDR "10.0.0.0/33"))
    (checkNot "cidr/no-slash"       (v.validateCIDR "10.0.0.0"))

    # ── validatePort ───────────────────────────────────────────────────────────
    (check    "port/1"              (v.validatePort 1))
    (check    "port/443"            (v.validatePort 443))
    (check    "port/65535"          (v.validatePort 65535))
    (checkNot "port/0"              (v.validatePort 0))
    (checkNot "port/65536"          (v.validatePort 65536))

    # ── validateBGPASN ─────────────────────────────────────────────────────────
    (check    "bgp-asn/private"     (v.validateBGPASN 65001))
    (check    "bgp-asn/public"      (v.validateBGPASN 15169))        # Google
    (check    "bgp-asn/4byte-max"   (v.validateBGPASN 4294967295))
    (check    "bgp-asn/min"         (v.validateBGPASN 1))
    (checkNot "bgp-asn/zero"        (v.validateBGPASN 0))
    (checkNot "bgp-asn/overflow"    (v.validateBGPASN 4294967296))
    (checkNot "bgp-asn/string"      (v.validateBGPASN "65001"))

    # ── validateBGPRouterId ────────────────────────────────────────────────────
    (check    "bgp-rid/valid"       (v.validateBGPRouterId "10.0.0.1"))
    (checkNot "bgp-rid/invalid"     (v.validateBGPRouterId "not-an-ip"))

    # ── validateBGPCommunity ───────────────────────────────────────────────────
    (check    "bgp-comm/standard"   (v.validateBGPCommunity "65000:100"))
    (checkNot "bgp-comm/bad"        (v.validateBGPCommunity "65000-100"))
    (checkNot "bgp-comm/triple"     (v.validateBGPCommunity "1:2:3"))    # that's large-community

    # ── validateBPGLargeCommunity ──────────────────────────────────────────────
    (check    "bgp-lc/valid"        (v.validateBPGLargeCommunity "65000:1:2"))
    (checkNot "bgp-lc/standard"     (v.validateBPGLargeCommunity "65000:1"))  # only 2 parts
    (checkNot "bgp-lc/bad"          (v.validateBPGLargeCommunity "nope"))

    # ── validateBGPNeighbor ────────────────────────────────────────────────────
    (check    "bgp-nbr/full"        (v.validateBGPNeighbor { address = "10.0.0.2"; asn = 65002; }))
    (check    "bgp-nbr/empty"       (v.validateBGPNeighbor { }))           # all fields optional
    (checkNot "bgp-nbr/bad-ip"      (v.validateBGPNeighbor { address = "bad"; }))
    (checkNot "bgp-nbr/bad-asn"     (v.validateBGPNeighbor { asn = 0; }))

    # ── validateBGPPrefixList ──────────────────────────────────────────────────
    (check    "bgp-pl/valid"        (v.validateBGPPrefixList [
                                      { network = "10.0.0.0/8"; action = "permit"; }
                                      { network = "172.16.0.0/12"; action = "deny"; }
                                    ]))
    (check    "bgp-pl/empty"        (v.validateBGPPrefixList []))
    (checkNot "bgp-pl/bad-action"   (v.validateBGPPrefixList [{ network = "10.0.0.0/8"; action = "ALLOW"; }]))
    (checkNot "bgp-pl/bad-cidr"     (v.validateBGPPrefixList [{ network = "bad"; action = "permit"; }]))
    (checkNot "bgp-pl/no-action"    (v.validateBGPPrefixList [{ network = "10.0.0.0/8"; }]))

    # ── validateBGPRouteMap ────────────────────────────────────────────────────
    (check    "bgp-rm/valid"        (v.validateBGPRouteMap [{ action = "permit"; }]))
    (check    "bgp-rm/empty"        (v.validateBGPRouteMap []))
    (checkNot "bgp-rm/bad-action"   (v.validateBGPRouteMap [{ action = "forward"; }]))

    # ── validateBGPConfig ──────────────────────────────────────────────────────
    (check    "bgp-cfg/full"        (v.validateBGPConfig { asn = 65001; routerId = "10.0.0.1"; }))
    (check    "bgp-cfg/empty"       (v.validateBGPConfig { }))
    (checkNot "bgp-cfg/bad-asn"     (v.validateBGPConfig { asn = 0; }))
    (checkNot "bgp-cfg/bad-rid"     (v.validateBGPConfig { routerId = "not-ip"; }))

    # ── validateFirewallRule ───────────────────────────────────────────────────
    (check    "fw/accept-tcp"       (v.validateFirewallRule { action = "accept"; protocol = "tcp"; }))
    (check    "fw/drop-no-proto"    (v.validateFirewallRule { action = "drop"; }))
    (check    "fw/reject-all"       (v.validateFirewallRule { action = "reject"; protocol = "all"; }))
    (checkNot "fw/bad-action"       (v.validateFirewallRule { action = "ALLOW"; }))
    (checkNot "fw/bad-protocol"     (v.validateFirewallRule { action = "accept"; protocol = "sctp"; }))
    (checkNot "fw/no-action"        (v.validateFirewallRule { protocol = "tcp"; }))

    # ── validateDHCPConfig ─────────────────────────────────────────────────────
    (check    "dhcp/full"           (v.validateDHCPConfig { subnet = "192.168.1.0/24"; gateway = "192.168.1.1"; }))
    (check    "dhcp/empty"          (v.validateDHCPConfig { }))
    (checkNot "dhcp/bad-subnet"     (v.validateDHCPConfig { subnet = "not-a-cidr"; }))
    (checkNot "dhcp/bad-gw"         (v.validateDHCPConfig { gateway = "not-an-ip"; }))

    # ── validateIDSConfig ──────────────────────────────────────────────────────
    (check    "ids/low"             (v.validateIDSConfig { profile = "low"; }))
    (check    "ids/high"            (v.validateIDSConfig { profile = "high"; }))
    (check    "ids/no-profile"      (v.validateIDSConfig { }))
    (checkNot "ids/unknown"         (v.validateIDSConfig { profile = "extreme"; }))

    # ── validateHost ───────────────────────────────────────────────────────────
    (check    "host/full"           (v.validateHost { name = "laptop"; macAddress = "aa:bb:cc:dd:ee:ff"; ipAddress = "10.0.0.5"; }))
    (check    "host/name-only"      (v.validateHost { name = "server"; }))
    (checkNot "host/no-name"        (v.validateHost { macAddress = "aa:bb:cc:dd:ee:ff"; }))
    (checkNot "host/bad-mac"        (v.validateHost { name = "x"; macAddress = "not-a-mac"; }))
    (checkNot "host/bad-ip"         (v.validateHost { name = "x"; ipAddress = "999.0.0.1"; }))

    # ── validateSubnet ─────────────────────────────────────────────────────────
    (check    "subnet/full"         (v.validateSubnet { cidr = "10.0.0.0/24"; gateway = "10.0.0.1"; }))
    (check    "subnet/empty"        (v.validateSubnet { }))
    (checkNot "subnet/bad-cidr"     (v.validateSubnet { cidr = "bad"; }))
    (checkNot "subnet/bad-gw"       (v.validateSubnet { gateway = "bad"; }))

    # ── validateNetwork ────────────────────────────────────────────────────────
    (check    "net/no-subnets"      (v.validateNetwork { }))
    (check    "net/valid-subnets"   (v.validateNetwork {
                                      subnets = {
                                        lan = { cidr = "192.168.1.0/24"; gateway = "192.168.1.1"; };
                                        mgmt = { cidr = "10.0.0.0/24"; gateway = "10.0.0.1"; };
                                      };
                                    }))
    (checkNot "net/bad-subnet"      (v.validateNetwork {
                                      subnets = { bad = { cidr = "nope"; }; };
                                    }))

    # ── validateHosts ──────────────────────────────────────────────────────────
    (check    "hosts/valid-list"    (v.validateHosts [{ name = "a"; } { name = "b"; }]))
    (check    "hosts/empty"         (v.validateHosts []))
    (checkNot "hosts/bad-entry"     (v.validateHosts [{ macAddress = "bad"; }]))  # missing name
    (checkNot "hosts/not-a-list"    (v.validateHosts { name = "x"; }))

    # ── validateGatewayData ────────────────────────────────────────────────────
    (check    "gd/empty"            (v.validateGatewayData { }))
    (check    "gd/full-valid"       (v.validateGatewayData {
                                      network = { subnets = { lan = { cidr = "192.168.1.0/24"; gateway = "192.168.1.1"; }; }; };
                                      hosts   = { staticDHCPv4Assignments = [{ name = "laptop"; }]; };
                                      firewall = { rules = [{ action = "accept"; }]; };
                                    }))
    (checkNot "gd/bad-fw-rule"      (v.validateGatewayData {
                                      firewall = { rules = [{ action = "BADACTION"; }]; };
                                    }))
    (checkNot "gd/bad-host"         (v.validateGatewayData {
                                      hosts = { staticDHCPv4Assignments = [{ ipAddress = "bad"; }]; };
                                    }))

    # ── fileExists ─────────────────────────────────────────────────────────────
    (check    "file/always-true"    (v.fileExists "/var/lib/something"))

    # ── base64Key ──────────────────────────────────────────────────────────────
    (check    "b64/valid"           (v.base64Key "AAAAAAAAAAAAAAAAAAAAAA=="))
    (check    "b64/no-padding"      (v.base64Key "ABCDEFGHIJKLMNOPabcdef"))
    (checkNot "b64/too-short"       (v.base64Key "abc=="))
    (checkNot "b64/bad-chars"       (v.base64Key "!!!invalid!!!!!!!!!!!!"))

    # ── nonEmptyString ─────────────────────────────────────────────────────────
    (check    "ne/hello"            (v.nonEmptyString "hello"))
    (checkNot "ne/empty"            (v.nonEmptyString ""))
    (checkNot "ne/not-string"       (v.nonEmptyString 42))
  ];

  # Evaluate all checks; any throw above will propagate as a build failure
  allPassed = builtins.length (builtins.filter (x: x == null) results) == builtins.length results;

in
pkgs.runCommand "validators-unit-test" { } ''
  ${if allPassed
    then "echo 'All validator unit tests passed (${toString (builtins.length results)} checks)' > $out"
    else throw "One or more validator unit tests failed"}
''

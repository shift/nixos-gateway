# Pure-eval unit tests for generateConfigDiff in lib/config-reload.nix
#
# Tests all four logical branches:
#   1. Identical configs, no configFiles       → changed=false, no files field
#   2. Identical configs, has configFiles      → changed=false, files field present
#   3. Different configs, known service        → changed=true,  files field present
#   4. Different configs, unknown service      → changed=true,  graceful fallback
#   5. Message contains 8-char hash prefix     → changed=true case
#   6. Hash is deterministic (attr order)      → key-order-insensitive
#
# Wire into flake.nix checks:
#   config-reload-unit-test = import ./tests/config-reload-unit-test.nix {
#     inherit pkgs; inherit (nixpkgs) lib;
#   };

{ pkgs, lib }:

let
  cr = import ../lib/config-reload.nix { inherit lib pkgs; };
  diff = cr.generateConfigDiff;

  # ── helpers ──────────────────────────────────────────────────────────────────

  assertTrue = label: cond:
    if cond then null
    else throw "FAIL [${label}]: expected true";

  assertFalse = label: cond:
    if !cond then null
    else throw "FAIL [${label}]: expected false";

  assertContains = label: needle: haystack:
    if lib.hasInfix needle haystack then null
    else throw "FAIL [${label}]: expected '${needle}' in '${haystack}'";

  assertHasAttr = label: attr: attrset:
    if attrset ? ${attr} then null
    else throw "FAIL [${label}]: expected attribute '${attr}' to be present";

  assertNoAttr = label: attr: attrset:
    if !(attrset ? ${attr}) then null
    else throw "FAIL [${label}]: expected attribute '${attr}' to be absent";

  # ── fixtures ─────────────────────────────────────────────────────────────────

  cfgA = { port = 53; upstream = "8.8.8.8"; zones = [ "example.com" ]; };
  cfgB = { port = 53; upstream = "1.1.1.1"; zones = [ "example.com" ]; };

  # "network" has configFiles = [] in reloadCapabilities
  # "dns"     has configFiles = ["/etc/knot/knotd.conf" ...]
  # "unknown" is not in reloadCapabilities at all

  # ── branch 1: identical + no configFiles (network service) ───────────────────
  b1 = diff cfgA cfgA "network";
  branch1Checks = [
    (assertFalse  "b1/changed"      b1.changed)
    (assertNoAttr "b1/no-files"     "files" b1)
    (assertContains "b1/msg-identical" "identical" b1.message)
    (assertContains "b1/msg-service"   "network"   b1.message)
  ];

  # ── branch 2: identical + has configFiles (dns service) ──────────────────────
  b2 = diff cfgA cfgA "dns";
  branch2Checks = [
    (assertFalse  "b2/changed"         b2.changed)
    (assertHasAttr "b2/has-files"      "files" b2)
    (assertTrue   "b2/files-nonempty"  (builtins.length b2.files > 0))
    (assertContains "b2/msg-unchanged"  "unchanged" b2.message)
    (assertContains "b2/msg-hash"       "hash:"     b2.message)
    (assertContains "b2/msg-service"    "dns"        b2.message)
  ];

  # ── branch 3: different configs, known service (dns) ─────────────────────────
  b3 = diff cfgA cfgB "dns";
  branch3Checks = [
    (assertTrue   "b3/changed"         b3.changed)
    (assertHasAttr "b3/has-files"      "files" b3)
    (assertTrue   "b3/files-nonempty"  (builtins.length b3.files > 0))
    (assertContains "b3/msg-changed"    "changed"   b3.message)
    (assertContains "b3/msg-arrow"      "→"         b3.message)
    (assertContains "b3/msg-service"    "dns"        b3.message)
  ];

  # ── branch 4: different configs, unknown service (graceful fallback) ──────────
  b4 = diff cfgA cfgB "nonexistent-service";
  branch4Checks = [
    # unknown service → or { configFiles = []; } → no configFiles → falls into
    # the "else" (changed=true) branch because configs differ
    (assertTrue   "b4/changed"         b4.changed)
    (assertContains "b4/msg-nonexistent" "nonexistent-service" b4.message)
  ];

  # ── branch 5: hash prefix is 8 chars and appears in changed message ─────────
  # Verify by computing the hash ourselves and checking the first 8 chars appear
  # in the changed message.  builtins.hashString is deterministic.
  b5OldHash = builtins.substring 0 8
    (builtins.hashString "sha256" (builtins.toJSON cfgA));
  b5NewHash = builtins.substring 0 8
    (builtins.hashString "sha256" (builtins.toJSON cfgB));
  b5 = diff cfgA cfgB "dns";
  branch5Checks = [
    (assertContains "b5/old-hash-in-msg" b5OldHash b5.message)
    (assertContains "b5/new-hash-in-msg" b5NewHash b5.message)
    (assertTrue     "b5/old-hash-8chars" (builtins.stringLength b5OldHash == 8))
    (assertTrue     "b5/new-hash-8chars" (builtins.stringLength b5NewHash == 8))
  ];

  # ── branch 6: hash is key-order-insensitive ───────────────────────────────────
  # Two attrsets with identical content but different syntactic key order must
  # produce changed=false (builtins.toJSON sorts keys lexicographically).
  cfgX1 = { a = 1; b = 2; c = 3; };
  cfgX2 = { c = 3; a = 1; b = 2; };  # same content, different order
  b6 = diff cfgX1 cfgX2 "network";
  branch6Checks = [
    (assertFalse "b6/order-insensitive" b6.changed)
  ];

  # ── aggregate ─────────────────────────────────────────────────────────────────
  allChecks =
    branch1Checks
    ++ branch2Checks
    ++ branch3Checks
    ++ branch4Checks
    ++ branch5Checks
    ++ branch6Checks;

  totalChecks = builtins.length allChecks;
  passed      = builtins.length (builtins.filter (x: x == null) allChecks);
  allPassed   = passed == totalChecks;

in
pkgs.runCommand "config-reload-unit-test" { } ''
  ${if allPassed
    then "echo 'All config-reload unit tests passed (${toString totalChecks} checks)' > $out"
    else throw "One or more config-reload unit tests failed"}
''

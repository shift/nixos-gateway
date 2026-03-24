{ lib }:

{
  # Generate a standard site tag based on site name
  mkSiteTag = siteName: "tag:site-${siteName}";

  # Process subnet routers configuration
  # Returns a list of routes to advertise
  getAdvertiseRoutes =
    subnetRouters:
    let
      enabledRouters = lib.filter (r: r.advertise) subnetRouters;
    in
    map (r: r.subnet) enabledRouters;

  # Check if any router is an exit node
  hasExitNode = subnetRouters: lib.any (r: r.exitNode) subnetRouters;

  # Generate ACL policies (JSON structure to be used with Tailscale ACLs)
  # This is a helper to generate the structure, actual application might depend on
  # how the user manages ACLs (GitOps vs direct API)
  generateAclPolicy =
    {
      siteName,
      aclPolicies,
      peerSites,
    }:
    let
      # Define groups
      groups = aclPolicies.groups or { };

      # Define ACLs
      acls = aclPolicies.acls or [ ];

      # Define tag owners - critical for automated tagging
      tagOwners = {
        "tag:site-${siteName}" = [ "autogroup:admin" ];
      }
      // (lib.genAttrs (map (p: "tag:site-${p.name}") peerSites) (_: [ "autogroup:admin" ]));

      # Auto-generated rules for site-to-site trust
      trustedPeerRules = lib.concatMap (
        peer:
        if peer.trustLevel == "full" then
          [
            {
              action = "accept";
              src = [ "tag:site-${siteName}" ];
              dst = [ "tag:site-${peer.name}:*" ];
            }
            {
              action = "accept";
              src = [ "tag:site-${peer.name}" ];
              dst = [ "tag:site-${siteName}:*" ];
            }
          ]
        else
          [ ]
      ) peerSites;

    in
    {
      inherit groups tagOwners;
      acls = acls ++ trustedPeerRules;
    };

  # Helper to validate CIDR format
  isValidCidr =
    cidr:
    let
      parts = lib.splitString "/" cidr;
    in
    builtins.length parts == 2 && (builtins.isInt (builtins.fromJSON (builtins.elemAt parts 1)));
}

{ lib }:

let
  inherit (lib) mkOption types;

  # Generate PeerAuthentication policies
  generatePeerAuthentication =
    policies:
    map (policy: {
      apiVersion = "security.istio.io/v1beta1";
      kind = "PeerAuthentication";
      metadata = {
        name = policy.name;
        namespace = "default";
      };
      spec = {
        selector = policy.selector;
        mtls = {
          mode = policy.mtls;
        };
      };
    }) policies;

  # Generate AuthorizationPolicy resources
  generateAuthorizationPolicies =
    policies:
    map (policy: {
      apiVersion = "security.istio.io/v1beta1";
      kind = "AuthorizationPolicy";
      metadata = {
        name = policy.name;
        namespace = "default";
      };
      spec = {
        selector = policy.selector;
        action = policy.action;
        rules = policy.rules;
      };
    }) policies;

  # Generate RequestAuthentication policies
  generateRequestAuthentication =
    policies:
    map (policy: {
      apiVersion = "security.istio.io/v1beta1";
      kind = "RequestAuthentication";
      metadata = {
        name = policy.name;
        namespace = "default";
      };
      spec = {
        selector = policy.selector;
        jwtRules = policy.jwtRules or [ ];
      };
    }) policies;

  # Generate comprehensive security policies
  generateSecurityPolicies =
    securityCfg:
    let
      peerAuth = generatePeerAuthentication securityCfg.peerAuthentication;
      authPolicies = generateAuthorizationPolicies securityCfg.authorizationPolicies;
      requestAuth = generateRequestAuthentication (securityCfg.requestAuthentication or [ ]);
    in
    {
      "peer-authentication.yaml" = builtins.toJSON peerAuth;
      "authorization-policies.yaml" = builtins.toJSON authPolicies;
      "request-authentication.yaml" = builtins.toJSON requestAuth;
    };

  # Helper functions for creating common policies
  mkDefaultPeerAuth =
    {
      name,
      namespace ? "default",
    }:
    {
      apiVersion = "security.istio.io/v1beta1";
      kind = "PeerAuthentication";
      metadata = {
        name = name;
        namespace = namespace;
      };
      spec = {
        mtls = {
          mode = "STRICT";
        };
      };
    };

  mkServiceAuthPolicy =
    {
      name,
      service,
      namespace ? "default",
      principals,
    }:
    {
      apiVersion = "security.istio.io/v1beta1";
      kind = "AuthorizationPolicy";
      metadata = {
        name = name;
        namespace = namespace;
      };
      spec = {
        selector = {
          matchLabels = {
            app = service;
          };
        };
        action = "ALLOW";
        rules = [
          {
            from = [
              {
                source = {
                  principals = principals;
                };
              }
            ];
          }
        ];
      };
    };

  mkJWTPolicy =
    {
      name,
      issuer,
      jwksUri,
      namespace ? "default",
    }:
    {
      apiVersion = "security.istio.io/v1beta1";
      kind = "RequestAuthentication";
      metadata = {
        name = name;
        namespace = namespace;
      };
      spec = {
        jwtRules = [
          {
            issuer = issuer;
            jwksUri = jwksUri;
          }
        ];
      };
    };

in
{
  inherit
    generatePeerAuthentication
    generateAuthorizationPolicies
    generateRequestAuthentication
    generateSecurityPolicies
    mkDefaultPeerAuth
    mkServiceAuthPolicy
    mkJWTPolicy
    ;
}

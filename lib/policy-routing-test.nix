{ lib ? import <nixpkgs/lib> }:

let
  policyLib = import ./policy-routing.nix { inherit lib; };
  
  # Mock rule with time
  complexRule = {
    name = "complex-rule";
    enabled = true;
    match = {
      sourceAddress = "192.168.1.10";
      time = "08:00-17:00"; # This is the new field we want to support
      destinationPort = 80;
    };
    action = {
      action = "route";
      table = "custom";
      priority = 1000;
    };
  };

  # Mock simple rule
  simpleRule = {
    name = "simple-rule";
    enabled = true;
    match = {
      sourceAddress = "192.168.1.10";
      destinationPort = 80;
    };
    action = {
      action = "route";
      table = "custom";
      priority = 1000;
    };
  };

in
{
  # We expect validatePolicyRule to fail initially because 'time' isn't in the check list yet
  # But we want to see what happens when we add it.
  
  # check complex rule
  isComplex = if builtins.hasAttr "time" complexRule.match && complexRule.match.time != null then true else false;
  
  # We will test the functions we add here
}

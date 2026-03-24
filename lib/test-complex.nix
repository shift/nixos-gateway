{ lib ? import <nixpkgs/lib> }:

let
  policyLib = import ./policy-routing.nix { inherit lib; };
  
  complexRule = {
    name = "complex-rule";
    enabled = true;
    match = {
      sourceAddress = "192.168.1.10";
      time = "08:00-17:00"; 
      destinationPort = 80;
    };
    action = {
      action = "route";
      table = "custom";
      priority = 1000;
    };
  };

  simpleRule = {
    name = "simple-rule";
    enabled = true;
    match = {
      sourceAddress = "192.168.1.10";
      destinationPort = 80;
      fwmark = null;
    };
    action = {
      action = "route";
      table = "custom";
      priority = 1000;
    };
  };

in
{
  isComplex = policyLib.isComplexRule complexRule;
  nftRule = policyLib.generateNftablesRule complexRule 1;
  ipRuleComplex = policyLib.generateIpRule complexRule 1;
  ipRuleSimple = policyLib.generateIpRule simpleRule 2;
}

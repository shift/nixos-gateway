{ lib, pkgs, ... }:

let
  inherit (lib) mkOption types;

  # Create a VRF interface configuration
  mkVrfDevice = name: table: {
    enable = true;
    netdevConfig = {
      Kind = "vrf";
      Name = name;
    };
    vrfConfig = {
      Table = table;
    };
  };

  # Create an interface assignment to a VRF
  mkVrfMember = interface: vrf: {
    networkConfig = {
      VRF = vrf;
    };
  };

  # Generate systemd-networkd config for a VRF
  mkNetworkdConfig =
    vrfName: vrfConfig:
    {
      "10-vrf-${vrfName}" = mkVrfDevice vrfName vrfConfig.table;
    }
    // (lib.listToAttrs (
      map (iface: {
        name = "20-vrf-member-${iface}";
        value = {
          matchConfig.Name = iface;
          networkConfig.VRF = vrfName;
        };
      }) vrfConfig.interfaces
    ));

  # Validate VRF configuration
  validateVrfConfig =
    vrfs:
    let
      tables = map (v: v.table) (lib.attrValues vrfs);
      uniqueTables = lib.unique tables;
    in
    if (builtins.length tables) != (builtins.length uniqueTables) then
      throw "VRF routing table IDs must be unique across all VRFs"
    else
      true;
in
{
  inherit
    mkVrfDevice
    mkVrfMember
    mkNetworkdConfig
    validateVrfConfig
    ;
}

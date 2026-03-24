{ lib, pkgs, ... }:

let
  inherit (lib) mkOption types;

  # Transit Gateway configuration validation
  validateTransitGatewayConfig =
    gateways:
    let
      names = map (g: g.name) gateways;
      uniqueNames = lib.unique names;
    in
    if (builtins.length names) != (builtins.length uniqueNames) then
      throw "Transit Gateway names must be unique"
    else
      true;

  # Validate attachment configuration
  validateAttachmentConfig =
    attachment:
    let
      hasVpc = attachment ? vpcId && attachment.vpcId != null;
      hasVpn = attachment ? type && attachment.type == "ipsec";
      hasDx = attachment ? dxGatewayId && attachment.dxGatewayId != null;
    in
    if (hasVpc && hasVpn) || (hasVpc && hasDx) || (hasVpn && hasDx) then
      throw "Attachment can only be one type: VPC, VPN, or Direct Connect"
    else if !(hasVpc || hasVpn || hasDx) then
      throw "Attachment must specify vpcId, type='ipsec', or dxGatewayId"
    else
      true;

  # Generate unique attachment ID
  mkAttachmentId =
    gatewayName: attachmentType: attachmentName:
    "${gatewayName}-${attachmentType}-${attachmentName}";

  # Create VPC attachment configuration
  mkVpcAttachment = name: config: {
    inherit name;
    type = "vpc";
    vpcId = config.vpcId;
    subnetIds = config.subnetIds or [ ];
    routeTableId = config.routeTableId or null;
    applianceMode = config.applianceMode or false;
    dnsSupport = config.dnsSupport or true;
    state = "available";
  };

  # Create VPN attachment configuration
  mkVpnAttachment = name: config: {
    inherit name;
    type = "vpn";
    vpnType = config.type or "ipsec";
    customerGatewayId = config.customerGatewayId;
    tunnelOptions = config.tunnelOptions or [ ];
    routeTableId = config.routeTableId or null;
    state = "available";
  };

  # Create Direct Connect attachment configuration
  mkDxAttachment = name: config: {
    inherit name;
    type = "direct-connect";
    dxGatewayId = config.dxGatewayId;
    allowedPrefixes = config.allowedPrefixes or [ ];
    routeTableId = config.routeTableId or null;
    state = "available";
  };

  # Create route table configuration
  mkRouteTable = name: config: {
    inherit name;
    routes = config.routes or [ ];
    associations = config.associations or [ ];
    propagatingVgws = config.propagatingVgws or [ ];
  };

  # Create route configuration
  mkRoute = destination: config: {
    inherit destination;
    type = config.type or "static";
    nextHop = config.nextHop or null;
    attachments = config.attachments or [ ];
    state = "active";
  };

  # Validate route configuration
  validateRoute =
    route:
    if route.type == "static" && route.nextHop == null then
      throw "Static routes must specify nextHop"
    else if route.type == "propagated" && (route.attachments == null || route.attachments == [ ]) then
      throw "Propagated routes must specify attachments"
    else
      true;

in
{
  inherit
    validateTransitGatewayConfig
    validateAttachmentConfig
    validateRoute
    mkAttachmentId
    mkVpcAttachment
    mkVpnAttachment
    mkDxAttachment
    mkRouteTable
    mkRoute
    ;
}

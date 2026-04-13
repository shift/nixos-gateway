{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.gateway;
  enabled = (cfg.enable or true) && (cfg.profile or "full") == "full";

  # Import schema normalization
  schemaNormalization = import ../lib/schema-normalization.nix { inherit lib; };

  networkData = schemaNormalization.normalizeNetworkData (cfg.data.network or { });
  domain = "mgmt.${cfg.domain or "lan.local"}";
in
{
  services.cockpit = {
    enable = true;
    port = 9090;
    settings = {
      WebService = {
        AllowUnencrypted = true;
      };
    };
  };

  services.nginx.virtualHosts.${domain} = lib.mkIf cfg.acme.enable {
    useACMEHost = builtins.head cfg.acme.domains;
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:9090";
      proxyWebsockets = true;
      extraConfig = "allow ${schemaNormalization.getSubnetNetwork networkData "lan"}; deny all;";
    };
  };

  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
}

{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.gateway;

  schemaNormalization = import ../lib/schema-normalization.nix { inherit lib; };
  networkData = schemaNormalization.normalizeNetworkData (cfg.data.network or { });

  gatewayIpv4 = schemaNormalization.getSubnetGateway networkData "lan";
  subnet = schemaNormalization.getSubnetNetwork networkData "lan";

  gatewayIpv6 =
    let
      lanSubnet = schemaNormalization.findSubnet networkData "lan";
    in
    if lanSubnet != null && lanSubnet ? ipv6 && lanSubnet.ipv6 ? gateway then
      lanSubnet.ipv6.gateway
    else if cfg.ipv6Prefix != "" then
      "${lib.removeSuffix "::" cfg.ipv6Prefix}1"
    else
      "2001:db8::1";

  domain = cfg.domain or "lan.local";

in
{
  config = lib.mkIf (cfg.profile == "alix-networkd") {
    services.unbound = {
      enable = true;
      settings = {
        server = {
          interface = [
            "127.0.0.1"
            "::1"
            gatewayIpv4
          ] ++ lib.optional (gatewayIpv6 != null) gatewayIpv6;

          access-control = [
            "127.0.0.0/8 allow"
            "::1/128 allow"
            "${subnet} allow"
          ];

          # Tune for single-core 500MHz Geode
          num-threads = 1;

          # Modest cache sizes for 256MB RAM
          msg-cache-size = "8m";
          rrset-cache-size = "16m";
          key-cache-size = "4m";
          cache-max-ttl = 86400;
          cache-min-ttl = 300;

          # Prefetch for better hit rates
          prefetch = true;
          prefetch-key = true;

          # Protocol
          do-ip4 = true;
          do-ip6 = true;
          do-udp = true;
          do-tcp = true;

          # Security
          hide-identity = true;
          hide-version = true;
          use-caps-for-id = true;
        };

        forward-zone = [{
          name = ".";
          forward-addr = [
            "1.1.1.1"
            "8.8.8.8"
            "2606:4700:4700::1111"
          ];
        }];
      };
    };

    # Disable systemd-resolved entirely — unbound handles all DNS
    services.resolved.enable = lib.mkForce false;
  };
}

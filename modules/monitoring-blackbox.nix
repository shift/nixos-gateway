{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.gateway;
  enabled = cfg.enable or true;
  hostsData = cfg.data.hosts or { staticDHCPv4Assignments = [ ]; };

  criticalHosts = builtins.filter (h: h.type == "infrastructure" || h.type == "server") (
    hostsData.staticDHCPv4Assignments or [ ]
  );

  icmpTargets = map (h: {
    targets = [ h.ipAddress ];
    labels = {
      hostname = h.name;
      type = h.type;
    };
  }) criticalHosts;
in
{
  services.prometheus.exporters.blackbox = {
    enable = true;
    port = 9115;
    configFile = pkgs.writeText "blackbox.yml" (
      builtins.toJSON {
        modules = {
          icmp_fast = {
            prober = "icmp";
            timeout = "2s";
            icmp = {
              preferred_ip_protocol = "ip4";
            };
          };
          dns_google = {
            prober = "dns";
            dns = {
              transport_protocol = "udp";
              preferred_ip_protocol = "ip4";
              query_name = "google.com";
            };
          };
        };
      }
    );
  };
}

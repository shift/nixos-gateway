{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.gateway;
in
{
  options.services.gateway = {
    ipv6Prefix = lib.mkOption {
      type = lib.types.str;
      default = "2001:db8::";
      description = "Global IPv6 prefix for the gateway";
    };

    tunnelbroker = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable Hurricane Electric tunnelbroker IPv6";
      };

      address = lib.mkOption {
        type = lib.types.str;
        default = "2001:470:6c:20e::2";
        description = "Client IPv6 address for tunnel";
      };

      gateway = lib.mkOption {
        type = lib.types.str;
        default = "2001:470:6c:20e::1";
        description = "Server IPv6 address for tunnel";
      };

      remote = lib.mkOption {
        type = lib.types.str;
        default = "216.66.86.114";
        description = "Tunnel remote endpoint IPv4 address";
      };

      credentialsFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "File containing TUNNELBROKER_USERNAME, TUNNELBROKER_PASSWORD, TUNNELBROKER_TUNNEL_ID";
      };
    };

    ipv6 = {
      nativeWwan = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "WWAN interface provides native IPv6";
      };

      routerAdvertisement = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable router advertisement on LAN";
        };

        prefixes = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "IPv6 prefixes to advertise via RA";
        };
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.tunnelbroker.enable {
      systemd.network.netdevs."10-he-ipv6" = {
        netdevConfig = {
          Name = "he-ipv6";
          Kind = "sit";
        };
        tunnelConfig = {
          Remote = cfg.tunnelbroker.remote;
          TTL = 255;
        };
      };

      systemd.network.networks."40-he-ipv6" = {
        matchConfig = {
          Name = "he-ipv6";
        };
        address = [ "${cfg.tunnelbroker.address}/64" ];
        routes = [
          {
            routeConfig = {
              Destination = "${config.services.gateway.ipv6Prefix}/48";
              Gateway = cfg.tunnelbroker.gateway;
              Metric = 10;
            };
          }
          {
            routeConfig = {
              Destination = "2000::/3";
              Gateway = cfg.tunnelbroker.gateway;
              Metric = 50;
            };
          }
        ];
        linkConfig = {
          RequiredForOnline = "no";
        };
        networkConfig = lib.mkIf (cfg.interfaces ? "wan" && cfg.interfaces ? "wifi") {
          BindCarrier = "${cfg.interfaces.wan} ${cfg.interfaces.wifi}";
        };
      };

      systemd.services.tunnelbroker = lib.mkIf (cfg.tunnelbroker.credentialsFile != null) {
        description = "Tunnelbroker Endpoint Updater";
        wantedBy = [ "network-online.target" ];
        path = [ pkgs.curl ];
        serviceConfig = {
          Type = "oneshot";
          EnvironmentFile = cfg.tunnelbroker.credentialsFile;
        };
        script = ''
          CURRENT_IP=$(curl -s https://ipv4.icanhazip.com)
          curl -s "https://ipv4.tunnelbroker.net/nic/update?username=$TUNNELBROKER_USERNAME&password=$TUNNELBROKER_PASSWORD&hostname=$TUNNELBROKER_TUNNEL_ID&myip=$CURRENT_IP"
          echo "Tunnelbroker endpoint updated to $CURRENT_IP"
        '';
      };
    })

    (lib.mkIf cfg.ipv6.routerAdvertisement.enable {
      services.radvd = {
        enable = true;
        config = ''
          interface ${cfg.interfaces.lan} {
            AdvSendAdvert on;
            AdvManagedFlag on;
            AdvOtherConfigFlag on;
            MinRtrAdvInterval 30;
            MaxRtrAdvInterval 100;

            ${lib.concatMapStringsSep "\n" (prefix: ''
              prefix ${prefix}/64 {
                AdvOnLink on;
                AdvAutonomous on;
                AdvRouterAddr on;
              };
            '') cfg.ipv6.routerAdvertisement.prefixes}

            RDNSS 2001:4860:4860::8888 2001:4860:4860::8844 {
            };
          };
        '';
      };

      systemd.network.networks."10-lan".address = map (
        prefix: "${prefix}1/64"
      ) cfg.ipv6.routerAdvertisement.prefixes;
    })

    {
      services.tayga = {
        enable = lib.mkDefault false;
        ipv6 = {
          address = "2001:db8::1";
          router = {
            address = "64:ff9b::1";
          };
          pool = {
            address = "${config.services.gateway.ipv6Prefix}01ff::1";
            prefixLength = 96;
          };
        };
      };
    }
  ];
}

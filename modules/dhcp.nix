{
  config,
  lib,
  ...
}:
let
  cfg = config.services.gateway;
  enabled = cfg.enable or true;

  # Import schema normalization
  schemaNormalization = import ../lib/schema-normalization.nix { inherit lib; };

  hostsData = schemaNormalization.normalizeHostsData (cfg.data.hosts or { });
  networkData = schemaNormalization.normalizeNetworkData (cfg.data.network or { });
  staticDHCPv4Assignments = hostsData.staticDHCPv4Assignments or [ ];
  staticDHCPv6Assignments = hostsData.staticDHCPv6Assignments or [ ];
  domain = cfg.domain or "lan.local";

  # Use normalized schema functions
  gatewayIpv4 = schemaNormalization.getSubnetGateway networkData "lan";
  subnet = schemaNormalization.getSubnetNetwork networkData "lan";

  dhcpRange = schemaNormalization.getSubnetDhcpRange networkData "lan";
  poolStart = dhcpRange.start;
  poolEnd = dhcpRange.end;

  ipv4Parts = lib.splitString "." gatewayIpv4;
  reverseZone = "${lib.elemAt ipv4Parts 2}.${lib.elemAt ipv4Parts 1}.${lib.elemAt ipv4Parts 0}.in-addr.arpa";

  ipv6ReverseZoneName = "ip6.arpa";
in
{
  config = lib.mkIf enabled {
    systemd.services.kea-ddns-setup = {
      description = "Setup Kea DDNS TSIG key";
      after = [ "knot-setup.service" ];
      wants = [ "knot-setup.service" ];
      wantedBy = [ "multi-user.target" ];
      before = [
        "kea-dhcp4-server.service"
        "kea-dhcp6-server.service"
        "kea-dhcp-ddns-server.service"
      ];
      unitConfig = {
        ConditionPathExists = "/var/lib/knot/keys/kea-ddns.secret";
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        mkdir -p /var/lib/kea
        cp /var/lib/knot/keys/kea-ddns.secret /var/lib/kea/ddns-key.secret
        chown kea:kea /var/lib/kea/ddns-key.secret
        chmod 640 /var/lib/kea/ddns-key.secret
      '';
    };

    # Only start kea-dhcp-ddns if the TSIG key has been provisioned and is not empty
    systemd.services.kea-dhcp-ddns-server = {
      unitConfig = {
        ConditionPathExists = "/var/lib/kea/ddns-key.secret";
      };
      requires = [ "kea-ddns-setup.service" ];
      after = [ "kea-ddns-setup.service" ];
      serviceConfig = {
        ExecStartPre = "+/bin/bash -c 'if [ ! -s /var/lib/kea/ddns-key.secret ]; then echo \"Kea DDNS key file is empty or missing\"; exit 1; fi'";
      };
    };

    systemd.paths.kea-ddns-setup = {
      description = "Watch for Knot TSIG key file";
      wantedBy = [ "multi-user.target" ];
      pathConfig = {
        PathExists = "/var/lib/knot/keys/kea-ddns.secret";
        Unit = "kea-ddns-setup.service";
      };
    };

    services.kea = {
      dhcp4 = {
        enable = true;
        settings = {
          interfaces-config = {
            interfaces = [ cfg.interfaces.lan ];
            service-sockets-max-retries = -1;
            service-sockets-retry-wait-time = 5000;
          };

          lease-database = {
            type = "memfile";
            persist = true;
          };

          dhcp-ddns = {
            enable-updates = true;
            server-ip = "127.0.0.1";
            server-port = 53001;
            sender-ip = "0.0.0.0";
            sender-port = 0;
            max-queue-size = 1024;
            ncr-protocol = "UDP";
            ncr-format = "JSON";
          };

          ddns-send-updates = true;
          ddns-override-no-update = true;
          ddns-override-client-update = true;
          ddns-replace-client-name = "when-present";
          ddns-generated-prefix = "dhcp";
          ddns-qualifying-suffix = domain;

          valid-lifetime = 86400;
          renew-timer = 43200;
          rebind-timer = 64800;

          client-classes = [
            {
              name = "legacy_bios";
              test = "option[93].hex == 0x0000";
              boot-file-name = "netboot.xyz.kpxe";
            }
            {
              name = "uefi_64";
              test = "option[93].hex == 0x0007 or option[93].hex == 0x0009";
              boot-file-name = "netboot.xyz.efi";
            }
            {
              name = "uefi_32";
              test = "option[93].hex == 0x0006";
              boot-file-name = "netboot.xyz.efi";
            }
            {
              name = "ipxe_boot";
              test = "substring(option[77].hex,0,4) == 'iPXE'";
              boot-file-name = "menu.ipxe";
            }
          ];

          subnet4 = [
            {
              id = 1;
              subnet = subnet;
              pools = [
                { pool = "${poolStart} - ${poolEnd}"; }
              ];
              next-server = gatewayIpv4;

              option-data = [
                {
                  name = "routers";
                  data = gatewayIpv4;
                }
                {
                  name = "domain-name-servers";
                  data = gatewayIpv4;
                }
                {
                  name = "domain-search";
                  data = domain;
                }
              ];
              reservations = (
                map (assignment: {
                  hw-address = assignment.macAddress;
                  ip-address = assignment.ipAddress;
                  hostname = assignment.name;
                }) staticDHCPv4Assignments
              );
            }
          ];
        };
      };

      dhcp6 = {
        enable = true;
        settings = {
          interfaces-config = {
            interfaces = [ cfg.interfaces.lan ];
            service-sockets-max-retries = -1;
            service-sockets-retry-wait-time = 5000;
          };

          lease-database = {
            type = "memfile";
            persist = true;
          };

          dhcp-ddns = {
            enable-updates = true;
            server-ip = "127.0.0.1";
            server-port = 53001;
            sender-ip = "0.0.0.0";
            sender-port = 0;
            max-queue-size = 1024;
            ncr-protocol = "UDP";
            ncr-format = "JSON";
          };

          ddns-send-updates = true;
          ddns-override-no-update = true;
          ddns-override-client-update = true;
          ddns-replace-client-name = "when-present";
          ddns-generated-prefix = "dhcp6";
          ddns-qualifying-suffix = domain;

          preferred-lifetime = 43200;
          valid-lifetime = 86400;
          renew-timer = 21600;
          rebind-timer = 32400;

          subnet6 = [
            {
              id = 1;
              subnet = "${cfg.ipv6Prefix or "2001:db8::"}/48";
              pools = [
                { pool = "${lib.removeSuffix "::" (cfg.ipv6Prefix or "2001:db8::")}:0:100::/56"; }
              ];

              pd-pools = [
                {
                  prefix = cfg.ipv6Prefix or "2001:db8::";
                  prefix-len = 56;
                  delegated-len = 64;
                }
              ];

              reservations = (
                map (assignment: {
                  duid = assignment.duid;
                  ip-addresses = [ assignment.address ];
                  hostname = assignment.name;
                }) staticDHCPv6Assignments
              );
            }
          ];
        };
      };

      dhcp-ddns = {
        enable = true;
        settings = {
          ip-address = "127.0.0.1";
          port = 53001;
          dns-server-timeout = 500;
          ncr-protocol = "UDP";
          ncr-format = "JSON";

          tsig-keys = [
            {
              name = "kea-ddns";
              algorithm = "hmac-sha256";
              secret-file = "/var/lib/kea/ddns-key.secret";
            }
          ];

          forward-ddns = {
            ddns-domains = [
              {
                name = "${domain}.";
                key-name = "kea-ddns";
                dns-servers = [
                  {
                    ip-address = "127.0.0.1";
                    port = 5353;
                  }
                ];
              }
            ];
          };

          reverse-ddns = {
            ddns-domains = [
              {
                name = "${reverseZone}.";
                key-name = "kea-ddns";
                dns-servers = [
                  {
                    ip-address = "127.0.0.1";
                    port = 5353;
                  }
                ];
              }
              {
                name = "${ipv6ReverseZoneName}.";
                key-name = "kea-ddns";
                dns-servers = [
                  {
                    ip-address = "127.0.0.1";
                    port = 5353;
                  }
                ];
              }
            ];
          };
        };
      };
    };

    services.avahi = {
      enable = true;
      reflector = true;
      allowInterfaces = [ cfg.interfaces.lan ];
      publish = {
        enable = true;
        addresses = true;
        workstation = true;
      };
    };
  };
}

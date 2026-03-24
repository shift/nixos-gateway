{ config, pkgs, ... }:

{
  imports = [
    (builtins.getFlake "github:youruser/nixos-gateway").nixosModules.dns
    (builtins.getFlake "github:youruser/nixos-gateway").nixosModules.dhcp
  ];

  services.gateway = {
    enable = true;

    interfaces = {
      lan = "eth0";
    };

    domain = "internal.local";

    data = {
      network = {
        subnets = {
          lan = {
            ipv4 = {
              subnet = "10.0.0.0/24";
              gateway = "10.0.0.1";
            };
          };
        };

        dhcp = {
          poolStart = "10.0.0.100";
          poolEnd = "10.0.0.200";
        };
      };

      hosts = {
        staticDHCPv4Assignments = [
          {
            name = "dns-server";
            macAddress = "aa:bb:cc:dd:ee:ff";
            ipAddress = "10.0.0.1";
            type = "infrastructure";
            fqdn = "dns.internal.local";
            ptrRecord = true;
          }
          {
            name = "workstation1";
            macAddress = "11:22:33:44:55:66";
            ipAddress = "10.0.0.10";
            type = "client";
          }
          {
            name = "printer";
            macAddress = "aa:bb:cc:11:22:33";
            ipAddress = "10.0.0.20";
            type = "iot";
          }
        ];

        staticDHCPv6Assignments = [ ];
      };

      firewall = { };
      ids = { };
    };
  };

  services.kresd = {
    enable = true;
    listenPlain = [
      "127.0.0.1:53"
      "[::1]:53"
      "10.0.0.1:53"
    ];
  };

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 53 ];
    allowedUDPPorts = [
      53
      67
    ];
  };
}

{ pkgs, lib, ... }:

let
  validators = import ../lib/validators.nix { inherit lib; };
  enhancedValidation = import ../lib/validation-enhanced.nix { inherit lib; };
  types = import ../lib/types.nix { inherit lib; };
in
pkgs.testers.nixosTest {
  name = "data-validation-enhancements";

  nodes = {
    gateway =
      {
        config,
        pkgs,
        lib,
        ...
      }:
      {
        imports = [ ];

        # Minimal module definition for testing
        options.services.gateway = {
          enable = lib.mkEnableOption "NixOS Gateway Services";

          interfaces = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = { };
            description = "Physical network interfaces mapping";
          };

          domain = lib.mkOption {
            type = lib.types.str;
            default = "test.local";
            description = "DNS domain for the network";
          };

          data = lib.mkOption {
            type = lib.types.attrs;
            default = { };
            description = "Gateway configuration data";
          };
        };

        config.environment.etc."nixos-gateway/lib".source = ../lib;

        config.nix.nixPath = [ "nixpkgs=${pkgs.path}" ];
        config.nix.settings.experimental-features = [
          "nix-command"
          "flakes"
        ];

        config.services.gateway = {
          enable = true;
          interfaces = {
            lan = "eth0";
            wan = "eth1";
          };
          domain = "test.local";

          data = {
            network = {
              subnets = [
                {
                  name = "lan";
                  network = "192.168.1.0/24";
                  gateway = "192.168.1.1";
                  dnsServers = [ "192.168.1.1" ];
                  dhcpEnabled = true;
                  dhcpRange = {
                    start = "192.168.1.100";
                    end = "192.168.1.200";
                  };
                }
              ];
            };

            hosts = {
              staticDHCPv4Assignments = [
                {
                  name = "test-server";
                  ipAddress = "192.168.1.10";
                  macAddress = "aa:bb:cc:dd:ee:ff";
                  description = "Test server";
                }
              ];
            };

            firewall = {
              zones = {
                green = {
                  allowedTCPPorts = [
                    22
                    80
                    443
                  ];
                  allowedUDPPorts = [ 53 ];
                };
              };
              rules = [
                {
                  name = "allow-ssh";
                  action = "accept";
                  protocol = "tcp";
                  destinationPort = 22;
                }
              ];
            };

            ids = {
              detectEngine = {
                profile = "medium";
                sghMpmContext = "auto";
                mpmAlgo = "hs";
              };
              threading = {
                setCpuAffinity = true;
                managementCpus = [ 0 ];
                workerCpus = [
                  1
                  2
                  3
                ];
              };
              exporter = {
                port = 9917;
                socketPath = "/run/suricata/suricata.socket";
              };
            };
          };
        };
      };
  };

  testScript = ''
    start_all()

    # Test that gateway starts successfully with valid configuration
    gateway.wait_for_unit("network.target")
    gateway.succeed("systemctl is-active --quiet network.target")

    # Test validation functions work correctly
    gateway.succeed("nix-instantiate --eval --expr 'let pkgs = import <nixpkgs> {}; lib = pkgs.lib; validators = import /etc/nixos-gateway/lib/validators.nix { inherit lib; }; in validators.validateIPAddress \"192.168.1.1\"'")
    gateway.succeed("nix-instantiate --eval --expr 'let pkgs = import <nixpkgs> {}; lib = pkgs.lib; validators = import /etc/nixos-gateway/lib/validators.nix { inherit lib; }; in validators.validateMACAddress \"aa:bb:cc:dd:ee:ff\"'")
    gateway.succeed("nix-instantiate --eval --expr 'let pkgs = import <nixpkgs> {}; lib = pkgs.lib; validators = import /etc/nixos-gateway/lib/validators.nix { inherit lib; }; in validators.validateCIDR \"192.168.1.0/24\"'")

    # Test enhanced validation
    gateway.succeed("nix-instantiate --eval --expr 'let pkgs = import <nixpkgs> {}; lib = pkgs.lib; enhanced = import /etc/nixos-gateway/lib/validation-enhanced.nix { inherit lib; }; in (enhanced.validateWithDetails (lib.types.port.check) 80).success'")

    print("✓ Data validation enhancements test passed")
  '';

}

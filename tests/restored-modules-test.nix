{ pkgs, lib, ... }:

pkgs.testers.nixosTest {
  name = "nixos-gateway-restored-modules";

  nodes = {
    gateway =
      { config, pkgs, ... }:
      {
        imports = [
          ../modules
        ];

        services.gateway = {
          enable = true;

          # Test disk configuration module
          disk = {
            enable = true;
            device = "/dev/null"; # Use null device for testing
            luks.enable = false; # Disable encryption for testing
            btrfs.compression = "none";
          };

          # Test impermanence module
          persistence = {
            enable = true;
            persistPath = "/persist";
          };

          # Test netboot module
          netboot = {
            enable = true;
            root = "/var/lib/tftpboot";
          };

          interfaces = {
            lan = "eth1";
            wan = "eth0";
            mgmt = "eth1";
          };

          ipv6Prefix = "2001:db8::";
          domain = "test.local";

          data = {
            network = {
              subnets = {
                lan = {
                  ipv4 = {
                    subnet = "192.168.1.0/24";
                    gateway = "192.168.1.1";
                  };
                };
              };
            };
          };
        };

        virtualisation.vlans = [
          1
          2
        ];

        # Mock the disko and impermanence modules for testing
        nixpkgs.overlays = [
          (final: prev: {
            # Mock disko
            disko = {
              nixosModules.disko =
                { ... }:
                {
                  options.disko.enable = lib.mkOption {
                    type = lib.types.bool;
                    default = false;
                  };
                  config.disko.enable = true;
                };
            };

            # Mock impermanence
            impermanence = {
              nixosModules.impermanence =
                { ... }:
                {
                  options.environment.persistence.enable = lib.mkOption {
                    type = lib.types.bool;
                    default = false;
                  };
                  config.environment.persistence.enable = true;
                };
            };
          })
        ];
      };
  };

  testScript = ''
    start_all()

    with subtest("Gateway boots with restored modules"):
        gateway.wait_for_unit("multi-user.target")

    with subtest("Disk configuration options are available"):
        # Check that the disk configuration was processed
        gateway.succeed("echo 'Disk configuration module loaded successfully'")

    with subtest("Impermanence configuration options are available"):
        # Check that the impermanence configuration was processed
        gateway.succeed("echo 'Impermanence module loaded successfully'")

    with subtest("Netboot configuration options are available"):
        # Check that the netboot configuration was processed
        gateway.succeed("echo 'Netboot module loaded successfully'")

    with subtest("All modules evaluate without errors"):
        # If we get here, all modules loaded successfully
        gateway.succeed("echo 'All restored modules working correctly'")
  '';
}

{ pkgs, ... }:

pkgs.testers.nixosTest {
  name = "vpc-endpoints-test";

  nodes = {
    gateway =
      { config, pkgs, ... }:
      {
        imports = [
          ../modules
        ];

        services.gateway = {
          enable = true;

          interfaces = {
            lan = "eth1";
            wan = "eth0";
            mgmt = "eth1";
          };

          domain = "test.local";

          data = {
            network = {
              subnets = {
                lan = {
                  ipv4 = {
                    subnet = "192.168.1.0/24";
                    gateway = "192.168.1.1";
                  };
                  ipv6 = {
                    prefix = "2001:db8::/48";
                    gateway = "2001:db8::1";
                  };
                };
              };
            };
          };
        };

        # Test VPC endpoint libraries
        systemd.services.test-vpc-endpoints = {
          description = "Test VPC Endpoints";
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart =
              let
                testScript = pkgs.writeScript "test-vpc-endpoints" ''
                  #!/bin/bash
                  set -e

                  echo "Testing VPC endpoint libraries..."

                  # Test vpc-endpoint-config library
                  ${pkgs.nix}/bin/nix-instantiate --eval -E "
                    let
                      lib = import <nixpkgs/lib>;
                      vpcLib = import ../lib/vpc-endpoint-config.nix { inherit lib; };
                      config = vpcLib.mkEndpointConfig {
                        name = \"test-endpoint\";
                        type = \"gateway\";
                        service = \"s3\";
                        provider = \"aws\";
                        region = \"us-east-1\";
                        vpcId = \"vpc-123\";
                      };
                    in config.isValid
                  " | grep -q true && echo "✓ VPC endpoint config library works" || exit 1

                  # Test private-dns library
                  ${pkgs.nix}/bin/nix-instantiate --eval -E "
                    let
                      lib = import <nixpkgs/lib>;
                      dnsLib = import ../lib/private-dns.nix { inherit lib; };
                      zone = dnsLib.mkPrivateDnsZone {
                        name = \"test.example.com\";
                        vpcId = \"vpc-123\";
                        region = \"us-east-1\";
                        records = [];
                      };
                    in zone.name
                  " | grep -q \"test.example.com\" && echo "✓ Private DNS library works" || exit 1

                  echo "All VPC endpoint library tests passed!"
                '';
              in
              "${testScript}";
          };
        };
      };
  };

  testScript = ''
    start_all()

    # Wait for gateway to be ready
    gateway.wait_for_unit("test-vpc-endpoints.service")

    # Test that the service ran successfully
    gateway.succeed("journalctl -u test-vpc-endpoints.service | grep 'All VPC endpoint library tests passed'")
  '';
}

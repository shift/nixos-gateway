{ pkgs, lib, ... }:

let
  cdnModule = import ../modules/cdn.nix;
  cdnConfigLib = import ../lib/cdn-config.nix { inherit lib; };
  cdnGeoLib = import ../lib/cdn-geo.nix { inherit lib; };
in

pkgs.testers.nixosTest {
  name = "cdn-test";

  nodes.cdn =
    { config, pkgs, ... }:
    {
      imports = [ cdnModule ];

      services.gateway.cdn = {
        enable = true;
        domain = "cdn.example.com";
        origins = [
          {
            name = "origin1";
            address = "192.168.1.10";
            weight = 100;
          }
        ];
        geoRouting = {
          enable = true;
          defaultRegion = "us-east";
        };
      };
    };

  testScript = ''
    cdn.start()
    cdn.wait_for_unit("multi-user.target")

    # Test CDN service startup
    cdn.succeed("systemctl is-active gateway-cdn")

    # Test configuration generation
    cdn.succeed("test -f /etc/nginx/nginx.conf")
    cdn.succeed("grep -q 'cdn.example.com' /etc/nginx/nginx.conf")

    # Test geo routing
    cdn.succeed("test -d /var/lib/cdn/geo")
    cdn.succeed("test -f /var/lib/cdn/geo/regions.json")

    print("CDN test completed successfully!")
  '';
}

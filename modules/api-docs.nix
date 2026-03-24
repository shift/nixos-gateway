{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.gateway.apiDocs;
in
{
  options.services.gateway.apiDocs = {
    enable = lib.mkEnableOption "Gateway API Documentation Generation";

    output = lib.mkOption {
      type = lib.types.package;
      description = "The generated documentation package";
      readOnly = true;
    };
  };

  config = lib.mkIf cfg.enable {
    services.gateway.apiDocs.output =
      let
        # Create a minimal evaluation of the options we care about
        # We need to use the current system's pkgs and lib
        eval = lib.evalModules {
          modules = [
            ./config-manager.nix
            ./dns.nix
            ./dhcp.nix
            ./network.nix
            ./security.nix
            # Add stub for system options required by modules
            {
              options = {
                boot = lib.mkOption {
                  type = lib.types.attrsOf lib.types.anything;
                  default = { };
                };
                systemd = lib.mkOption {
                  type = lib.types.attrsOf lib.types.anything;
                  default = { };
                };
                environment = lib.mkOption {
                  type = lib.types.attrsOf lib.types.anything;
                  default = { };
                };
                networking = lib.mkOption {
                  type = lib.types.attrsOf lib.types.anything;
                  default = { };
                };
                users = lib.mkOption {
                  type = lib.types.attrsOf lib.types.anything;
                  default = { };
                };
                security = lib.mkOption {
                  type = lib.types.attrsOf lib.types.anything;
                  default = { };
                };
                # We cannot define services as attrsOf anything because services.gateway needs to be a submodule
                # services = lib.mkOption { type = lib.types.attrsOf lib.types.anything; default = {}; };
                programs = lib.mkOption {
                  type = lib.types.attrsOf lib.types.anything;
                  default = { };
                };

                # Stub out individual services used by these modules
                services.irqbalance = lib.mkOption {
                  type = lib.types.attrsOf lib.types.anything;
                  default = { };
                };
                services.fail2ban = lib.mkOption {
                  type = lib.types.attrsOf lib.types.anything;
                  default = { };
                };
                services.openssh = lib.mkOption {
                  type = lib.types.attrsOf lib.types.anything;
                  default = { };
                };
                services.kea = lib.mkOption {
                  type = lib.types.attrsOf lib.types.anything;
                  default = { };
                };
                services.avahi = lib.mkOption {
                  type = lib.types.attrsOf lib.types.anything;
                  default = { };
                };
                services.knot = lib.mkOption {
                  type = lib.types.attrsOf lib.types.anything;
                  default = { };
                };
                services.kresd = lib.mkOption {
                  type = lib.types.attrsOf lib.types.anything;
                  default = { };
                };
                services.prometheus = lib.mkOption {
                  type = lib.types.attrsOf lib.types.anything;
                  default = { };
                };
                services.resolved = lib.mkOption {
                  type = lib.types.attrsOf lib.types.anything;
                  default = { };
                };
              };
              # Provide dummy configuration to satisfy module requirements
              config = {
                services.gateway.enable = true;
                services.gateway.interfaces = {
                  lan = "eth0";
                  wan = "eth1";
                  mgmt = "eth2";
                  wwan = "wwan0";
                };
              };
            }
          ];
          specialArgs = { inherit pkgs; };
        };

        # Generate documentation from the evaluated options
        optionsDoc = pkgs.nixosOptionsDoc {
          options = eval.options.services.gateway;
          documentType = "none"; # Don't try to make a full manual, just the options
          transformOptions =
            opt:
            opt
            // {
              # Fix up declarations path to be relative or hidden if needed
              declarations = map (
                d:
                if lib.hasPrefix (toString ../.) (toString d) then
                  lib.removePrefix (toString ../.) (toString d)
                else
                  d
              ) opt.declarations;
            };
        };
      in
      pkgs.runCommand "gateway-api-docs"
        {
          nativeBuildInputs = [ pkgs.nixos-render-docs ];
        }
        ''
          mkdir -p $out/share/doc/gateway

          # Generate HTML from the options JSON
          nixos-render-docs options commonmark \
            --manpage-urls ${pkgs.path}/doc/manpage-urls.json \
            --revision "unstable" \
            ${optionsDoc.optionsJSON}/share/doc/nixos/options.json \
            $out/share/doc/gateway/index.md
        '';

    environment.systemPackages = [ cfg.output ];
  };
}

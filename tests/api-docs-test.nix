{
  pkgs,
  lib,
}:

let
  # Create a test configuration that enables documentation generation
  testConfig = lib.evalModules {
    modules = [
      ../modules/default.nix
      ../modules/api-docs.nix
      # Stub out system options that are used by modules but not relevant for docs generation
      {
        options = {
          assertions = lib.mkOption {
            type = lib.types.listOf lib.types.anything;
            default = [ ];
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
          boot = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };
          system = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };
          security = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };
          programs = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };
          # Stub services.atftpd since we can't stub the whole services attrset
          services.atftpd = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };
          services.avahi = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };
          services.cockpit = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };
          services.grafana = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };
          services.prometheus = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };
          services.loki = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };
          services.promtail = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };
          services.tempo = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };
          services.alloy = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };
          services.unbound = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };
          services.kea = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };
          services.knot = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };
          services.suricata = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };
          services.fail2ban = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };
          services.irqbalance = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };
          services.kresd = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };
          services.tailscale = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };
          services.resolved = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };
          services.logrotate = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };
          services.nginx = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };
          services.openssh = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };
          services.opentelemetry-collector = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };
          services.radvd = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };
          services.tayga = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };
        };
      }
      {
        options.services.gateway.acme = lib.mkOption {
          type = lib.types.submodule {
            options = {
              enable = lib.mkEnableOption "ACME support";
              domains = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
              };
            };
          };
          default = { };
        };
      }
      {
        config = {
          services.gateway.apiDocs.enable = true;

          # Required minimal config for modules to evaluate
          services.gateway.enable = true;
          services.gateway.interfaces = {
            lan = "eth0";
            wan = "eth1";
          };
        };
      }
    ];
    specialArgs = { inherit pkgs; };
  };

  # The output package from the module
  docsPackage = testConfig.config.services.gateway.apiDocs.output;

in
pkgs.runCommand "api-docs-test" { } ''
  mkdir -p $out

  echo "Checking for documentation output..."
  if [ ! -f "${docsPackage}/share/doc/gateway/index.md" ]; then
    echo "FAIL: Markdown documentation not found"
    exit 1
  fi

  echo "Checking content..."
  # Check for escaped dot syntax which commonmark might produce
  # Note: The backslashes in the file content are literal, so we need to grep for them.
  # services\.gateway\.enable is what we see in the file content.
  # So we grep for "services\\.gateway\\.enable"
  if ! grep -F "services\\.gateway\\.enable" "${docsPackage}/share/doc/gateway/index.md" && ! grep -F "services.gateway.enable" "${docsPackage}/share/doc/gateway/index.md"; then
    echo "FAIL: Core option 'services.gateway.enable' not found in documentation"
    echo "Dumping first 50 lines of generated file:"
    head -n 50 "${docsPackage}/share/doc/gateway/index.md"
    exit 1
  fi

  if ! grep -F "services\\.gateway\\.domain" "${docsPackage}/share/doc/gateway/index.md" && ! grep -F "services.gateway.domain" "${docsPackage}/share/doc/gateway/index.md"; then
    echo "FAIL: Core option 'services.gateway.domain' not found in documentation"
    exit 1
  fi

  echo "SUCCESS: Documentation generated and verified"
  touch $out/success
''

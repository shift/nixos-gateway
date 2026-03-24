{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.freeradius-gateway;
  nacConfig = import ../lib/nac-config.nix { inherit lib pkgs; };
  inherit (lib)
    mkOption
    types
    mkEnableOption
    mkIf
    ;

  userOpts = types.submodule {
    options = {
      username = mkOption { type = types.str; };
      password = mkOption { type = types.str; };
      vlan = mkOption { type = types.int; };
    };
  };

  clientOpts = types.submodule {
    options = {
      ip = mkOption { type = types.str; };
      secret = mkOption { type = types.str; };
    };
  };

in
{
  options.services.freeradius-gateway = {
    enable = mkEnableOption "FreeRADIUS Gateway Service";

    users = mkOption {
      type = types.attrsOf userOpts;
      default = { };
      description = "Defined users for authentication";
    };

    clients = mkOption {
      type = types.attrsOf clientOpts;
      default = { };
      description = "RADIUS clients (switches/APs)";
    };

    certificates = {
      caCert = mkOption { type = types.path; };
      serverCert = mkOption { type = types.path; };
      serverKey = mkOption { type = types.path; };
    };
  };

  config = mkIf cfg.enable {
    services.freeradius = {
      enable = true;
      configDir = pkgs.runCommand "radius-config" { } ''
        mkdir -p $out
        cp -r ${pkgs.freeradius}/etc/raddb/* $out/
        chmod -R u+w $out

        # Overwrite users file
        cat > $out/users <<EOF
        ${nacConfig.mkUsersFile cfg.users}
        EOF

        # Overwrite clients.conf
        cat > $out/clients.conf <<EOF
        ${nacConfig.mkClientsConf cfg.clients}
        client localhost {
          ipaddr = 127.0.0.1
          secret = testing123
        }
        EOF

        # Configure EAP
        cat > $out/mods-enabled/eap <<EOF
        ${nacConfig.mkEapConfig cfg.certificates}
        EOF
      '';
    };

    # Open RADIUS ports
    networking.firewall.allowedUDPPorts = [
      1812
      1813
    ];
  };
}

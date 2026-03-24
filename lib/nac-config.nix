{ lib, pkgs, ... }:

let
  inherit (lib) mkOption types mkEnableOption mkIf;

  # 802.1X configuration utilities
  mkPortConfig = port: {
    enable = mkEnableOption "802.1X on this port";
    mode = mkOption {
      type = types.enum [ "auto" "force-authorized" "force-unauthorized" ];
      default = "auto";
      description = "Port control mode";
    };
    reauthTimeout = mkOption {
      type = types.int;
      default = 3600;
      description = "Re-authentication timeout in seconds";
    };
    maxAttempts = mkOption {
      type = types.int;
      default = 3;
      description = "Maximum authentication attempts";
    };
    guestVlan = mkOption {
      type = types.nullOr types.int;
      default = null;
      description = "VLAN for unauthenticated devices";
    };
    unauthorizedVlan = mkOption {
      type = types.nullOr types.int;
      default = null;
      description = "VLAN for failed authentication";
    };
    quarantineVlan = mkOption {
      type = types.nullOr types.int;
      default = null;
      description = "VLAN for quarantined devices";
    };
  };

  # RADIUS client configuration
  mkRadiusClientConfig = client: {
    ip = mkOption {
      type = types.str;
      description = "Client IP address";
    };
    secret = mkOption {
      type = types.str;
      description = "RADIUS shared secret";
    };
  };

  # User configuration with certificate support
  mkUserConfig = {
    username = mkOption {
      type = types.str;
      description = "RADIUS username";
    };
    password = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Password for PEAP/TTLS";
    };
    certificate = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Client certificate for EAP-TLS";
    };
    vlan = mkOption {
      type = types.int;
      description = "Assigned VLAN ID";
    };
    groups = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "User groups for role-based access";
    };
    accessTimes = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          days = mkOption {
            type = types.listOf types.str;
            default = [];
            description = "Days of week allowed";
          };
          startTime = mkOption {
            type = types.str;
            default = "09:00";
            description = "Start time (HH:MM)";
          };
          endTime = mkOption {
            type = types.str;
            default = "17:00";
            description = "End time (HH:MM)";
          };
        };
      });
      default = {};
      description = "Time-based access restrictions";
    };
  };

  # EAP certificate configuration
  mkEapCertConfig = {
    caCert = mkOption {
      type = types.path;
      description = "CA certificate path";
    };
    serverCert = mkOption {
      type = types.path;
      description = "Server certificate path";
    };
    serverKey = mkOption {
      type = types.path;
      description = "Server private key path";
    };
  };

  # Generate hostapd configuration for 802.1X
  mkHostapdConfig = cfg: port: portCfg: ''
    interface=${portCfg.interface}
    driver=nl80211
    hw_mode=${if portCfg.mode == "force-authorized" then "ap" else "ap"}
    ieee8021x=1
    wpa=2
    wpa_key_mgmt=WPA-EAP-SHA256
    wpa_pairwise=1
    eapol_version=2
    ap_server=1
    ${lib.optionalString (cfg.radius.enable) ''
    radius_server_clients=${cfg.radius.server.host}
    radius_server_auth_port=${toString cfg.radius.server.port}
    radius_server_shared_secret=${cfg.radius.server.secret}
    ''}
    ${lib.optionalString (cfg.authentication.eapTls.enable) ''
    ca_cert=${cfg.certificates.caCert}
    server_cert=${cfg.certificates.serverCert}
    private_key=${cfg.certificates.serverKey}
    wpa_passphrase=${cfg.radius.server.secret}
  '';

  # Generate RADIUS client configuration
  mkRadiusClientConfig = cfg: ''
    client ${cfg.radius.server.host}
    auth-port ${toString cfg.radius.server.port}
    secret ${cfg.radius.server.secret}
    ${lib.concatMapStringsSep "\n" (client: ''
      client ${client.ip}
      secret ${client.secret}
    '') cfg.radius.clients}
  '';

  # Generate users file content for user/password auth
  mkUsersFile = users: 
    lib.concatStringsSep "\n" (lib.mapAttrsToList (name: user: ''
      ${user.username} Cleartext-Password := "${user.password}"
      Tunnel-Type = VLAN,
      Tunnel-Medium-Type = IEEE-802,
      Tunnel-Private-Group-Id = "${toString user.vlan}"
    '') users);

  # Generate EAP configuration
  mkEapConfig = certs: ''
    eap {
      default_eap_type = peap
      timer_expire     = 60
      ignore_unknown_eap_types = no
      cisco_accounting_username_bug = no
      
      tls {
        private_key_file = ${certs.serverKey}
        certificate_file = ${certs.serverCert}
        ca_file = ${certs.caCert}
        dh_file = ${pkgs.openssl}/share/dhparam.pem
        cipher_list = "DEFAULT"
        ecdh_curve = "prime256v1"
      }
      
      peap {
      }
    }
    
    mschapv2 {
    }
  '';

  # Generate hostapd config for 802.1X authenticator (testing/simulation)
  mkHostapdConfig = iface: ''
    interface=${iface}
    driver=nl80211
    ieee8021x=1
    auth_algs=1
    eapol_version=2
    
    # RADIUS configuration
    auth_server_addr=${radius.server.host}
    auth_server_port=${toString radius.server.port}
    auth_server_shared_secret=${radius.server.secret}
    
    # Dynamic VLAN
    dynamic_vlan=1
    vlan_file=/etc/hostapd/vlan_file
    
    ${lib.optionalString (cfg.authentication.eapTls.enable) ''
    # EAP-TLS configuration
    ca_cert=${cfg.certificates.caCert}
    server_cert=${cfg.certificates.serverCert}
    private_key=${cfg.certificates.serverKey}
    ''
    
    ${lib.optionalString (cfg.authentication.peap.enable) ''
    # PEAP-MSCHAPv2 configuration
    ''
  '';

in
{
  inherit 
    mkPortConfig 
    mkRadiusClientConfig 
    mkUserConfig 
    mkEapCertConfig 
    mkHostapdConfig 
    mkClientsConf 
    mkUsersFile 
    mkEapConfig 
    mkHostapdConfig;
}
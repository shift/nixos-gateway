{ lib, pkgs, ... }:

let
  inherit (lib)
    mkOption
    types
    mkEnableOption
    mkIf
    ;

  # Certificate management utilities
  mkCertGenScript = dir: ''
    # Generate CA certificate
    if [ ! -f ${dir}/ca.key ]; then
      ${pkgs.openssl}/bin/openssl genrsa -out ${dir}/ca.key 2048
      ${pkgs.openssl}/bin/openssl req -new -x509 -days 3650 -key ${dir}/ca.key -out ${dir}/ca.pem -subj "/C=US/ST=California/L=San Francisco/O=Example/OU=IT/CN=Gateway-CA"
    fi

    # Generate server certificate
    if [ ! -f ${dir}/server.key ]; then
      ${pkgs.openssl}/bin/openssl genrsa -out ${dir}/server.key 2048
    fi

    ${pkgs.openssl}/bin/openssl req -new -key ${dir}/server.key -out ${dir}/server.csr -subj "/C=US/ST=California/L=San Francisco/O=Example/OU=IT/CN=Gateway-Server"

    ${pkgs.openssl}/bin/openssl x509 -req -in ${dir}/server.csr -CA ${dir}/ca.pem -CAkey ${dir}/ca.key -CAcreateserial -out ${dir}/server.crt -days 3650 -extensions v3_req

    # Generate client certificate
    if [ ! -f ${dir}/client.key ]; then
      ${pkgs.openssl}/bin/openssl genrsa -out ${dir}/client.key 2048
    fi

    ${pkgs.openssl}/bin/openssl req -new -key ${dir}/client.key -out ${dir}/client.csr -subj "/C=US/ST=California/L=San Francisco/O=Example/OU=IT/CN=Gateway-Client"

    ${pkgs.openssl}/bin/openssl x509 -req -in ${dir}/client.csr -CA ${dir}/ca.pem -CAkey ${dir}/ca.key -CAcreateserial -out ${dir}/client.crt -days 3650 -extensions v3_req

    # Generate DH parameters for EAP
    ${pkgs.openssl}/bin/openssl dhparam -out ${dir}/dh.pem 2048
  '';

  # Generate DH parameters for EAP
  mkDhParams = dir: ''
    ${pkgs.openssl}/bin/openssl dhparam -out ${dir}/dh.pem 2048
  '';

in
{
  inherit
    mkCertGenScript
    mkDhParams
    ;
}

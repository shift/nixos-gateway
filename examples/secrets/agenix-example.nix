# agenix configuration example
# This file demonstrates how to use agenix for secret management

# Example secrets.nix file for agenix
let
  root = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG5T1XvQ7TJZW7QZ9JQ8ZQ7ZQ9ZQ7ZQ9ZQ7ZQ9ZQ7ZQ9 root@gateway";
  nginx = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG5T1XvQ7TJZW7QZ9JQ8ZQ7ZQ9ZQ7ZQ9ZQ7ZQ9ZQ7ZQ9 nginx@gateway";
  prometheus = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG5T1XvQ7TJZW7QZ9JQ8ZQ7ZQ9ZQ7ZQ9ZQ7ZQ9ZQ7ZQ9 prometheus@gateway";
in
{
  # TLS certificate secret
  "gateway-tls.age".publicKeys = [
    root
    nginx
  ];

  # TLS private key secret
  "gateway-key.age".publicKeys = [
    root
    nginx
  ];

  # Database password secret
  "database-password.age".publicKeys = [ root ];

  # WireGuard private key
  "wireguard-key.age".publicKeys = [ root ];

  # WireGuard preshared keys
  "wireguard-peer1-psk.age".publicKeys = [ root ];
  "wireguard-peer2-psk.age".publicKeys = [ root ];

  # API keys
  "prometheus-api-key.age".publicKeys = [
    root
    prometheus
  ];
  "cloudflare-api-key.age".publicKeys = [ root ];

  # TSIG keys
  "dns-tsig-key.age".publicKeys = [ root ];
}

# Example encrypted secret files (these would be encrypted with agenix)
# gateway-tls.age: Encrypted TLS certificate
# gateway-key.age: Encrypted TLS private key
# database-password.age: Encrypted database password
# wireguard-key.age: Encrypted WireGuard private key
# etc.

# Usage in NixOS configuration:
# age.secrets.gateway-tls.file = ./secrets/gateway-tls.age;
# age.secrets.gateway-key.file = ./secrets/gateway-key.age;
#
# services.nginx.virtualHosts."example.com" = {
#   sslCertificate = age.secrets.gateway-tls.path;
#   sslCertificateKey = age.secrets.gateway-key.path;
# };

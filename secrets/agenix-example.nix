# Agenix Example Configuration
# This file demonstrates how to use agenix with the gateway secrets management

# First, install agenix:
# nix-env -iA nixpkgs.agenix

# Create age key pair:
# agenix --keygen

# Encrypt secrets:
# agenix -e gateway-secrets.nix

# Example secrets.nix file for agenix:
let
  # Import the gateway secrets configuration
  gatewaySecrets = import ./gateway-secrets.nix;

  # System users and their age public keys
  users = {
    root = "age1ql3z7hjy54pw3hyww5p5t067chj8q7s3x2lq5lfxp2e6p0x5m9ysqk7l9x";
    nginx = "age1qyq8z7hjy54pw3hyww5p5t067chj8q7s3x2lq5lfxp2e6p0x5m9ysqk7l9x";
    prometheus = "age1r2q8z7hjy54pw3hyww5p5t067chj8q7s3x2lq5lfxp2e6p0x5m9ysqk7l9x";
  };

  # Host keys
  hosts = {
    gateway01 = "age1examplehostkey1234567890abcdef1234567890abcdef";
    gateway02 = "age1examplehostkey0987654321fedcba0987654321fedcba";
  };

in
{
  # Gateway TLS certificate
  "gateway-secrets/tls/gateway.crt.age".publicKeys = [
    users.root
    users.nginx
    hosts.gateway01
    hosts.gateway02
  ];

  "gateway-secrets/tls/gateway.key.age".publicKeys = [
    users.root
    users.nginx
    hosts.gateway01
    hosts.gateway02
  ];

  # WireGuard VPN keys
  "gateway-secrets/vpn/wireguard/private.key.age".publicKeys = [
    users.root
    hosts.gateway01
    hosts.gateway02
  ];

  "gateway-secrets/vpn/wireguard/peer1-psk.age".publicKeys = [
    users.root
    hosts.gateway01
    hosts.gateway02
  ];

  "gateway-secrets/vpn/wireguard/peer2-psk.age".publicKeys = [
    users.root
    hosts.gateway01
    hosts.gateway02
  ];

  # DNS TSIG keys
  "gateway-secrets/dns/ddns-key.age".publicKeys = [
    users.root
    hosts.gateway01
    hosts.gateway02
  ];

  # Monitoring API keys
  "gateway-secrets/monitoring/prometheus-remote-key.age".publicKeys = [
    users.root
    users.prometheus
    hosts.gateway01
    hosts.gateway02
  ];

  "gateway-secrets/monitoring/grafana-admin-key.age".publicKeys = [
    users.root
    users.prometheus
    hosts.gateway01
    hosts.gateway02
  ];

  # Database passwords
  "gateway-secrets/databases/metrics-db-password.age".publicKeys = [
    users.root
    users.prometheus
    hosts.gateway01
    hosts.gateway02
  ];

  "gateway-secrets/databases/logs-db-password.age".publicKeys = [
    users.root
    users.prometheus
    hosts.gateway01
    hosts.gateway02
  ];
}

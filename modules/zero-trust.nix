{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.gateway.zeroTrust;
  trustEngine = import ../lib/trust-engine.nix { inherit pkgs; };
in
{
  options.services.gateway.zeroTrust = {
    enable = mkEnableOption "Zero Trust Microsegmentation Engine";

    defaultPolicy = mkOption {
      type = types.enum [
        "accept"
        "drop"
      ];
      default = "drop";
      description = "Default policy for traffic not explicitly trusted";
    };
  };

  config = mkIf cfg.enable {
    # Disable Reverse Path Filtering to avoid silent drops
    networking.firewall.checkReversePath = false;
    boot.kernel.sysctl = {
      "net.ipv4.conf.all.rp_filter" = 0;
      "net.ipv4.conf.default.rp_filter" = 0;
      "net.ipv4.conf.eth1.rp_filter" = 0;
    };

    # Disable standard firewall to avoid conflicts/overrides
    networking.firewall.enable = false;

    # Ensure NFTables kernel modules are loaded
    boot.kernelModules = [
      "nf_tables"
      "nf_tables_ipv4"
      "nf_tables_ipv6"
    ];

    # 1. NFTables Configuration
    networking.nftables.enable = true;
    networking.nftables.flushRuleset = true;
    networking.nftables.tables = {
      zero_trust = {
        family = "inet";
        content = ''
          set trusted_devices {
            type ipv4_addr
            flags interval
          }

          set restricted_devices {
            type ipv4_addr
            flags interval
          }

          set threat_intel_ip_block {
            type ipv4_addr
            flags interval
          }

          set threat_intel_domain_block {
            type ipv4_addr 
            flags interval
            # Note: For domain blocking in NFTables, we usually use sets of IP addresses
            # resolved from domains, or need to use distinct sets if doing DNS packet inspection.
            # For this MVP, we will assume domain blocklist results in IPs being added here.
          }

          counter dropped_packets {}
          counter forward_dropped_packets {}

          chain input {
            type filter hook input priority filter; policy drop;
            
            # Log dropped packets for visibility
            log prefix "NFT-DROP: " flags all
            counter name "dropped_packets"
            
            # Allow loopback
            iifname "lo" accept
            
            # Allow established/related
            ct state established,related accept
            
            # Allow ICMP for network diagnostics
            # ip protocol icmp accept
            # ip6 nexthdr icmpv6 accept
            
            # Zero Trust Logic
            ip saddr @threat_intel_ip_block drop
            ip daddr @threat_intel_ip_block drop
            ip saddr @threat_intel_domain_block drop
            ip daddr @threat_intel_domain_block drop
            
            ip saddr @trusted_devices accept
            ip saddr @restricted_devices drop
          }

          # Chain for forwarding traffic
          chain forward {
            type filter hook forward priority filter; policy drop;
            
            # Zero Trust Logic for Forwarding
            ip saddr @threat_intel_ip_block drop
            ip daddr @threat_intel_ip_block drop
            ip saddr @threat_intel_domain_block drop
            ip daddr @threat_intel_domain_block drop
            
            ip saddr @trusted_devices accept
            ip saddr @restricted_devices drop
            
            counter name "forward_dropped_packets" drop
          }
        '';
      };
    };

    # 2. Systemd Service for Trust Engine
    systemd.services.zero-trust-engine = {
      description = "Zero Trust Microsegmentation Engine";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        ExecStart = "${trustEngine}/bin/zero-trust-engine";
        Restart = "always";
        StateDirectory = "zero-trust";
        # Ensure the directory is writable
        ReadWritePaths = [ "/var/lib/zero-trust" ];
      };
      path = [ pkgs.nftables ];
    };

    # Create initial config directory
    systemd.tmpfiles.rules = [
      "d /etc/zero-trust 0755 root root -"
      "f /etc/zero-trust/config.json 0644 root root - {}"
      "d /var/lib/zero-trust 0755 root root -"
    ];
  };
}

{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.services.gateway;
  enabled = cfg.enable or true;

  # Import schema normalization
  schemaNormalization = import ../lib/schema-normalization.nix { inherit lib; };

  networkData = schemaNormalization.normalizeNetworkData (cfg.data.network or { });
in
{
  options.services.gateway = {
    security = {
      enable = lib.mkEnableOption "NixOS Gateway Security";

      engine = lib.mkOption {
        type = lib.types.enum [
          "fail2ban"
          "crowdsec"
        ];
        default = "fail2ban";
        description = "Security engine to use for intrusion prevention";
      };
    };
  };

  config = lib.mkIf (enabled && cfg.security.enable) {
    # SSH hardening
    services.openssh = {
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        X11Forwarding = false;
        MaxAuthTries = 3;
        MaxSessions = 10;
        ClientAliveInterval = 300;
        ClientAliveCountMax = 2;
      };

      extraConfig = ''
        # Rate limiting
        MaxStartups 10:30:60
      '';
    };

    # Fail2ban for SSH protection (conditional)
    services.fail2ban = lib.mkIf (cfg.security.engine == "fail2ban") {
      enable = true;
      maxretry = 5;
      ignoreIP = [
        "127.0.0.1/8"
        (schemaNormalization.getSubnetNetwork networkData "lan")
        "::1"
        (
          let
            lanSubnet = schemaNormalization.findSubnet networkData "lan";
          in
          if lanSubnet != null && lanSubnet ? ipv6 && lanSubnet.ipv6 ? prefix then
            lanSubnet.ipv6.prefix
          else
            "2001:db8::/48"
        )
      ];

      jails = {
        sshd = lib.mkForce ''
          enabled = true
          port = ssh
          filter = sshd
          maxretry = 3
          findtime = 600
          bantime = 3600
        '';
      };
    };

    # Kernel hardening via sysctl
    boot.kernel.sysctl = {
      # IP forwarding already enabled in network.nix

      # TCP/IP stack hardening
      "net.ipv4.tcp_syncookies" = 1;
      "net.ipv4.tcp_syn_retries" = 2;
      "net.ipv4.tcp_synack_retries" = 2;
      "net.ipv4.tcp_max_syn_backlog" = 4096;

      # IP spoofing protection
      "net.ipv4.conf.all.rp_filter" = 1;
      "net.ipv4.conf.default.rp_filter" = 1;

      # Ignore ICMP redirects
      "net.ipv4.conf.all.accept_redirects" = 0;
      "net.ipv4.conf.default.accept_redirects" = 0;
      "net.ipv4.conf.all.secure_redirects" = 0;
      "net.ipv4.conf.default.secure_redirects" = 0;
      "net.ipv6.conf.all.accept_redirects" = 0;
      "net.ipv6.conf.default.accept_redirects" = 0;

      # Don't send ICMP redirects
      "net.ipv4.conf.all.send_redirects" = 0;
      "net.ipv4.conf.default.send_redirects" = 0;

      # Ignore ICMP ping requests
      "net.ipv4.icmp_echo_ignore_all" = 0;
      "net.ipv4.icmp_echo_ignore_broadcasts" = 1;

      # Ignore bogus ICMP error responses
      "net.ipv4.icmp_ignore_bogus_error_responses" = 1;

      # Log martian packets
      "net.ipv4.conf.all.log_martians" = 1;
      "net.ipv4.conf.default.log_martians" = 1;

      # TCP hardening
      "net.ipv4.tcp_timestamps" = 1;
      "net.ipv4.tcp_fin_timeout" = 15;
      "net.ipv4.tcp_keepalive_time" = 300;
      "net.ipv4.tcp_keepalive_probes" = 5;
      "net.ipv4.tcp_keepalive_intvl" = 15;

      # Connection tracking
      "net.netfilter.nf_conntrack_max" = 262144;
      "net.netfilter.nf_conntrack_tcp_timeout_established" = 432000;
      "net.netfilter.nf_conntrack_tcp_timeout_time_wait" = 120;

      # BBR congestion control
      "net.core.default_qdisc" = "fq";
      "net.ipv4.tcp_congestion_control" = "bbr";

      # Network buffer tuning
      "net.core.rmem_max" = 134217728;
      "net.core.wmem_max" = 134217728;
      "net.core.rmem_default" = 1048576;
      "net.core.wmem_default" = 1048576;
      "net.core.optmem_max" = 40960;
      "net.ipv4.tcp_rmem" = "4096 87380 67108864";
      "net.ipv4.tcp_wmem" = "4096 65536 67108864";

      # Suricata tuning
      "net.core.netdev_max_backlog" = 10000;

      # IPv6 hardening
      "net.ipv6.conf.all.accept_source_route" = 0;
      "net.ipv6.conf.default.accept_source_route" = 0;

      # Kernel hardening
      "kernel.dmesg_restrict" = 1;
      "kernel.kptr_restrict" = 2;
      "kernel.yama.ptrace_scope" = 1;
      "kernel.unprivileged_bpf_disabled" = 1;
      "kernel.unprivileged_userns_clone" = 0;

      # File system hardening
      "fs.protected_hardlinks" = 1;
      "fs.protected_symlinks" = 1;
      "fs.protected_fifos" = 2;
      "fs.protected_regular" = 2;
    };

    # Additional security modules
    boot.kernelModules = [ "tcp_bbr" ];

    # Harden systemd services
    systemd.coredump.enable = false;

    security.protectKernelImage = true;
  };
}

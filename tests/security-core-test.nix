{ pkgs, ... }:
{
  name = "security-core-test";
  nodes.machine =
    { pkgs, ... }:
    {
      imports = [
        ../modules/default.nix
        ../modules/security.nix
        ../modules/network.nix
        ../modules/dhcp.nix
      ];

      # Minimal config to satisfy assertions in network/dhcp if needed
      services.gateway.enable = true;
      services.gateway.interfaces.lan = "eth1";
      services.gateway.interfaces.wan = "eth0";

      # Explicitly enable security with fail2ban
      services.gateway.security.enable = true;
      services.gateway.security.engine = "fail2ban";

      # Enable SSH so we can check its config
      services.openssh.enable = true;
    };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    # Check if fail2ban is running (security enabled)
    machine.succeed("systemctl is-active fail2ban.service")

    # Check if sysctl settings are applied
    machine.succeed("sysctl net.ipv4.tcp_syncookies | grep 1")
    machine.succeed("sysctl net.ipv4.icmp_echo_ignore_broadcasts | grep 1")

    # Check SSH hardening - explicitly check sshd is running first
    machine.succeed("systemctl is-active sshd.service")
    machine.succeed("grep 'PermitRootLogin no' /etc/ssh/sshd_config")
  '';
}

{ pkgs, ... }:

pkgs.testers.nixosTest {
  name = "test-ssh-api";

  nodes.gateway =
    { config, ... }:
    {
      services.openssh = {
        enable = true;
        # Test new SSH settings API
        settings = {
          PasswordAuthentication = false;
          PermitRootLogin = "prohibit-password";
          Ciphers = [ "chacha20-poly1305@openssh.com" ];
          X11Forwarding = false;
          GatewayPorts = "no";
          KexAlgorithms = [ "curve25519-sha256@libssh.org" ];
          LogLevel = "VERBOSE";
          UseDns = false;
        };
      };
    };

  testScript = ''
    start_all()
    gateway.wait_for_unit("multi-user.target")
    gateway.succeed("test -f /etc/ssh/sshd_config")
    gateway.succeed("systemctl is-active sshd")
  '';
}

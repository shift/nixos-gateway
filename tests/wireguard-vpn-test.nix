{ pkgs, ... }:

let
  serverConfig = {
    services.gateway = {
      wireguard = {
        enable = true;
        server = {
          interface = "wg0";
          address = "10.100.0.1/24";
        };

        automation = {
          keyRotation = {
            enable = true;
            interval = "90";
          };
          peerManagement = {
            enable = true;
            watchDirectory = "/etc/wireguard/peers.d";
          };
        };
        monitoring.enable = true;
      };
      interfaces.wan = "eth1";
    };

    networking.nat.enable = true;
    networking.nat.externalInterface = "eth1";
    networking.nat.internalInterfaces = [ "wg0" ];
    networking.firewall.enable = true;
  };

in
{
  name = "wireguard-vpn-automation-test";

  nodes.machine =
    { config, pkgs, ... }:
    {
      imports = [ ../modules/vpn.nix ];

      options.services.gateway.interfaces.wan = pkgs.lib.mkOption {
        type = pkgs.lib.types.str;
        default = "eth1";
      };

      config = serverConfig;
    };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    # 1. Verify WireGuard interface creation
    machine.wait_for_unit("wireguard-wg0.service")
    machine.succeed("ip link show wg0")

    # 2. Verify Key Generation
    machine.succeed("test -f /var/lib/wireguard/wg0.key")

    # 3. Verify Automation Services
    machine.succeed("systemctl list-timers | grep wireguard-wg0-key-rotation")

    # Verify Watcher
    machine.succeed("mkdir -p /etc/wireguard/peers.d")
    machine.succeed("systemctl start wireguard-wg0-watcher.path")
    # Verify the path unit is active
    machine.succeed("systemctl is-active wireguard-wg0-watcher.path")

    # 4. Verify NAT Rules
    rules = machine.succeed("iptables-save")
    assert "-A POSTROUTING -s 10.100.0.0/24 -o eth1 -j MASQUERADE" in rules
  '';
}

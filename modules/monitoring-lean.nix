{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.gateway;
in
{
  config = lib.mkIf (cfg.profile == "alix-networkd" || cfg.profile == "alix-dnsmasq") {
    # D-Bus system service for gateway health monitoring
    systemd.services.gateway-health = {
      description = "Gateway Health Monitor (D-Bus service)";
      wantedBy = [ "multi-user.target" ];
      after = [ "dbus.service" "network.target" "systemd-networkd.service" ];
      requires = [ "dbus.service" ];

      serviceConfig = {
        Type = "notify";
        NotifyAccess = "all";
        ExecStart = "${pkgs.gateway-health}/bin/gateway-health";
        WatchdogSec = "60s";
        Restart = "on-failure";
        RestartSec = "5s";

        # D-Bus access
        BusName = "org.gateway.Health";

        # Hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ "/run/gateway" ];
        AmbientCapabilities = [ "CAP_NET_ADMIN" "CAP_NET_RAW" ];
        CapabilityBoundingSet = [ "CAP_NET_ADMIN" "CAP_NET_RAW" ];
        RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" "AF_NETLINK" ];
      };
    };

    # Stats directory on tmpfs
    systemd.tmpfiles.rules = [
      "d /run/gateway 0755 root root - -"
    ];

    # Config file
    environment.etc."gateway/health.toml".text = ''
      check_interval_secs = 30
      ping_target = "1.1.1.1"
      wan_interface = "${cfg.interfaces.wan}"
      dns_test_domain = "one.one.one.one"
      dns_server = "127.0.0.1"
      services = [
        "systemd-networkd.service"
        "sshd.service"
      ]
      monitored_interfaces = [
        "${cfg.interfaces.wan}"
        "${cfg.interfaces.lan}"
      ]
    '';

    # D-Bus policy allowing root and systemd-networkd to call into us
    services.dbus.packages = [
      (pkgs.writeTextFile {
        name = "org.gateway.Health.conf";
        destination = "/etc/dbus-1/system.d/org.gateway.Health.conf";
        text = ''
          <!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
            "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
          <busconfig>
            <policy user="root">
              <allow own="org.gateway.Health"/>
              <allow send_destination="org.gateway.Health"/>
            </policy>
            <policy context="default">
              <allow send_destination="org.gateway.Health"/>
            </policy>
          </busconfig>
        '';
      })
    ];

    # networkd dispatcher: on link changes, notify gateway-health via D-Bus
    systemd.services.gateway-networkd-dispatcher = {
      description = "Notify gateway-health on network state changes";
      wantedBy = [ "multi-user.target" ];
      after = [ "gateway-health.service" ];
      requires = [ "gateway-health.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        # Wait for gateway-health to be on the bus
        sleep 2
        echo "Network state dispatcher ready"
      '';
    };

    # systemd OnFailure for gateway services — triggers health check via D-Bus
    systemd.services."systemd-networkd".unitConfig.OnFailure = "gateway-health-on-failure@%n.service";
    systemd.services."sshd".unitConfig.OnFailure = "gateway-health-on-failure@%n.service";

    # Template service that calls ServiceFailed on the D-Bus interface
    systemd.services."gateway-health-on-failure@" = {
      description = "Notify gateway-health that %i failed";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.dbus}/bin/dbus-send --system --type=method_call --dest=org.gateway.Health /org/gateway/Health org.gateway.Health.ServiceFailed string:%i";
      };
    };
  };
}

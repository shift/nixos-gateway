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
  options.services.gateway.alix = {
    storage = {
      scheme = lib.mkOption {
        type = lib.types.enum [ "ext4-rw" "ext4-noatime" ];
        default = "ext4-noatime";
        description = ''
          Storage scheme for the ALIX CompactFlash card.
          - ext4-rw: Standard read-write. Simple, but risks CF corruption on power loss.
          - ext4-noatime: Read-write with noatime+discard. Minimizes CF writes.
          squashfs-overlay is planned but requires a custom image builder (not yet implemented).
        '';
      };

      configPartition = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Create a mount unit for the FAT32 config partition";
      };
    };
  };

  config = lib.mkIf (cfg.profile == "alix-networkd" || cfg.profile == "alix-dnsmasq") (
    let
      storage = cfg.alix.storage;
    in
    lib.mkMerge [
      # ── Common to all schemes ──
      {
        # No swap partition on CF — use zram (configured in hosts/alix.nix)
        swapDevices = lib.mkForce [ ];

        # Minimize journal writes — volatile storage
        services.journald.extraConfig = lib.mkDefault ''
          Storage=volatile
          Compress=yes
          SystemMaxUse=10M
          MaxFileSec=1day
        '';

        # Runtime state directories
        systemd.tmpfiles.rules = [
          "d /run/gateway 0755 root root - -"
          "d /var/lib/dnsmasq 0755 dnsmasq dnsmasq - -"
          "d /var/lib/hostapd 0755 root root - -"
          "d /var/lib/wireguard 0700 root root - -"
        ];
      }

      # ── ext4-rw: standard ──
      (lib.mkIf (storage.scheme == "ext4-rw") {
        fileSystems."/" = {
          options = [ "noatime" "discard" "errors=remount-ro" ];
        };
      })

      # ── ext4-noatime: aggressive CF protection ──
      (lib.mkIf (storage.scheme == "ext4-noatime") {
        fileSystems."/" = {
          options = [ "noatime" "nodiratime" "discard" "errors=remount-ro" "commit=60" ];
        };

        # Periodic TRIM for CF
        services.fstrim = {
          enable = true;
          interval = "weekly";
        };
      })

      # ── Config partition (common to all schemes) ──
      (lib.mkIf storage.configPartition {
        # Mount the FAT32 config partition for gateway-setup to read
        # Partition 2 on the CF card (created by the image builder)
        fileSystems."/mnt/config" = {
          device = "/dev/disk/by-label/CONFIG";
          fsType = "vfat";
          options = [ "noauto" "ro" "nofail" "noexec" "nodev" "nosuid" ];
        };

        # Populate /etc/gateway from config partition on boot
        systemd.services.gateway-populate-config = {
          description = "Populate gateway config from config partition";
          wantedBy = [ "multi-user.target" ];
          after = [ "local-fs.target" ];
          before = [
            "systemd-networkd.service"
            "gateway-health.service"
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            CONFIG_DEV="/dev/disk/by-label/CONFIG"

            if [ -b "$CONFIG_DEV" ] || [ -b "/dev/sda2" ]; then
              DEV="''${CONFIG_DEV:-/dev/sda2}"
              mkdir -p /mnt/config
              mount -t vfat -o ro "$DEV" /mnt/config 2>/dev/null || true

              if [ -f /mnt/config/gateway.toml ]; then
                echo "Found gateway config on config partition"
                mkdir -p /etc/gateway
                ${pkgs.gateway-setup}/bin/gateway-setup \
                  --config /mnt/config/gateway.toml \
                  --output /etc/gateway
              fi

              umount /mnt/config 2>/dev/null || true
            else
              echo "No config partition found, using NixOS declarative config"
            fi
          '';
        };
      })
    ]
  );
}

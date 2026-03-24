{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.services.gateway.disk or { };
in
{
  config = lib.mkIf (cfg.enable or false) (
    lib.mkMerge [
      # Disko configuration (only if disko module is available and enabled)
      (lib.mkIf (cfg.enable && (config.disko.enable or false) && (builtins.hasAttr "disko" config)) {
        disko.devices.disk.primary = {
          device = cfg.device or "/dev/null";
          type = "disk";
          content = {
            type = "gpt";
            partitions = {
              ESP = {
                type = "EF00";
                size = cfg.bootSize or "500M";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot";
                };
              };
              swap = {
                size = cfg.swapSize or "8G";
                content = {
                  type = "swap";
                };
              };
              root = {
                size = "100%";
                content =
                  if (cfg.luks.enable or false) then
                    {
                      type = "luks";
                      name = cfg.luks.name or "cryptroot";
                      settings = {
                        allowDiscards = true;
                        bypassWorkqueues = true;
                      };
                      content = {
                        type = "btrfs";
                        extraArgs = [ "-f" ];
                        subvolumes = {
                          "@root" = {
                            mountpoint = "/";
                            mountOptions = [
                              "compress=${cfg.btrfs.compression or "zstd"}"
                            ]
                            ++ (cfg.btrfs.extraMountOptions or [ "noatime" ]);
                          };
                          "@persist" = {
                            mountpoint = "/persist";
                            mountOptions = [
                              "compress=${cfg.btrfs.compression or "zstd"}"
                            ]
                            ++ (cfg.btrfs.extraMountOptions or [ "noatime" ]);
                          };
                          "@nix" = {
                            mountpoint = "/nix";
                            mountOptions = [
                              "compress=${cfg.btrfs.compression or "zstd"}"
                              "noatime"
                            ];
                          };
                        };
                      };
                    }
                  else
                    {
                      type = "btrfs";
                      extraArgs = [ "-f" ];
                      subvolumes = {
                        "@root" = {
                          mountpoint = "/";
                          mountOptions = [
                            "compress=${cfg.btrfs.compression or "zstd"}"
                          ]
                          ++ (cfg.btrfs.extraMountOptions or [ "noatime" ]);
                        };
                        "@persist" = {
                          mountpoint = "/persist";
                          mountOptions = [
                            "compress=${cfg.btrfs.compression or "zstd"}"
                          ]
                          ++ (cfg.btrfs.extraMountOptions or [ "noatime" ]);
                        };
                        "@nix" = {
                          mountpoint = "/nix";
                          mountOptions = [
                            "compress=${cfg.btrfs.compression or "zstd"}"
                            "noatime"
                          ];
                        };
                      };
                    };
              };
            };
          };
        };
      })

      # General boot and system configuration (always applied when disk config is enabled)
      {
        boot.initrd.availableKernelModules = lib.mkIf (cfg.luks.enable or false) [
          "tpm_tis"
          "tpm_crb"
        ];

        boot.initrd.systemd.enable = lib.mkIf (
          (cfg.luks.enable or false) && (cfg.luks.tpm2.enable or false)
        ) true;

        boot.initrd.luks.devices.${cfg.luks.name or "cryptroot"} = lib.mkIf (cfg.luks.enable or false) {
          device = "/dev/disk/by-partlabel/disk-primary-root";
          crypttabExtraOpts = lib.mkIf (cfg.luks.tpm2.enable or false) [ "tpm2-device=auto" ];
        };

        security.tpm2 = lib.mkIf ((cfg.luks.enable or false) && (cfg.luks.tpm2.enable or false)) {
          enable = true;
          pkcs11.enable = true;
          tctiEnvironment.enable = true;
        };

        boot.loader = {
          systemd-boot.enable = lib.mkDefault true;
          efi.canTouchEfiVariables = lib.mkDefault true;
        };

        boot.supportedFilesystems = [ "btrfs" ];

        # systemd.services.wipe-root = {
        #   description = "Wipe root subvolume to blank state";
        #   wantedBy = [ "local-fs.target" ];
        #   after = [ "local-fs-pre.target" ];
        #   before = [ "local-fs.target" ];
        #   unitConfig.DefaultDependencies = false;
        #   serviceConfig.Type = "oneshot";
        #
        #   script = ''
        #     mkdir -p /mnt
        #
        #     # Mount btrfs root
        #     ${
        #       if (cfg.luks.enable or false) then
        #         "mount -o subvol=/ /dev/mapper/${cfg.luks.name or "cryptroot"} /mnt"
        #       else
        #         "mount -o subvol=/ /dev/disk/by-partlabel/disk-primary-root /mnt"
        #     }
        #
        #     # Check if blank snapshot exists
        #     if [[ -e /mnt/@root-blank ]]; then
        #       # Delete current root subvolume
        #       ${pkgs.btrfs-progs}/bin/btrfs subvolume delete /mnt/@root
        #       # Restore from blank snapshot
        #       ${pkgs.btrfs-progs}/bin/btrfs subvolume snapshot /mnt/@root-blank /mnt/@root
        #     else
        #       # Create blank snapshot on first boot
        #       ${pkgs.btrfs-progs}/bin/btrfs subvolume snapshot /mnt/@root /mnt/@root-blank
        #     fi
        #
        #     umount /mnt
        #   '';
        # };
      }
    ]
  );
}

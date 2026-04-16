# ALIX disk image builder
#
# Produces a raw MBR image suitable for `dd` to CompactFlash:
#   - Single ext4 partition with extlinux bootloader
#   - Sized to fit the NixOS closure + boot files + extra free space
#   - No firmware partition, no LVM, no UEFI
#
# Build with:
#   nix build .#nixosConfigurations.alix-networkd.config.system.build.alixImage
#
# Flash with:
#   zstd -d alix.img.zst | sudo dd of=/dev/sdX bs=4M status=progress
{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.alixImage;

  # Build the ext4 rootfs using nixpkgs' helper (works in sandbox)
  rootfs = pkgs.callPackage (pkgs.path + "/nixos/lib/make-ext4-fs.nix") {
    storePaths = [ config.system.build.toplevel ];
    compressImage = false;
    populateImageCommands = ''
      # Install extlinux boot files into /boot
      ${config.boot.loader.generic-extlinux-compatible.populateCmd} \
        -c ${config.system.build.toplevel} -d ./files/boot
    '';
    volumeLabel = cfg.label;
  };
in
{
  options.alixImage = {
    enable = lib.mkEnableOption "ALIX disk image builder";

    imageName = lib.mkOption {
      type = lib.types.str;
      default = "alix-${config.system.nixos.label}-${pkgs.stdenv.hostPlatform.system}.img";
    };

    label = lib.mkOption {
      type = lib.types.str;
      default = "nixos";
      description = "ext4 filesystem label for the root partition.";
    };

    extraSizeMB = lib.mkOption {
      type = lib.types.int;
      default = 32;
      description = "Extra free space in MiB to leave on the partition.";
    };

    compress = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Compress the image with zstd.";
    };
  };

  config = lib.mkIf cfg.enable {
    system.build.alixImage = pkgs.callPackage (
      {
        stdenv,
        e2fsprogs,
        util-linux,
        syslinux,
        zstd,
      }:
      stdenv.mkDerivation {
        name = cfg.imageName;

        nativeBuildInputs = [
          e2fsprogs
          util-linux
          syslinux
          zstd
        ];

        buildCommand = ''
          mkdir -p $out/nix-support $out/image

          IMG_NAME="${cfg.imageName}"
          ROOTFS="${rootfs}"

          echo "Root filesystem size:"
          du -h $ROOTFS

          # Create raw image: 1MiB alignment gap + root partition
          rootSizeBlocks=$(du -B 512 --apparent-size $ROOTFS | awk '{ print $1 }')
          gapBlocks=$((1 * 1024 * 1024 / 512))  # 1MiB
          totalBlocks=$((gapBlocks + rootSizeBlocks))
          truncate -s $((totalBlocks * 512)) alix.img

          # MBR partition table: single Linux partition starting at 1MiB
          sfdisk --no-reread --no-tell-kernel alix.img <<EOF
              label: dos

              start=1M, type=83, bootable
          EOF

          # Write root filesystem into the partition
          eval $(partx alix.img -o START,SECTORS --nr 1 --pairs)
          dd conv=notrunc if=$ROOTFS of=alix.img seek=$START count=$SECTORS status=progress

          # Install syslinux MBR boot code (loads the active partition's boot sector)
          dd if=${syslinux}/share/syslinux/mbr.bin of=alix.img bs=440 count=1 conv=notrunc

          ${lib.optionalString cfg.compress ''
            zstd -T$NIX_BUILD_CORES -3 alix.img -o $out/image/$IMG_NAME.zst
            echo "file sd-image $out/image/$IMG_NAME.zst" >> $out/nix-support/hydra-build-products
          ''}

          ${lib.optionalString (!cfg.compress) ''
            cp alix.img $out/image/$IMG_NAME
            echo "file sd-image $out/image/$IMG_NAME" >> $out/nix-support/hydra-build-products
          ''}

          # Report sizes
          FINAL=$out/image/*
          echo "" >> $GITHUB_STEP_SUMMARY || true
          du -h $FINAL || true
        '';
      }
    ) { };
  };
}

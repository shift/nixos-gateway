# ALIX disk image builder
#
# Produces a raw MBR image suitable for `dd` to CompactFlash:
#   - Partition 1: ext4 root (NixOS system + boot)
#   - Partition 2: FAT32 config (gateway.toml, user-editable)
#   - syslinux MBR boot code
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

    configSizeMB = lib.mkOption {
      type = lib.types.int;
      default = 16;
      description = "Size of the FAT32 config partition in MiB.";
    };

    extraSizeMB = lib.mkOption {
      type = lib.types.int;
      default = 32;
      description = "Extra free space in MiB to leave on the root partition.";
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
        dosfstools,
        mtools,
        util-linux,
        syslinux,
        zstd,
      }:
      stdenv.mkDerivation {
        name = cfg.imageName;

        nativeBuildInputs = [
          e2fsprogs
          dosfstools
          mtools
          util-linux
          syslinux
          zstd
        ];

        buildCommand = ''
          mkdir -p $out/nix-support $out/image

          IMG_NAME="${cfg.imageName}"
          ROOTFS="${rootfs}"
          CONFIG_SIZE_MB=${toString cfg.configSizeMB}

          echo "Root filesystem size:"
          du -h $ROOTFS

          # ── Calculate partition layout ──
          rootSizeBlocks=$(du -B 512 --apparent-size $ROOTFS | awk '{ print $1 }')
          configSizeBlocks=$((CONFIG_SIZE_MB * 1024 * 1024 / 512))
          gapSectors=$((1 * 1024 * 1024 / 512))  # 1MiB alignment

          # Total image: gap + root + config
          totalBlocks=$((gapSectors + rootSizeBlocks + configSizeBlocks))
          truncate -s $((totalBlocks * 512)) alix.img

          # ── MBR partition table ──
          # Partition 1: ext4 root (bootable)
          # Partition 2: FAT32 config (partlabel="config" via MBR type=0x0c)
          sfdisk --no-reread --no-tell-kernel alix.img <<EOF
              label: dos

              start=1M, type=83, bootable
              type=0c
          EOF

          echo "Partition table:"
          sfdisk -d alix.img

          # ── Write root filesystem (partition 1) ──
          eval $(partx alix.img -o START,SECTORS --nr 1 --pairs)
          dd conv=notrunc if=$ROOTFS of=alix.img seek=$START count=$SECTORS status=progress

          # ── Create FAT32 config partition (partition 2) ──
          eval $(partx alix.img -o START,SECTORS --nr 2 --pairs)
          # Create a small FAT32 image
          truncate -s $((SECTORS * 512)) config.part
          mkfs.vfat -F 32 -n CONFIG config.part

          # Write a README so the partition isn't empty
          cat > readme.txt <<'README'
          Place gateway.toml in this partition to configure the gateway.
          See examples/alix-gateway.toml for the configuration format.
          README
          mcopy -i config.part readme.txt ::readme.txt

          # Verify
          fsck.vfat -vn config.part

          # Write config partition into the image
          dd conv=notrunc if=config.part of=alix.img seek=$START count=$SECTORS

          # ── Install syslinux MBR boot code ──
          dd if=${syslinux}/share/syslinux/mbr.bin of=alix.img bs=440 count=1 conv=notrunc

          # ── Compress and output ──
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

{
  config,
  pkgs,
  lib,
  ...
}:

{
  # === Platform ===
  nixpkgs.system = "i686-linux";
  nixpkgs.hostPlatform = lib.mkDefault "i686-linux";

  # === Boot: BIOS/MBR only (no UEFI on ALIX) ===
  boot.loader.grub = {
    enable = true;
    version = 2;
    device = "/dev/sda"; # CompactFlash card
    extraConfig = ''
      serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1
      terminal_input serial
      terminal_output serial
    '';
  };

  boot.kernelParams = [
    "console=ttyS0,115200n8"
    "panic=10"
    "quiet"
    "loglevel=3"
  ];

  # === Custom kernel (built-in drivers only, no module loader) ===
  # See config/kernel/alix.config for the full kernel config
  boot.kernelPackages = lib.mkDefault (
    pkgs.linuxPackagesFor (
      pkgs.linuxManualConfig {
        inherit (pkgs.linux_6_6) src;
        version = pkgs.linux_6_6.version;
        configfile = ../config/kernel/alix.config;
        allowImportFromDerivation = true;
      }
    )
  );

  # No module loading - everything is built-in
  boot.kernelModules = lib.mkForce [ ];
  boot.extraModulePackages = lib.mkForce [ ];
  boot.initrd.availableKernelModules = lib.mkForce [ ];
  boot.initrd.kernelModules = lib.mkForce [ ];

  # Minimal initramfs (or skip entirely with monolithic kernel)
  boot.initrd.enable = lib.mkDefault true;

  # === Serial console ===
  systemd.services."serial-getty@ttyS0" = {
    enable = true;
    wantedBy = [ "getty.target" ];
    serviceConfig.Restart = "always";
  };

  # === Memory conservation ===
  services.journald.extraConfig = ''
    Storage=volatile
    Compress=yes
    SystemMaxUse=10M
    MaxFileSec=1day
  '';

  # zram swap - compressed swap in RAM (better than nothing on 256MB)
  zramSwap = {
    enable = true;
    memoryPercent = 25; # 64MB on 256MB system
    algorithm = "lzo-rle"; # Fastest on Geode LX (no AES, no SIMD)
  };

  boot.tmp.useTmpfs = true;
  boot.tmp.tmpfsSize = "50%";

  # === CF-friendly storage ===
  # No swap partition on CF (use zram instead)
  swapDevices = [ ];

  # Mount root with noatime to minimize CF writes
  fileSystems."/" = {
    options = [ "noatime" "discard" ];
  };

  # === Documentation/locale stripping (1GB CF) ===
  documentation.enable = false;
  documentation.man.enable = false;
  documentation.man.generateCaches = false;
  documentation.info.enable = false;
  documentation.doc.enable = false;
  documentation.nixos.enable = false;

  i18n.supportedLocales = [ "en_US.UTF-8/UTF-8" ];
  i18n.defaultLocale = "en_US.UTF-8";

  # No nix on target (deployment-only device, all builds in GHA)
  # Don't register nix-daemon, don't include nix tools
  nix.settings.auto-optimise-store = false;
  services.nix-gc.enable = lib.mkForce false;
  # Exclude nix from system packages — it's a deployment-only target
  # The closure will still contain nix due to system activation scripts,
  # but the daemon won't run builds

  # Strip unnecessary packages
  fonts.fontconfig.enable = false;
  sound.enable = false;
  services.xserver.enable = false;

  # === Conntrack tuning for low memory ===
  boot.kernel.sysctl = {
    "net.netfilter.nf_conntrack_max" = 8192;
    "net.netfilter.nf_conntrack_tcp_timeout_established" = 7200; # 2h instead of 5d
    "vm.swappiness" = 60; # Prefer swapping to zram over killing processes
    "vm.vfs_cache_pressure" = 200; # Reclaim dentry/inode caches aggressively
    "vm.dirty_ratio" = 5; # Write back early (CF protection)
    "vm.dirty_background_ratio" = 2;
  };

  # === Minimal system packages ===
  environment.systemPackages = with pkgs; [
    coreutils
    bash
    openssh
    iputils
    conntrack-tools
    nftables
    wireguard-tools
    hostapd
    vim-small
  ];

  # === SSH access ===
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes"; # Serial console access only anyway
      PasswordAuthentication = true; # For initial setup
    };
  };

  # === Time ===
  time.timeZone = "UTC";
  services.ntp.enable = true; # Lightweight ntpd, not chrony

  # === Networking ===
  networking.useDHCP = false;
  networking.useNetworkd = true;
  networking.networkmanager.enable = false;
  systemd.network.enable = true;

  # Single core — irqbalance is pointless
  services.irqbalance.enable = lib.mkForce false;

  # === Gateway profile selection ===
  # Set this in a host-specific overlay or pass via module args
  # services.gateway.profile = "alix-networkd"; # or "alix-dnsmasq"
}

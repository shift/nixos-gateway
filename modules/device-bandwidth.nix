{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.gateway.deviceBandwidth;
  gatewayCfg = config.services.gateway;

  # Helper to get IP from DHCP assignments (simplified for now, would need tighter integration)
  # This relies on the DHCP module populating a known structure or file.
  # For this iteration, we will rely on static configuration or manual mapping.

  # Convert simple duration strings to seconds
  parseDuration =
    duration:
    if lib.hasSuffix "h" duration then
      (lib.toInt (lib.removeSuffix "h" duration)) * 3600
    else if lib.hasSuffix "d" duration then
      (lib.toInt (lib.removeSuffix "d" duration)) * 86400
    else if lib.hasSuffix "w" duration then
      (lib.toInt (lib.removeSuffix "w" duration)) * 604800
    else
      0; # Default or invalid

  # Placeholder for nftables quota rules generation
  # Real implementation would need persistent counters or an external daemon for complex quotas
  generateQuotaRules =
    deviceName: quota:
    # This is a stub. Full quota implementation requires a stateful counter mechanism (like nftables quotas)
    # and a reset mechanism (cron/systemd timer).
    # For now, we will log the intent.
    "# Quota rule for ${deviceName}: ${quota}";

in
{
  options.services.gateway.deviceBandwidth = {
    enable = lib.mkEnableOption "Per-device bandwidth allocation";

    deviceProfiles = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            maxBandwidth = lib.mkOption {
              type = lib.types.str;
              default = "10Mbit";
            };
            guaranteedBandwidth = lib.mkOption {
              type = lib.types.str;
              default = "1Mbit";
            };
            priority = lib.mkOption {
              type = lib.types.int;
              default = 5;
            };
            burstAllowance = lib.mkOption {
              type = lib.types.str;
              default = "0k";
            };
            timeLimit = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
            };
          };
        }
      );
      default = { };
      description = "Bandwidth profiles definition";
    };

    devices = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            mac = lib.mkOption { type = lib.types.str; };
            ip = lib.mkOption { type = lib.types.str; }; # Requiring IP for now for TC matching
            profile = lib.mkOption { type = lib.types.str; };
          };
        }
      );
      default = { };
      description = "Map specific devices (MAC/IP) to profiles";
    };

    quotas = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
      default = { };
      description = "Bandwidth quotas (daily, weekly, monthly)";
    };
  };

  config = lib.mkIf cfg.enable {
    # 1. Integrate with QoS Traffic Classes
    # We dynamically generate traffic classes for each defined device based on its profile.
    services.gateway.qos.trafficClasses =
      let
        sortedDeviceNames = lib.sort (a: b: a < b) (lib.attrNames cfg.devices);
        # Create a mapping of name -> index
        nameToIndex = lib.listToAttrs (lib.imap0 (i: n: lib.nameValuePair n i) sortedDeviceNames);
      in
      lib.mapAttrs' (
        name: device:
        let
          profile = cfg.deviceProfiles.${device.profile};
          idx = nameToIndex.${name};
          id = 2000 + idx; # ID range 2000+
        in
        lib.nameValuePair "device-${name}" {
          inherit id;
          priority = profile.priority;
          maxBandwidth = profile.maxBandwidth;
          guaranteedBandwidth = profile.guaranteedBandwidth;
          # We don't use 'protocols' here, we use source/dest IP matching in firewall
        }
      ) cfg.devices;

    # 2. Generate Firewall/Packet Marking Rules
    # We need to mark packets coming FROM or going TO these devices with the class ID.
    services.gateway.qos.extraForwardRules = ''
      # Device Bandwidth Marking
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (
          name: device:
          let
            sortedDeviceNames = lib.sort (a: b: a < b) (lib.attrNames cfg.devices);
            nameToIndex = lib.listToAttrs (lib.imap0 (i: n: lib.nameValuePair n i) sortedDeviceNames);
            idx = nameToIndex.${name};
            id = 2000 + idx;
          in
          ''
            ip saddr ${device.ip} meta mark set ${toString id} counter
            ip daddr ${device.ip} meta mark set ${toString id} counter
          ''
        ) cfg.devices
      )}
    '';

    # 3. Quota Management (Stub/Foundation)
    # Real implementation would involve a script to check bytes and update dynamic blocklists/tc rules
    # systemd.services.bandwidth-quota-monitor = { ... }

  };
}

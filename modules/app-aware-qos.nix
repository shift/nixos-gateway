{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.gateway.appAwareQoS;
  dpiEngine = import ../lib/dpi-engine.nix { inherit lib; };
  qosCfg = config.services.gateway.qos;

  # Define the application submodule structure
  applicationOpts = types.submodule {
    options = {
      protocols = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "List of lower-level protocols (tcp, udp, etc.)";
      };
      signatures = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "List of DPI signatures (e.g., 'netflix', 'zoom')";
      };
      shaping = mkOption {
        type = types.submodule {
          options = {
            maxBandwidth = mkOption {
              type = types.str;
              default = "1Gbit";
            };
            guaranteedBandwidth = mkOption {
              type = types.str;
              default = "1Mbit";
            };
            priority = mkOption {
              type = types.int;
              default = 5;
            };
            bufferManagement = mkOption {
              type = types.str;
              default = "adaptive";
            };
            throttleDuring = mkOption {
              type = types.nullOr types.str;
              default = null;
            };
            jitterControl = mkOption {
              type = types.bool;
              default = false;
            };
          };
        };
        default = { };
        description = "Traffic shaping parameters";
      };
    };
  };

  # Helper to generate traffic classes with deterministic IDs
  # We convert to a list, assign IDs based on index, and then generate the config
  appsWithId = imap1 (
    i: app:
    app
    // {
      uniqueId = 100 + (i * 10);
    }
  ) (mapAttrsToList (name: value: { inherit name value; }) cfg.applications);

  generatedTrafficClasses = listToAttrs (
    map (app: {
      name = app.name;
      value = {
        id = app.uniqueId;
        priority = app.value.shaping.priority;
        maxBandwidth = app.value.shaping.maxBandwidth;
        guaranteedBandwidth = app.value.shaping.guaranteedBandwidth;
        # We don't pass 'protocols' directly here because qos.nix expects simple strings.
        # Instead, we'll inject custom rules into the firewall.
        protocols = [ ];
        dscp = if app.value.shaping.priority <= 2 then 46 else null; # EF for high prio
      };
    }) appsWithId
  );

  # Generate firewall rules for each application
  # This bridges the gap between 'signatures' and nftables
  generatedRules = flatten (
    map (
      app:
      let
        # Get rules for named signatures
        sigRules = dpiEngine.resolveApps app.value.signatures;
        # Basic protocol rules (if any simple ones provided)
        protoRules = map (p: "meta l4proto ${p}") app.value.protocols;

        allRules = sigRules ++ protoRules;

        # We need the ID we generated above to mark packets
        classId = app.uniqueId;

        # Action: Mark the packet
        action = "meta mark set ${toString classId} counter";
      in
      map (rule: "${rule} ${action}") allRules
    ) appsWithId
  );

in
{
  options.services.gateway.appAwareQoS = {
    enable = mkEnableOption "Application-Aware QoS";

    dpiEngine = {
      enable = mkEnableOption "DPI Engine";
      database = mkOption {
        type = types.str;
        default = "nDPI";
      };
      updateInterval = mkOption {
        type = types.str;
        default = "7d";
      };
      classification = mkOption {
        type = types.submodule {
          options = {
            confidence = mkOption {
              type = types.float;
              default = 0.8;
            };
            learningMode = mkOption {
              type = types.bool;
              default = true;
            };
            customSignatures = mkOption {
              type = types.listOf types.attrs;
              default = [ ];
            };
          };
        };
        default = { };
      };
    };

    applications = mkOption {
      type = types.attrsOf applicationOpts;
      default = { };
      description = "Defined applications and their shaping rules";
    };

    policies = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            rules = mkOption {
              type = types.listOf types.attrs;
              default = [ ];
            };
            schedule = mkOption {
              type = types.nullOr types.str;
              default = null;
            };
          };
        }
      );
      default = { };
      description = "High-level policies mapping users/time to applications";
    };

    machineLearning = mkOption {
      type = types.submodule {
        options = {
          enable = mkEnableOption "ML-based classification";
          model = mkOption {
            type = types.str;
            default = "random-forest";
          };
          trainingData = mkOption {
            type = types.str;
            default = "30d";
          };
          retrainInterval = mkOption {
            type = types.str;
            default = "7d";
          };
          features = mkOption {
            type = types.listOf types.str;
            default = [ ];
          };
        };
      };
      default = { };
    };

    monitoring = mkOption {
      type = types.submodule {
        options = {
          enable = mkEnableOption "Monitoring";
          metrics = mkOption {
            type = types.attrsOf types.bool;
            default = { };
          };
        };
      };
      default = { };
    };
  };

  config = mkIf cfg.enable {
    # Integrate with the core QoS module
    services.gateway.qos = {
      enable = true;
      # Merge our generated classes with existing ones
      trafficClasses = generatedTrafficClasses;
    };

    # Inject our rules into the QoS forward chain using the new integration point
    services.gateway.qos.extraForwardRules = ''
      # Application-Aware QoS Rules
      ${concatStringsSep "\n        " generatedRules}
    '';
  };
}

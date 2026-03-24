{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.gateway.debugMode;
  debugTools = import ../lib/debug-tools.nix { inherit lib pkgs; };

  # Define option types
  levelOpts =
    { name, ... }:
    {
      options = {
        name = lib.mkOption { type = lib.types.str; };
        priority = lib.mkOption { type = lib.types.int; };
        description = lib.mkOption { type = lib.types.str; };
        color = lib.mkOption { type = lib.types.str; };
      };
    };

  componentOpts =
    { name, ... }:
    {
      options = {
        name = lib.mkOption { type = lib.types.str; };
        description = lib.mkOption { type = lib.types.str; };
        modules = lib.mkOption { type = lib.types.listOf lib.types.str; };
        defaultLevel = lib.mkOption { type = lib.types.str; };
      };
    };

  checkOpts =
    { name, ... }:
    {
      options = {
        name = lib.mkOption { type = lib.types.str; };
        description = lib.mkOption { type = lib.types.str; };
        command = lib.mkOption { type = lib.types.str; };
        services = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
        ports = lib.mkOption {
          type = lib.types.listOf lib.types.int;
          default = [ ];
        };
        metrics = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
        targets = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
      };
    };

  toolOpts =
    { name, ... }:
    {
      options = {
        name = lib.mkOption { type = lib.types.str; };
        description = lib.mkOption { type = lib.types.str; };
        command = lib.mkOption { type = lib.types.str; };
        flags = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
        filters = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
        duration = lib.mkOption {
          type = lib.types.str;
          default = "";
        };
      };
    };

in
{
  options.services.gateway.debugMode = {
    enable = lib.mkEnableOption "Gateway Debug Mode";

    levels = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule levelOpts);
      default = [
        {
          name = "error";
          priority = 0;
          description = "Error conditions";
          color = "red";
        }
        {
          name = "warn";
          priority = 1;
          description = "Warning conditions";
          color = "yellow";
        }
        {
          name = "info";
          priority = 2;
          description = "Informational messages";
          color = "blue";
        }
        {
          name = "debug";
          priority = 3;
          description = "Debug information";
          color = "green";
        }
        {
          name = "trace";
          priority = 4;
          description = "Detailed tracing";
          color = "cyan";
        }
      ];
      description = "Debug levels configuration";
    };

    components = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule componentOpts);
      default = [ ];
      description = "Debug components configuration";
    };

    diagnostics = {
      health = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
        };
        checks = lib.mkOption {
          type = lib.types.listOf (lib.types.submodule checkOpts);
          default = [ ];
          description = "Health checks";
        };
        reporting = lib.mkOption {
          type = lib.types.attrs;
          default = { };
        };
      };

      network = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
        };
        tools = lib.mkOption {
          type = lib.types.listOf (lib.types.submodule toolOpts);
          default = [ ];
          description = "Network diagnostic tools";
        };
      };

      configuration = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
        };
        tools = lib.mkOption {
          type = lib.types.listOf (lib.types.submodule toolOpts);
          default = [ ];
          description = "Configuration diagnostic tools";
        };
      };

      performance = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
        };
        tools = lib.mkOption {
          type = lib.types.listOf (lib.types.submodule toolOpts);
          default = [ ];
          description = "Performance diagnostic tools";
        };
      };
    };

    # Placeholder options
    logging = lib.mkOption {
      type = lib.types.attrs;
      default = { };
    };
    interactive = lib.mkOption {
      type = lib.types.attrs;
      default = { };
    };
    troubleshooting = lib.mkOption {
      type = lib.types.attrs;
      default = { };
    };
    performance = lib.mkOption {
      type = lib.types.attrs;
      default = { };
    };
  };

  config = lib.mkIf cfg.enable {
    # Install standard debug tools
    environment.systemPackages = with pkgs; [
      # Network
      tcpdump
      conntrack-tools
      dig
      ethtool
      mtr
      socat
      nmap

      # System
      sysstat
      iotop
      htop
      lsof
      strace

      # Generated diagnostic script
      (debugTools.mkDiagnoseScript cfg.diagnostics)
    ];

    # Create convenient aliases
    environment.shellAliases = {
      debug-net = "tcpdump -i any -n -v";
      debug-conns = "conntrack -L";
      debug-health = "gateway-diagnose";
    };
  };
}

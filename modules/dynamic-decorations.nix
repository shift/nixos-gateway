{
  config,
  lib,
  pkgs,
  osConfig ? null,
  ...
}:

with lib;

let
  cfg = config.features.dynamic-decorations;

  sysEnabled = path: if osConfig != null then attrByPath path false osConfig else false;
  userEnabled = path: attrByPath path false config;
  isHyprland =
    (sysEnabled [
      "programs"
      "hyprland"
      "enable"
    ])
    || (userEnabled [
      "wayland"
      "windowManager"
      "hyprland"
      "enable"
    ]);
  # Add SwayFX detection logic if you use it (regular Sway doesn't support these)
  isSwayFx = isSway && (config.wayland.windowManager.sway.package.pname == "swayfx");
  isSway =
    (sysEnabled [
      "programs"
      "sway"
      "enable"
    ])
    || (userEnabled [
      "wayland"
      "windowManager"
      "sway"
      "enable"
    ]);

in
{
  options.features.dynamic-decorations = {
    enable = mkEnableOption "dynamic decoration management";

    blur = mkOption {
      type = types.bool;
      default = true;
      description = "Enable blur on transparent windows";
    };
    shadows = mkOption {
      type = types.bool;
      default = true;
      description = "Enable window shadows";
    };
    dimming = mkOption {
      type = types.bool;
      default = false;
      description = "Dim inactive windows";
    };
  };

  config = mkIf cfg.enable {

    # --- Hyprland ---
    wayland.windowManager.hyprland.settings = mkIf isHyprland {
      decoration = {
        blur = {
          enabled = cfg.blur;
          size = 3;
          passes = 3; # High quality blur
          new_optimizations = true;
        };

        drop_shadow = cfg.shadows;
        shadow_range = 15;
        shadow_render_power = 3;

        dim_inactive = cfg.dimming;
        dim_strength = 0.3;
      };
    };

    # --- SwayFX (If installed) ---
    wayland.windowManager.sway.config = mkIf isSwayFx {
      blur_enable = if cfg.blur then "enable" else "disable";
      shadows_enable = if cfg.shadows then "enable" else "disable";
      default_dim_inactive = toString (if cfg.dimming then 0.3 else 0.0);
    };
  };
}

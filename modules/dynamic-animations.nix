{
  config,
  lib,
  pkgs,
  osConfig ? null,
  ...
}:

with lib;

let
  cfg = config.features.dynamic-animations;

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

  # Pre-defined animation curves
  profiles = {
    # Fast, snappy, standard look
    default = ''
      bezier = myBezier, 0.05, 0.9, 0.1, 1.05
      animation = windows, 1, 7, myBezier
      animation = windowsOut, 1, 7, default, popin 80%
      animation = border, 1, 10, default
      animation = borderangle, 1, 8, default
      animation = fade, 1, 7, default
      animation = workspaces, 1, 6, default
    '';

    # Hyprland's signature bounce
    bouncy = ''
      bezier = overshot, 0.05, 0.9, 0.1, 1.1
      animation = windows, 1, 5, overshot, slide
      animation = border, 1, 10, default
      animation = fade, 1, 5, default
      animation = workspaces, 1, 6, overshot, slidevert
    '';

    # Smooth, macOS-like flow
    fluid = ''
      bezier = fluid, 0.25, 0.46, 0.45, 0.94
      animation = windows, 1, 5, fluid, slide
      animation = workspaces, 1, 5, fluid, slide
      animation = fade, 1, 5, fluid
    '';

    # Maximum performance
    instant = ''
      animation = global, 1, 1, default
    '';
  };
in
{
  options.features.dynamic-animations = {
    enable = mkEnableOption "dynamic animation management";

    profile = mkOption {
      type = types.enum [
        "default"
        "bouncy"
        "fluid"
        "instant"
      ];
      default = "default";
      description = "The animation personality to use.";
    };
  };

  config = mkIf (cfg.enable && isHyprland) {
    wayland.windowManager.hyprland.extraConfig = profiles.${cfg.profile};
  };
}

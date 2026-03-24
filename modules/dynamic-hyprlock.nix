{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.features.dynamic-hyprlock;

  # Fetch Stylix colors (or defaults)
  colors =
    config.lib.stylix.colors or {
      base00 = "1e1e2e";
      base05 = "cdd6f4";
      base08 = "f38ba8";
    };

  # Helper to generate a label block
  mkLabel = l: {
    monitor = l.monitor;
    text = l.text;
    text_align = "center";
    color = "rgba(${colors.base05}ff)";
    font_size = l.size;
    font_family = config.stylix.fonts.sansSerif.name or "Sans";
    position = l.position;
    halign = l.halign;
    valign = l.valign;
    shadow_passes = 1;
  };

in
{
  options.features.dynamic-hyprlock = {
    enable = mkEnableOption "dynamic hyprlock configuration";

    wallpaper = mkOption {
      type = types.path;
      description = "Path to the lock screen wallpaper.";
    };

    blur = mkOption {
      type = types.int;
      default = 2;
      description = "Blur amount for the background.";
    };

    widgets = mkOption {
      description = "List of UI widgets to display.";
      default = [ ];
      type = types.listOf (
        types.submodule {
          options = {
            type = mkOption {
              type = types.enum [
                "label"
                "input"
              ];
            };
            text = mkOption {
              type = types.str;
              default = "";
            }; # For labels
            monitor = mkOption {
              type = types.str;
              default = "";
            }; # "" = all monitors
            position = mkOption {
              type = types.str;
              default = "0, 0";
            };
            halign = mkOption {
              type = types.str;
              default = "center";
            };
            valign = mkOption {
              type = types.str;
              default = "center";
            };
            size = mkOption {
              type = types.int;
              default = 25;
            };
          };
        }
      );
    };
  };

  config = mkIf cfg.enable {
    programs.hyprlock = {
      enable = true;
      settings = {
        general = {
          no_fade_in = false;
          grace = 0;
          disable_loading_bar = true;
        };

        background = [
          {
            monitor = "";
            path = toString cfg.wallpaper;
            blur_passes = cfg.blur;
            contrast = 0.8916;
            brightness = 0.8172;
            vibrancy = 0.1696;
            vibrancy_darkness = 0.0;
          }
        ];

        input-field = filter (w: w.type == "input") (
          map (w: {
            monitor = w.monitor;
            size = "250, 60";
            outline_thickness = 2;
            dots_size = 0.2;
            dots_spacing = 0.2;
            dots_center = true;
            outer_color = "rgba(${colors.base05}ff)";
            inner_color = "rgba(${colors.base00}ff)";
            font_color = "rgba(${colors.base05}ff)";
            fade_on_empty = false;
            placeholder_text = "<i>Input Password...</i>";
            hide_input = false;
            position = w.position;
            halign = w.halign;
            valign = w.valign;
          }) cfg.widgets
        );

        label = map mkLabel (filter (w: w.type == "label") cfg.widgets);
      };
    };
  };
}

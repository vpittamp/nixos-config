# sway-easyfocus - Keyboard-driven window focusing with hints
# Home Manager module for declarative configuration
# Upstream: https://github.com/edzdez/sway-easyfocus
#
# Usage:
#   programs.sway-easyfocus = {
#     enable = true;
#     settings = {
#       chars = "fjghdkslaemuvitywoqpcbnxz";
#       window_background_color = "#000000";
#       # ... other options
#     };
#   };
{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit (lib)
    mkIf
    mkEnableOption
    mkPackageOption
    mkOption
    ;

  cfg = config.programs.sway-easyfocus;
  formatter = pkgs.formats.yaml { };
in
{
  meta.maintainers = with lib.hm.maintainers; [ aguirre-matteo ];

  options.programs.sway-easyfocus = {
    enable = mkEnableOption "sway-easyfocus";
    package = mkPackageOption pkgs "sway-easyfocus" { nullable = true; };
    settings = mkOption {
      type = formatter.type;
      default = { };
      example = {
        chars = "fjghdkslaemuvitywoqpcbnxz";
        window_background_color = "#d1f21f";
        window_background_opacity = 0.2;
        focused_background_color = "#285577";
        focused_background_opacity = 1.0;
        focused_text_color = "#ffffff";
        font_family = "monospace";
        font_weight = "bold";
        font_size = "medium";
      };
      description = ''
        Configuration settings for sway-easyfocus. All available options can be found here:
        <https://github.com/edzdez/sway-easyfocus?tab=readme-ov-file#config-file>.
      '';
    };
  };

  config = mkIf cfg.enable {
    home.packages = mkIf (cfg.package != null) [ cfg.package ];
    xdg.configFile."sway-easyfocus/config.yaml" = mkIf (cfg.settings != { }) {
      source = formatter.generate "sway-easyfocus-config.yaml" cfg.settings;
    };
  };
}

# XResources configuration for xterm
# Matches Ghostty/Catppuccin Mocha theme
{ config, lib, pkgs, ... }:

{
  xresources.properties = {
    # Font configuration
    "XTerm*faceName" = "FiraCode Nerd Font";
    "XTerm*faceSize" = 12;

    # Catppuccin Mocha color scheme
    "XTerm*background" = "#1e1e2e";
    "XTerm*foreground" = "#cdd6f4";
    "XTerm*cursorColor" = "#f5e0dc";

    # Black
    "XTerm*color0" = "#45475a";
    "XTerm*color8" = "#585b70";

    # Red
    "XTerm*color1" = "#f38ba8";
    "XTerm*color9" = "#f38ba8";

    # Green
    "XTerm*color2" = "#a6e3a1";
    "XTerm*color10" = "#a6e3a1";

    # Yellow
    "XTerm*color3" = "#f9e2af";
    "XTerm*color11" = "#f9e2af";

    # Blue
    "XTerm*color4" = "#89b4fa";
    "XTerm*color12" = "#89b4fa";

    # Magenta
    "XTerm*color5" = "#f5c2e7";
    "XTerm*color13" = "#f5c2e7";

    # Cyan
    "XTerm*color6" = "#94e2d5";
    "XTerm*color14" = "#94e2d5";

    # White
    "XTerm*color7" = "#bac2de";
    "XTerm*color15" = "#a6adc8";

    # Window settings
    "XTerm*internalBorder" = 0;
    "XTerm*borderWidth" = 0;
    "XTerm*saveLines" = 1000;
    "XTerm*scrollBar" = false;

    # Clean appearance
    "XTerm*cursorBlink" = false;
    "XTerm*borderColor" = "#1e1e2e";

    # Fix backspace
    "XTerm*backarrowKey" = false;
    "XTerm*metaSendsEscape" = true;
  };
}

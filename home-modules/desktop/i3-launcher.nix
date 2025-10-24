{ config, lib, pkgs, ... }:

# Feature 034: Unified Application Launcher - rofi Configuration
#
# This module configures rofi as the unified application launcher with:
# - Catppuccin Mocha theme for visual consistency
# - Icon support for application recognition
# - drun mode for XDG desktop file integration
# - Optimized for the application registry system

{
  # T051: rofi launcher configuration
  programs.rofi = {
    enable = true;
    package = pkgs.rofi;

    # T053: Catppuccin Mocha theme
    theme = "catppuccin-mocha";

    # Font configuration matching system theme
    font = "JetBrainsMono Nerd Font 11";

    # Terminal for applications that need it
    terminal = "${pkgs.ghostty}/bin/ghostty";

    extraConfig = {
      # T052: Enable drun mode (desktop file runner)
      modi = "drun,run,window";

      # Show icons for applications
      show-icons = true;
      icon-theme = "Papirus-Dark";

      # Display configuration
      display-drun = "Applications";
      display-run = "Run";
      display-window = "Windows";

      # Behavior
      drun-display-format = "{name} [{comment}]";
      disable-history = false;
      hide-scrollbar = true;
      sidebar-mode = false;

      # Performance
      lazy-grab = true;
      dpi = 1;

      # Layout
      lines = 10;
      columns = 1;
      width = 40;
      location = 0;  # Center

      # Sorting
      sorting-method = "fzf";
      matching = "fuzzy";
      sort = true;
      case-sensitive = false;
    };
  };

  # Install Catppuccin rofi theme
  home.file.".config/rofi/catppuccin-mocha.rasi" = {
    text = ''
      * {
        bg-col:  #1e1e2e;
        bg-col-light: #313244;
        border-col: #89b4fa;
        selected-col: #45475a;
        blue: #89b4fa;
        fg-col: #cdd6f4;
        fg-col2: #f38ba8;
        grey: #6c7086;

        width: 600;
      }

      element-text, element-icon , mode-switcher {
        background-color: inherit;
        text-color:       inherit;
      }

      window {
        height: 450px;
        border: 3px;
        border-color: @border-col;
        background-color: @bg-col;
      }

      mainbox {
        background-color: @bg-col;
      }

      inputbar {
        children: [prompt,entry];
        background-color: @bg-col;
        border-radius: 5px;
        padding: 2px;
      }

      prompt {
        background-color: @blue;
        padding: 6px;
        text-color: @bg-col;
        border-radius: 3px;
        margin: 20px 0px 0px 20px;
      }

      textbox-prompt-colon {
        expand: false;
        str: ":";
      }

      entry {
        padding: 6px;
        margin: 20px 0px 0px 10px;
        text-color: @fg-col;
        background-color: @bg-col;
      }

      listview {
        border: 0px 0px 0px;
        padding: 6px 0px 0px;
        margin: 10px 0px 0px 20px;
        columns: 1;
        lines: 10;
        background-color: @bg-col;
      }

      element {
        padding: 5px;
        background-color: @bg-col;
        text-color: @fg-col;
      }

      element-icon {
        size: 25px;
      }

      element selected {
        background-color:  @selected-col;
        text-color: @fg-col2;
      }

      mode-switcher {
        spacing: 0;
      }

      button {
        padding: 10px;
        background-color: @bg-col-light;
        text-color: @grey;
        vertical-align: 0.5;
        horizontal-align: 0.5;
      }

      button selected {
        background-color: @bg-col;
        text-color: @blue;
      }

      message {
        background-color: @bg-col-light;
        margin: 2px;
        padding: 2px;
        border-radius: 5px;
      }

      textbox {
        padding: 6px;
        margin: 20px 0px 0px 20px;
        text-color: @blue;
        background-color: @bg-col-light;
      }
    '';
  };

  # Ensure Papirus icon theme is available
  home.packages = with pkgs; [
    papirus-icon-theme
  ];
}

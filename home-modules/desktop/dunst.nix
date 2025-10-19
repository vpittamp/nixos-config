# Dunst - Lightweight notification daemon for i3
{ config, pkgs, lib, ... }:

{
  services.dunst = {
    enable = true;

    settings = {
      global = {
        # Display
        monitor = 0;
        follow = "mouse";

        # Geometry
        width = 300;
        height = "(0, 300)";  # Dynamic height up to 300px (new syntax)
        origin = "top-right";
        offset = "(10, 50)";  # New syntax: (horizontal, vertical)

        # Progress bar
        progress_bar = true;
        progress_bar_height = 10;
        progress_bar_frame_width = 1;
        progress_bar_min_width = 150;
        progress_bar_max_width = 300;

        # Appearance
        transparency = 10;
        separator_height = 2;
        padding = 8;
        horizontal_padding = 8;
        frame_width = 2;
        frame_color = "#89b4fa";
        separator_color = "frame";
        sort = true;

        # Text
        font = "monospace 10";
        line_height = 0;
        markup = "full";
        format = "<b>%s</b>\\n%b";
        alignment = "left";
        vertical_alignment = "center";
        show_age_threshold = 60;
        word_wrap = true;
        ellipsize = "middle";
        ignore_newline = false;
        stack_duplicates = true;
        hide_duplicate_count = false;
        show_indicators = true;

        # Icons
        icon_position = "left";
        min_icon_size = 32;
        max_icon_size = 64;

        # History
        sticky_history = true;
        history_length = 20;

        # Interaction
        dmenu = "${pkgs.rofi}/bin/rofi -dmenu -p dunst";
        browser = "${pkgs.firefox}/bin/firefox";
        mouse_left_click = "do_action, close_current";
        mouse_middle_click = "close_current";
        mouse_right_click = "close_all";
      };

      # Urgency levels with Catppuccin Mocha colors
      urgency_low = {
        background = "#1e1e2e";
        foreground = "#cdd6f4";
        frame_color = "#89b4fa";
        timeout = 5;
      };

      urgency_normal = {
        background = "#1e1e2e";
        foreground = "#cdd6f4";
        frame_color = "#89b4fa";
        timeout = 10;
      };

      urgency_critical = {
        background = "#1e1e2e";
        foreground = "#cdd6f4";
        frame_color = "#f38ba8";
        timeout = 0;
      };

      # Special notification for long-running commands
      command_success = {
        appname = "bg-command";
        urgency = "normal";
        background = "#1e1e2e";
        foreground = "#a6e3a1";
        frame_color = "#a6e3a1";
        timeout = 15;
      };

      command_failure = {
        appname = "bg-command";
        urgency = "critical";
        background = "#1e1e2e";
        foreground = "#f38ba8";
        frame_color = "#f38ba8";
        timeout = 0;
      };
    };
  };
}

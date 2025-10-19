# Polybar Configuration for i3
# Provides statusbar with custom modules including project indicator
{ config, lib, pkgs, ... }:

let
  polybarPkg = pkgs.polybar.override {
    i3Support = true;
    alsaSupport = true;
    pulseSupport = true;
  };
in
{
  # Install polybar package (even though systemd service is disabled)
  home.packages = [ polybarPkg ];

  # We still need services.polybar enabled to generate the config file
  # but we disable the systemd service afterwards
  services.polybar = {
    enable = true;
    package = polybarPkg;

    # Dummy script since we start polybar from i3
    script = "";

    config = {
      "bar/main" = {
        monitor = "\${env:MONITOR:}";
        monitor-strict = true;
        width = "100%";
        height = 27;
        radius = 0;
        fixed-center = true;
        bottom = true;  # Position at bottom

        background = "#1e1e2e";
        foreground = "#cdd6f4";

        line-size = 3;
        line-color = "#f5e0dc";

        border-size = 0;
        border-color = "#00000000";

        padding-left = 1;
        padding-right = 1;

        module-margin-left = 1;
        module-margin-right = 1;

        font-0 = "FiraCode Nerd Font:size=10;2";
        font-1 = "Font Awesome 6 Free:style=Solid:size=10;2";
        font-2 = "Font Awesome 6 Brands:size=10;2";

        modules-left = "monitor i3";
        modules-center = "project";
        modules-right = "filesystem memory cpu network date";

        # System tray disabled to prevent multi-monitor conflicts
        # Only one polybar instance can manage the system tray at a time
        # tray-position = "right";
        # tray-padding = 2;

        cursor-click = "pointer";
        cursor-scroll = "ns-resize";

        enable-ipc = true;
      };

      # Monitor Module - Display current monitor name
      "module/monitor" = {
        type = "custom/script";
        exec = "echo \"\${MONITOR}\"";
        format = "<label>";
        format-prefix = "󰍹 ";  # Monitor icon
        format-prefix-foreground = "#89dceb";  # Sky blue color
        format-background = "#313244";  # Darker background
        format-padding = 2;
        label = "%output%";
        label-foreground = "#89dceb";  # Match prefix color
        label-font = 1;  # Use Font Awesome font
      };

      # Project Module - Custom Script
      "module/project" = {
        type = "custom/script";
        exec = "~/.config/polybar/scripts/project-display.sh";
        interval = 2;

        # Click to switch project
        click-left = "~/.config/i3/scripts/project-switcher.sh";
        # Right click to clear project
        click-right = "~/.config/i3/scripts/project-clear.sh && polybar-msg action '#project.hook.0'";

        format = "<label>";
        format-prefix = " ";
        format-prefix-foreground = "#b4befe";
        format-underline = "#b4befe";

        label = "%output%";
        label-foreground = "#cdd6f4";
      };

      # i3 Workspaces Module
      "module/i3" = {
        type = "internal/i3";
        format = "<label-state> <label-mode>";
        index-sort = true;
        wrapping-scroll = false;
        pin-workspaces = true;  # Only show workspaces on their assigned monitor

        # Mode indicator (resize, etc)
        label-mode-padding = 2;
        label-mode-foreground = "#1e1e2e";
        label-mode-background = "#f38ba8";

        # Focused workspace
        "label-focused" = "%name%";
        "label-focused-foreground" = "#cdd6f4";  # Light text
        "label-focused-background" = "#45475a";
        "label-focused-underline" = "#b4befe";
        "label-focused-padding" = 2;

        # Unfocused workspace
        "label-unfocused" = "%name%";
        "label-unfocused-foreground" = "#bac2de";  # Slightly dimmed text
        "label-unfocused-padding" = 2;

        # Visible workspace (on other monitor)
        "label-visible" = "%name%";
        "label-visible-foreground" = "#cdd6f4";  # Light text
        "label-visible-background" = "#313244";
        "label-visible-underline" = "#45475a";
        "label-visible-padding" = 2;

        # Urgent workspace
        "label-urgent" = "%name%";
        "label-urgent-foreground" = "#1e1e2e";  # Dark text on bright background
        "label-urgent-background" = "#f38ba8";
        "label-urgent-padding" = 2;
      };

      # Date Module
      "module/date" = {
        type = "internal/date";
        interval = 5;

        date = "%a %b %d";
        date-alt = "%A, %B %d";

        time = "%H:%M";
        time-alt = "%H:%M:%S";

        format-prefix = " ";
        format-prefix-foreground = "#f9e2af";
        format-underline = "#f9e2af";

        label = "%date% %time%";
      };

      # CPU Module
      "module/cpu" = {
        type = "internal/cpu";
        interval = 2;
        format-prefix = " ";
        format-prefix-foreground = "#a6e3a1";
        format-underline = "#a6e3a1";
        label = "%percentage:2%%";
      };

      # Memory Module
      "module/memory" = {
        type = "internal/memory";
        interval = 2;
        format-prefix = " ";
        format-prefix-foreground = "#89b4fa";
        format-underline = "#89b4fa";
        label = "%percentage_used%%";
      };

      # Filesystem Module
      "module/filesystem" = {
        type = "internal/fs";
        interval = 25;

        mount-0 = "/";

        label-mounted = "%{F#a6e3a1}%{F-} %percentage_used%%";
        label-unmounted = "%mountpoint% not mounted";
        label-unmounted-foreground = "#585b70";
      };

      # Network Module
      "module/network" = {
        type = "internal/network";
        interface-type = "wired";
        interval = 3;

        format-connected = "<label-connected>";
        format-connected-underline = "#94e2d5";
        label-connected = " %local_ip%";

        format-disconnected = "<label-disconnected>";
        label-disconnected = "󰌙 Disconnected";
        label-disconnected-foreground = "#585b70";
      };

      # Battery Module (if applicable)
      "module/battery" = {
        type = "internal/battery";
        battery = "BAT0";
        adapter = "AC";
        full-at = 98;

        format-charging = "<animation-charging> <label-charging>";
        format-charging-underline = "#a6e3a1";

        format-discharging = "<ramp-capacity> <label-discharging>";
        format-discharging-underline = "#f9e2af";

        format-full-prefix = " ";
        format-full-prefix-foreground = "#a6e3a1";
        format-full-underline = "#a6e3a1";

        ramp-capacity-0 = "";
        ramp-capacity-1 = "";
        ramp-capacity-2 = "";
        ramp-capacity-3 = "";
        ramp-capacity-4 = "";

        animation-charging-0 = "";
        animation-charging-1 = "";
        animation-charging-2 = "";
        animation-charging-3 = "";
        animation-charging-4 = "";
        animation-charging-framerate = 750;
      };

      # Temperature Module
      "module/temperature" = {
        type = "internal/temperature";
        thermal-zone = 0;
        warn-temperature = 70;

        format = "<label>";
        format-underline = "#fab387";
        format-warn = "<label-warn>";
        format-warn-underline = "#f38ba8";

        label = " %temperature-c%";
        label-warn = " %temperature-c%";
        label-warn-foreground = "#f38ba8";
      };

      # Settings
      "settings" = {
        screenchange-reload = true;
        pseudo-transparency = false;
      };

      # Global WM Settings
      "global/wm" = {
        margin-top = 0;
        margin-bottom = 0;
      };
    };

    # Workaround: Add i3 module foreground colors via extraConfig
    # These don't seem to work when defined in the module config above
    extraConfig = ''
      [module/i3]
      label-focused-foreground = #cdd6f4
      label-unfocused-foreground = #bac2de
      label-visible-foreground = #cdd6f4
      label-urgent-foreground = #1e1e2e
    '';
  };

  # Create polybar scripts directory and project display script
  home.file.".config/polybar/scripts/project-display.sh" = {
    text = ''
      #!${pkgs.bash}/bin/bash
      # Display current project for polybar

      PROJECT=$(~/.config/i3/scripts/project-current.sh --format json 2>/dev/null)

      if [ -n "$PROJECT" ]; then
        # Check if project is active
        IS_ACTIVE=$(echo "$PROJECT" | ${pkgs.jq}/bin/jq -r '.active // false' 2>/dev/null)

        if [ "$IS_ACTIVE" = "true" ]; then
          PROJECT_NAME=$(echo "$PROJECT" | ${pkgs.jq}/bin/jq -r '.name // empty' 2>/dev/null)
          PROJECT_ICON=$(echo "$PROJECT" | ${pkgs.jq}/bin/jq -r '.icon // ""' 2>/dev/null)

          if [ -n "$PROJECT_NAME" ] && [ "$PROJECT_NAME" != "null" ]; then
            # Display with icon (if available)
            if [ -n "$PROJECT_ICON" ] && [ "$PROJECT_ICON" != "null" ]; then
              echo "$PROJECT_ICON $PROJECT_NAME"
            else
              echo "$PROJECT_NAME"
            fi
          else
            echo "No Project"
          fi
        else
          echo "No Project"
        fi
      else
        echo "No Project"
      fi
    '';
    executable = true;
  };

  # Disable the polybar systemd service - polybar is started by i3 instead
  # This avoids X11 authentication issues and properly inherits i3's environment
  systemd.user.services.polybar.Install.WantedBy = lib.mkForce [];
}

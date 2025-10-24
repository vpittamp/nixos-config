# Polybar Configuration for i3
# Restored from Feature 013 with updated i3pm daemon integration
{ config, lib, pkgs, ... }:

let
  polybarPkg = pkgs.polybar.override {
    i3Support = true;
    alsaSupport = true;
    pulseSupport = true;
  };

  # Create wrapper script to call i3pm from PATH
  # (i3pm is installed via home.packages in i3pm-deno.nix)
  i3pmWrapper = pkgs.writeShellScript "i3pm-caller" ''
    exec ${config.home.profileDirectory}/bin/i3pm "$@"
  '';
in
{
  # Install polybar package
  home.packages = [ polybarPkg ];

  # We still need services.polybar enabled to generate the config file
  # but we disable the systemd service afterwards (polybar started by i3)
  services.polybar = {
    enable = true;
    package = polybarPkg;

    # Polybar launch script (runs on each monitor)
    script = ''
      # Kill any existing polybar instances
      ${pkgs.procps}/bin/pkill polybar || true

      # Wait for processes to exit
      sleep 1

      # Launch polybar on each connected monitor
      for m in $(${pkgs.xorg.xrandr}/bin/xrandr --query | ${pkgs.gnugrep}/bin/grep " connected" | ${pkgs.coreutils}/bin/cut -d" " -f1); do
        MONITOR=$m ${polybarPkg}/bin/polybar --reload main &
      done
    '';

    config = {
      "bar/main" = {
        monitor = "\${env:MONITOR:}";
        monitor-strict = true;
        width = "100%";
        height = 27;
        radius = 0;
        fixed-center = true;
        bottom = true;  # Position at bottom

        background = "#1e1e2e";  # Catppuccin Mocha base
        foreground = "#cdd6f4";  # Catppuccin Mocha text

        line-size = 3;
        line-color = "#f5e0dc";  # Catppuccin Mocha rosewater

        border-size = 0;
        border-color = "#00000000";

        padding-left = 1;
        padding-right = 1;

        module-margin-left = 1;
        module-margin-right = 1;

        font-0 = "FiraCode Nerd Font:size=10;2";
        font-1 = "Font Awesome 6 Free:style=Solid:size=10;2";
        font-2 = "Font Awesome 6 Brands:size=10;2";

        # Three-section layout: workspaces left, project center, system info right
        modules-left = "monitor i3";
        modules-center = "project";
        modules-right = "cpu memory network date";

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
        format-prefix-foreground = "#89dceb";  # Sky blue color (Catppuccin Mocha sky)
        format-background = "#313244";  # Catppuccin Mocha surface0
        format-padding = 2;
        label = "%output%";
        label-foreground = "#89dceb";  # Match prefix color
      };

      # Project Module - Real-time updates via daemon polling
      "module/project" = {
        type = "custom/script";
        exec = "${pkgs.writeShellScript "polybar-project-display" ''
          #!${pkgs.bash}/bin/bash
          # Display current project for polybar via i3pm daemon
          # Polls daemon every 2 seconds (daemon updates via tick events)

          # Function to display current project
          display_project() {
            # Query daemon for current project (strip ANSI color codes)
            CURRENT=$(${i3pmWrapper} project current 2>/dev/null | ${pkgs.gnused}/bin/sed 's/\x1b\[[0-9;]*m//g')

            if [ -z "$CURRENT" ] || [ "$CURRENT" = "null" ]; then
              # No active project - global mode
              echo "∅ Global"
              return
            fi

            # Get project info from daemon
            PROJECT_INFO=$(${i3pmWrapper} project list --json 2>/dev/null | \
              ${pkgs.jq}/bin/jq -r ".[] | select(.name == \"$CURRENT\") | \"\\(.icon // \"📁\") \\(.display_name // .name)\"")

            if [ -n "$PROJECT_INFO" ]; then
              echo "$PROJECT_INFO"
            else
              # Fallback if project info not found
              echo "📁 $CURRENT"
            fi
          }

          # Display current state
          display_project
        ''}";
        interval = 2;  # Poll every 2 seconds

        # Click to switch project (using rofi)
        click-left = "${pkgs.writeShellScript "polybar-project-switcher" ''
          #!${pkgs.bash}/bin/bash
          # Get list of projects with icons and display names
          PROJECT_LIST=$(${i3pmWrapper} project list --json 2>/dev/null)

          if [ -z "$PROJECT_LIST" ] || [ "$PROJECT_LIST" = "[]" ]; then
            ${pkgs.libnotify}/bin/notify-send "i3pm" "No projects configured"
            exit 0
          fi

          # Format for rofi: "icon display_name"
          FORMATTED=$(echo "$PROJECT_LIST" | ${pkgs.jq}/bin/jq -r '.[] | "\\(.icon // "📁") \\(.display_name // .name)\t\\(.name)"')

          # Show rofi menu
          SELECTED=$(echo "$FORMATTED" | ${pkgs.coreutils}/bin/cut -f1 | \
            ${pkgs.rofi}/bin/rofi -dmenu -i -p "Switch Project" -theme-str 'window {width: 400px;}')

          if [ -n "$SELECTED" ]; then
            # Get the project name corresponding to the selection
            PROJECT_NAME=$(echo "$FORMATTED" | ${pkgs.gnugrep}/bin/grep -F "$SELECTED" | ${pkgs.coreutils}/bin/cut -f2)

            if [ -n "$PROJECT_NAME" ]; then
              ${i3pmWrapper} project switch "$PROJECT_NAME"
            fi
          fi
        ''}";
        # Right click to clear project
        click-right = "${i3pmWrapper} project clear";

        format = "<label>";
        format-prefix = " ";
        format-prefix-foreground = "#b4befe";  # Catppuccin Mocha lavender
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
        label-mode-background = "#f38ba8";  # Catppuccin Mocha red

        # Focused workspace
        "label-focused" = "%name%";
        "label-focused-foreground" = "#cdd6f4";  # Light text
        "label-focused-background" = "#45475a";  # Catppuccin Mocha surface1
        "label-focused-underline" = "#b4befe";   # Catppuccin Mocha lavender
        "label-focused-padding" = 2;

        # Unfocused workspace
        "label-unfocused" = "%name%";
        "label-unfocused-foreground" = "#bac2de";  # Catppuccin Mocha subtext1
        "label-unfocused-padding" = 2;

        # Visible workspace (on other monitor)
        "label-visible" = "%name%";
        "label-visible-foreground" = "#cdd6f4";
        "label-visible-background" = "#313244";  # Catppuccin Mocha surface0
        "label-visible-underline" = "#45475a";
        "label-visible-padding" = 2;

        # Urgent workspace
        "label-urgent" = "%name%";
        "label-urgent-foreground" = "#1e1e2e";
        "label-urgent-background" = "#f38ba8";  # Catppuccin Mocha red
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
        format-prefix-foreground = "#f9e2af";  # Catppuccin Mocha yellow
        format-underline = "#f9e2af";

        label = "%date% %time%";
      };

      # CPU Module
      "module/cpu" = {
        type = "internal/cpu";
        interval = 2;
        format-prefix = " ";
        format-prefix-foreground = "#a6e3a1";  # Catppuccin Mocha green
        format-underline = "#a6e3a1";
        label = "%percentage:2%%";
      };

      # Memory Module
      "module/memory" = {
        type = "internal/memory";
        interval = 2;
        format-prefix = " ";
        format-prefix-foreground = "#89b4fa";  # Catppuccin Mocha blue
        format-underline = "#89b4fa";
        label = "%percentage_used%%";
      };

      # Network Module
      "module/network" = {
        type = "internal/network";
        interface-type = "wired";
        interval = 3;

        format-connected = "<label-connected>";
        format-connected-underline = "#94e2d5";  # Catppuccin Mocha teal
        label-connected = " %local_ip%";

        format-disconnected = "<label-disconnected>";
        label-disconnected = "󰌙 Disconnected";
        label-disconnected-foreground = "#585b70";  # Catppuccin Mocha surface2
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

    # No extraConfig needed - all settings are in the main config above
  };

  # Create polybar launch script that i3 can call
  home.file.".config/polybar/launch.sh" = {
    text = ''
      #!/${pkgs.bash}/bin/bash
      # Polybar launch script for i3
      # Kills existing instances and launches on all monitors

      # Kill any existing polybar instances
      ${pkgs.procps}/bin/pkill polybar || true

      # Wait for processes to exit
      sleep 1

      # Launch polybar on each connected monitor
      for m in $(${pkgs.xorg.xrandr}/bin/xrandr --query | ${pkgs.gnugrep}/bin/grep " connected" | ${pkgs.coreutils}/bin/cut -d" " -f1); do
        MONITOR=$m ${polybarPkg}/bin/polybar --reload main &
      done
    '';
    executable = true;
  };

  # Disable the polybar systemd service - polybar is started by i3 instead
  # This avoids X11 authentication issues and properly inherits i3's environment
  systemd.user.services.polybar.Install.WantedBy = lib.mkForce [];
}

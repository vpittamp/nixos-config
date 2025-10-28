# i3bar Configuration with Event-Driven Status Updates
# Dual bars: Top bar for system monitoring, bottom bar for project context
{ config, lib, pkgs, ... }:

let
  # Create wrapper script to call i3pm from PATH
  # (i3pm is installed via home.packages in i3pm-deno.nix)
  i3pmWrapper = pkgs.writeShellScript "i3pm-caller" ''
    exec ${config.home.profileDirectory}/bin/i3pm "$@"
  '';

  # Bottom bar: Event-driven project status script with click handler
  projectStatusScript = pkgs.writeShellScript "i3bar-status-event-driven" (
    builtins.replaceStrings
      [ "@i3pm@" "@jq@" "@sed@" "@date@" "@grep@" "@awk@" "@xterm@" "@walker@" "@walker_project_list@" "@walker_project_switch@" ]
      [ "${i3pmWrapper}" "${pkgs.jq}/bin/jq" "${pkgs.gnused}/bin/sed" "${pkgs.coreutils}/bin/date" "${pkgs.gnugrep}/bin/grep" "${pkgs.gawk}/bin/awk" "${pkgs.xterm}/bin/xterm" "${config.programs.walker.package}/bin/walker" "${config.home.profileDirectory}/bin/walker-project-list" "${config.home.profileDirectory}/bin/walker-project-switch" ]
      (builtins.readFile ./i3bar/status-event-driven.sh)
  );

  # Top bar: System monitoring script (polling every 2 seconds)
  systemMonitorScript = pkgs.writeShellScript "i3bar-status-system-monitor" (
    builtins.replaceStrings
      [ "@date@" "@grep@" "@awk@" "@sed@" ]
      [ "${pkgs.coreutils}/bin/date" "${pkgs.gnugrep}/bin/grep" "${pkgs.gawk}/bin/awk" "${pkgs.gnused}/bin/sed" ]
      (builtins.readFile ./i3bar/status-system-monitor.sh)
  );
in
{
  # Install i3bar package (part of i3)
  home.packages = with pkgs; [
    i3  # Includes i3bar
  ];

  # Top bar: System monitoring
  home.file.".config/i3/i3bar-top.conf".text = ''
    # Top bar: System monitoring (Catppuccin Mocha theme)
    # Updates every 2 seconds with system metrics
    # Separate bar for each output to avoid duplication

    # Top bar for rdp0 (monitor 1)
    bar {
      position top
      output rdp0
      status_command ${systemMonitorScript}

      # Font
      font pango:FiraCode Nerd Font, Font Awesome 6 Free 10

      # No system tray on top bar
      tray_output none

      # No workspace buttons on top bar
      workspace_buttons no

      # Separator
      separator_symbol " | "

      # Colors (Catppuccin Mocha theme)
      colors {
        background #1e1e2e
        statusline #cdd6f4
        separator  #6c7086
      }
    }

    # Top bar for rdp1 (monitor 2)
    bar {
      position top
      output rdp1
      status_command ${systemMonitorScript}

      # Font
      font pango:FiraCode Nerd Font, Font Awesome 6 Free 10

      # No system tray on top bar
      tray_output none

      # No workspace buttons on top bar
      workspace_buttons no

      # Separator
      separator_symbol " | "

      # Colors (Catppuccin Mocha theme)
      colors {
        background #1e1e2e
        statusline #cdd6f4
        separator  #6c7086
      }
    }

    # Top bar for rdp2 (monitor 3)
    bar {
      position top
      output rdp2
      status_command ${systemMonitorScript}

      # Font
      font pango:FiraCode Nerd Font, Font Awesome 6 Free 10

      # No system tray on top bar
      tray_output none

      # No workspace buttons on top bar
      workspace_buttons no

      # Separator
      separator_symbol " | "

      # Colors (Catppuccin Mocha theme)
      colors {
        background #1e1e2e
        statusline #cdd6f4
        separator  #6c7086
      }
    }
  '';

  # Bottom bar: Project context and workspaces
  home.file.".config/i3/i3bar-bottom.conf".text = ''
    # Bottom bar: Project context (Catppuccin Mocha theme)
    # Event-driven status updates via i3pm daemon subscriptions
    # Separate bar for each output with output-specific information

    # Bottom bar for rdp0 (monitor 1)
    bar {
      position bottom
      output rdp0
      status_command ${projectStatusScript} rdp0

      # Font
      font pango:FiraCode Nerd Font, Font Awesome 6 Free 10

      # System tray on bottom bar only
      tray_output primary

      # Workspace buttons on bottom bar
      workspace_buttons yes
      strip_workspace_numbers no

      # Separator
      separator_symbol " | "

      # Colors (Catppuccin Mocha theme)
      colors {
        background #1e1e2e
        statusline #cdd6f4
        separator  #6c7086

        # Workspace button colors: border background text
        focused_workspace  #b4befe #45475a #cdd6f4
        active_workspace   #313244 #313244 #cdd6f4
        inactive_workspace #1e1e2e #1e1e2e #bac2de
        urgent_workspace   #f38ba8 #f38ba8 #1e1e2e
        binding_mode       #f38ba8 #f38ba8 #1e1e2e
      }
    }

    # Bottom bar for rdp1 (monitor 2)
    bar {
      position bottom
      output rdp1
      status_command ${projectStatusScript} rdp1

      # Font
      font pango:FiraCode Nerd Font, Font Awesome 6 Free 10

      # No system tray on monitor 2
      tray_output none

      # Workspace buttons on bottom bar
      workspace_buttons yes
      strip_workspace_numbers no

      # Separator
      separator_symbol " | "

      # Colors (Catppuccin Mocha theme)
      colors {
        background #1e1e2e
        statusline #cdd6f4
        separator  #6c7086

        # Workspace button colors: border background text
        focused_workspace  #b4befe #45475a #cdd6f4
        active_workspace   #313244 #313244 #cdd6f4
        inactive_workspace #1e1e2e #1e1e2e #bac2de
        urgent_workspace   #f38ba8 #f38ba8 #1e1e2e
        binding_mode       #f38ba8 #f38ba8 #1e1e2e
      }
    }

    # Bottom bar for rdp2 (monitor 3)
    bar {
      position bottom
      output rdp2
      status_command ${projectStatusScript} rdp2

      # Font
      font pango:FiraCode Nerd Font, Font Awesome 6 Free 10

      # No system tray on monitor 3
      tray_output none

      # Workspace buttons on bottom bar
      workspace_buttons yes
      strip_workspace_numbers no

      # Separator
      separator_symbol " | "

      # Colors (Catppuccin Mocha theme)
      colors {
        background #1e1e2e
        statusline #cdd6f4
        separator  #6c7086

        # Workspace button colors: border background text
        focused_workspace  #b4befe #45475a #cdd6f4
        active_workspace   #313244 #313244 #cdd6f4
        inactive_workspace #1e1e2e #1e1e2e #bac2de
        urgent_workspace   #f38ba8 #f38ba8 #1e1e2e
        binding_mode       #f38ba8 #f38ba8 #1e1e2e
      }
    }
  '';

  # Create click handler script for future use
  home.file.".config/i3bar/click-handler.sh" = {
    text = ''
      #!/${pkgs.bash}/bin/bash
      # i3bar click event handler
      # Reads click events from stdin (JSON format)

      while read -r line; do
        # Parse click event
        name=$(echo "$line" | ${pkgs.jq}/bin/jq -r '.name')
        button=$(echo "$line" | ${pkgs.jq}/bin/jq -r '.button')

        case "$name" in
          project)
            if [ "$button" = "1" ]; then
              # Left click: Open project switcher
              PROJECT_LIST=$(${i3pmWrapper} project list --json 2>/dev/null)

              if [ -z "$PROJECT_LIST" ] || [ "$PROJECT_LIST" = "[]" ]; then
                ${pkgs.libnotify}/bin/notify-send "i3pm" "No projects configured"
                exit 0
              fi

              # Format for rofi: "icon display_name"
              FORMATTED=$(echo "$PROJECT_LIST" | ${pkgs.jq}/bin/jq -r '.[] | "\(.icon // "📁") \(.display_name // .name)\t\(.name)"')

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
            elif [ "$button" = "3" ]; then
              # Right click: Clear project
              ${i3pmWrapper} project clear
            fi
            ;;

          date)
            if [ "$button" = "1" ]; then
              # Left click: Show calendar (if available)
              ${pkgs.libnotify}/bin/notify-send "Calendar" "$(${pkgs.coreutils}/bin/date '+%A, %B %d, %Y')"
            fi
            ;;
        esac
      done
    '';
    executable = true;
  };
}

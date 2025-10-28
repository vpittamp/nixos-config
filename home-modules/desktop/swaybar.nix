# Swaybar Configuration with Event-Driven Status Updates
# Dual bars: Top bar for system monitoring, bottom bar for project context
# Parallel to i3bar.nix - adapted for Sway on M1 MacBook Pro
{ config, lib, pkgs, osConfig ? null, ... }:

let
  # Detect headless Sway configuration (Feature 046)
  isHeadless = osConfig != null && (osConfig.networking.hostName or "") == "nixos-hetzner-sway";
  # Create wrapper script to call i3pm from PATH
  # (i3pm is installed via home.packages in i3pm-deno.nix)
  i3pmWrapper = pkgs.writeShellScript "i3pm-caller" ''
    exec ${config.home.profileDirectory}/bin/i3pm "$@"
  '';

  # Bottom bar: Event-driven project status script with click handler
  # Reuses existing i3bar script (protocol-compatible with Sway)
  projectStatusScript = pkgs.writeShellScript "swaybar-status-event-driven" (
    builtins.replaceStrings
      [ "@i3pm@" "@jq@" "@sed@" "@date@" "@grep@" "@awk@" "@xterm@" "@walker@" "@walker_project_list@" "@walker_project_switch@" ]
      [ "${i3pmWrapper}" "${pkgs.jq}/bin/jq" "${pkgs.gnused}/bin/sed" "${pkgs.coreutils}/bin/date" "${pkgs.gnugrep}/bin/grep" "${pkgs.gawk}/bin/awk" "${pkgs.xterm}/bin/xterm" "${config.programs.walker.package}/bin/walker" "${config.home.profileDirectory}/bin/walker-project-list" "${config.home.profileDirectory}/bin/walker-project-switch" ]
      (builtins.readFile ./i3bar/status-event-driven.sh)
  );

  # Top bar: System monitoring script (polling every 2 seconds)
  # Reuses existing i3bar script (protocol-compatible with Sway)
  systemMonitorScript = pkgs.writeShellScript "swaybar-status-system-monitor" (
    builtins.replaceStrings
      [ "@date@" "@grep@" "@awk@" "@sed@" ]
      [ "${pkgs.coreutils}/bin/date" "${pkgs.gnugrep}/bin/grep" "${pkgs.gawk}/bin/awk" "${pkgs.gnused}/bin/sed" ]
      (builtins.readFile ./i3bar/status-system-monitor.sh)
  );
in
{
  # Swaybar configuration via home-manager
  # Sway bar protocol is identical to i3bar (FR-023)
  wayland.windowManager.sway.config.bars = if isHeadless then [
    # Headless mode (Feature 046): Single bar at top for HEADLESS-1
    {
      position = "top";
      statusCommand = "${projectStatusScript} HEADLESS-1";
      fonts = {
        names = [ "FiraCode Nerd Font" "Font Awesome 6 Free" ];
        size = 10.0;
      };
      trayOutput = "none";  # No system tray in headless mode
      workspaceButtons = true;  # Show workspace buttons
      colors = {
        background = "#1e1e2e";  # Catppuccin Mocha
        statusline = "#cdd6f4";
        separator = "#6c7086";
        focusedWorkspace = {
          background = "#89b4fa";
          border = "#89b4fa";
          text = "#1e1e2e";
        };
        activeWorkspace = {
          background = "#313244";
          border = "#313244";
          text = "#cdd6f4";
        };
        inactiveWorkspace = {
          background = "#1e1e2e";
          border = "#1e1e2e";
          text = "#cdd6f4";
        };
        urgentWorkspace = {
          background = "#f38ba8";
          border = "#f38ba8";
          text = "#1e1e2e";
        };
      };
      extraConfig = ''
        output HEADLESS-1
        separator_symbol " | "
        strip_workspace_numbers no
      '';
    }
  ] else [
    # M1 MacBook mode: Dual bars on two outputs
    # Top bar: System monitoring (eDP-1 - built-in Retina display)
    {
      position = "top";
      statusCommand = "${systemMonitorScript}";
      fonts = {
        names = [ "FiraCode Nerd Font" "Font Awesome 6 Free" ];
        size = 10.0;
      };
      trayOutput = "none";  # No system tray on top bar
      workspaceButtons = false;  # No workspace buttons on top bar
      colors = {
        background = "#1e1e2e";  # Catppuccin Mocha
        statusline = "#cdd6f4";
        separator = "#6c7086";
      };
      extraConfig = ''
        output eDP-1
        separator_symbol " | "
      '';
    }

    # Top bar: System monitoring (HDMI-A-1 - external monitor)
    {
      position = "top";
      statusCommand = "${systemMonitorScript}";
      fonts = {
        names = [ "FiraCode Nerd Font" "Font Awesome 6 Free" ];
        size = 10.0;
      };
      trayOutput = "none";
      workspaceButtons = false;
      colors = {
        background = "#1e1e2e";
        statusline = "#cdd6f4";
        separator = "#6c7086";
      };
      extraConfig = ''
        output HDMI-A-1
        separator_symbol " | "
      '';
    }

    # Bottom bar: Project context (eDP-1)
    {
      position = "bottom";
      statusCommand = "${projectStatusScript} eDP-1";
      fonts = {
        names = [ "FiraCode Nerd Font" "Font Awesome 6 Free" ];
        size = 10.0;
      };
      trayOutput = "primary";  # System tray on bottom bar
      workspaceButtons = true;  # Workspace buttons on bottom bar
      colors = {
        background = "#1e1e2e";
        statusline = "#cdd6f4";
        separator = "#6c7086";
        focusedWorkspace = {
          background = "#89b4fa";
          border = "#89b4fa";
          text = "#1e1e2e";
        };
        activeWorkspace = {
          background = "#313244";
          border = "#313244";
          text = "#cdd6f4";
        };
        inactiveWorkspace = {
          background = "#1e1e2e";
          border = "#1e1e2e";
          text = "#cdd6f4";
        };
        urgentWorkspace = {
          background = "#f38ba8";
          border = "#f38ba8";
          text = "#1e1e2e";
        };
      };
      extraConfig = ''
        output eDP-1
        separator_symbol " | "
        strip_workspace_numbers no
      '';
    }

    # Bottom bar: Project context (HDMI-A-1)
    {
      position = "bottom";
      statusCommand = "${projectStatusScript} HDMI-A-1";
      fonts = {
        names = [ "FiraCode Nerd Font" "Font Awesome 6 Free" ];
        size = 10.0;
      };
      trayOutput = "none";  # Tray only on primary
      workspaceButtons = true;
      colors = {
        background = "#1e1e2e";
        statusline = "#cdd6f4";
        separator = "#6c7086";
        focusedWorkspace = {
          background = "#89b4fa";
          border = "#89b4fa";
          text = "#1e1e2e";
        };
        activeWorkspace = {
          background = "#313244";
          border = "#313244";
          text = "#cdd6f4";
        };
        inactiveWorkspace = {
          background = "#1e1e2e";
          border = "#1e1e2e";
          text = "#cdd6f4";
        };
        urgentWorkspace = {
          background = "#f38ba8";
          border = "#f38ba8";
          text = "#1e1e2e";
        };
      };
      extraConfig = ''
        output HDMI-A-1
        separator_symbol " | "
        strip_workspace_numbers no
      '';
    }
  ];
}

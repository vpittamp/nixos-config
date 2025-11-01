# Swaybar Configuration with Event-Driven Status Updates
# Dual bars: Top bar for system monitoring, bottom bar for project context
# Parallel to i3bar.nix - adapted for Sway on M1 MacBook Pro
{ config, lib, pkgs, osConfig ? null, sharedPythonEnv, ... }:

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

  # Top bar: Enhanced system status (Feature 052)
  # Uses Python-based status generator with D-Bus integration
  # Falls back to legacy shell script if swaybar-enhanced is disabled
  # Note: Uses shared Python environment from python-environment.nix
  enhancedStatusScript = pkgs.writeShellScript "swaybar-enhanced-status" ''
    export GI_TYPELIB_PATH="${pkgs.glib.out}/lib/girepository-1.0:${pkgs.gobject-introspection}/lib/girepository-1.0"
    exec ${sharedPythonEnv}/bin/python \
      ${config.xdg.configHome}/sway/swaybar/status-generator.py
  '';

  # Legacy top bar: System monitoring script (polling every 2 seconds)
  # Reuses existing i3bar script (protocol-compatible with Sway)
  systemMonitorScript = pkgs.writeShellScript "swaybar-status-system-monitor" (
    builtins.replaceStrings
      [ "@date@" "@grep@" "@awk@" "@sed@" ]
      [ "${pkgs.coreutils}/bin/date" "${pkgs.gnugrep}/bin/grep" "${pkgs.gawk}/bin/awk" "${pkgs.gnused}/bin/sed" ]
      (builtins.readFile ./i3bar/status-system-monitor.sh)
  );

  # Select status script based on swaybar-enhanced enablement
  topBarStatusScript = if (config.programs.swaybar-enhanced.enable or false)
    then enhancedStatusScript
    else systemMonitorScript;
in
{
  # Swaybar configuration via home-manager
  # Sway bar protocol is identical to i3bar (FR-023)
  wayland.windowManager.sway.config.bars = if isHeadless then [
    # Headless mode (Feature 048): Dual bars for each of three VNC outputs
    # Each VNC connection shows one output with its own bars
    # Top bar: System monitoring, Bottom bar: Project context + workspaces

    # Monitor 1 (HEADLESS-1) - Top bar: Enhanced system status (Feature 052)
    {
      position = "top";
      statusCommand = "${topBarStatusScript}";
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
        # Catppuccin Mocha theme for mode indicator (Feature 042 - T034)
        bindingMode = {
          background = "#313244";  # surface0
          border = "#a6e3a1";      # green
          text = "#cdd6f4";        # text
        };
      };
      extraConfig = ''
        output HEADLESS-1
        separator_symbol " | "
        binding_mode_indicator yes
      '';
    }

    # Monitor 1 (HEADLESS-1) - Bottom bar: Project context with workspaces
    {
      position = "bottom";
      statusCommand = "${projectStatusScript} HEADLESS-1";
      fonts = {
        names = [ "FiraCode Nerd Font" "Font Awesome 6 Free" ];
        size = 10.0;
      };
      trayOutput = "none";
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
        # Catppuccin Mocha theme for mode indicator (Feature 042 - T034)
        bindingMode = {
          background = "#313244";  # surface0
          border = "#a6e3a1";      # green
          text = "#cdd6f4";        # text
        };
      };
      extraConfig = ''
        output HEADLESS-1
        separator_symbol " | "
        strip_workspace_numbers no
        binding_mode_indicator yes
      '';
    }

    # Monitor 2 (HEADLESS-2) - Top bar: Enhanced system status (Feature 052)
    {
      position = "top";
      statusCommand = "${topBarStatusScript}";
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
        output HEADLESS-2
        separator_symbol " | "
      '';
    }

    # Monitor 2 (HEADLESS-2) - Bottom bar: Project context with workspaces
    {
      position = "bottom";
      statusCommand = "${projectStatusScript} HEADLESS-2";
      fonts = {
        names = [ "FiraCode Nerd Font" "Font Awesome 6 Free" ];
        size = 10.0;
      };
      trayOutput = "none";
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
        # Catppuccin Mocha theme for mode indicator (Feature 042 - T034)
        bindingMode = {
          background = "#313244";  # surface0
          border = "#a6e3a1";      # green
          text = "#cdd6f4";        # text
        };
      };
      extraConfig = ''
        output HEADLESS-2
        separator_symbol " | "
        strip_workspace_numbers no
        binding_mode_indicator yes
      '';
    }

    # Monitor 3 (HEADLESS-3) - Top bar: Enhanced system status (Feature 052)
    {
      position = "top";
      statusCommand = "${topBarStatusScript}";
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
        output HEADLESS-3
        separator_symbol " | "
      '';
    }

    # Monitor 3 (HEADLESS-3) - Bottom bar: Project context with workspaces
    {
      position = "bottom";
      statusCommand = "${projectStatusScript} HEADLESS-3";
      fonts = {
        names = [ "FiraCode Nerd Font" "Font Awesome 6 Free" ];
        size = 10.0;
      };
      trayOutput = "none";
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
        # Catppuccin Mocha theme for mode indicator (Feature 042 - T034)
        bindingMode = {
          background = "#313244";  # surface0
          border = "#a6e3a1";      # green
          text = "#cdd6f4";        # text
        };
      };
      extraConfig = ''
        output HEADLESS-3
        separator_symbol " | "
        strip_workspace_numbers no
        binding_mode_indicator yes
      '';
    }
  ] else [
    # M1 MacBook mode: Dual bars on two outputs
    # Top bar: Enhanced system status (Feature 052) - eDP-1 (built-in Retina display)
    # Note: Font size 10.0 for HiDPI Retina display (2x scaling = effective 20.0)
    {
      position = "top";
      statusCommand = "${topBarStatusScript}";
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

    # Top bar: Enhanced system status (Feature 052) - HDMI-A-1 (external monitor)
    {
      position = "top";
      statusCommand = "${topBarStatusScript}";
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
      trayOutput = "eDP-1";  # System tray on bottom bar (M1 built-in display)
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
        # Catppuccin Mocha theme for mode indicator (Feature 042 - T034)
        bindingMode = {
          background = "#313244";  # surface0
          border = "#a6e3a1";      # green
          text = "#cdd6f4";        # text
        };
      };
      extraConfig = ''
        output eDP-1
        separator_symbol " | "
        strip_workspace_numbers no
        binding_mode_indicator yes
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
        # Catppuccin Mocha theme for mode indicator (Feature 042 - T034)
        bindingMode = {
          background = "#313244";  # surface0
          border = "#a6e3a1";      # green
          text = "#cdd6f4";        # text
        };
      };
      extraConfig = ''
        output HDMI-A-1
        separator_symbol " | "
        strip_workspace_numbers no
        binding_mode_indicator yes
      '';
    }
  ];
}

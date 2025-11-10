# Swaybar Configuration with Event-Driven Status Updates
# Dual bars: Top bar for system monitoring, bottom bar for project context
# Parallel to i3bar.nix - adapted for Sway on M1 MacBook Pro
{ config, lib, pkgs, osConfig ? null, sharedPythonEnv, ... }:

let
  # Detect headless Sway configuration (Feature 046)
  isHeadless = osConfig != null && (osConfig.networking.hostName or "") == "nixos-hetzner-sway";

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
  wayland.windowManager.sway.config.bars =
    let
      mkTopBar = { output, trayOutput ? "none", bindingModeIndicator ? false }:
        {
          position = "top";
          statusCommand = "${topBarStatusScript}";
          fonts = {
            names = [ "FiraCode Nerd Font" "Font Awesome 6 Free" ];
            size = 8.0;
          };
          trayOutput = trayOutput;
          workspaceButtons = false;
          colors = {
            background = "#1e1e2e";
            statusline = "#cdd6f4";
            separator = "#6c7086";
            bindingMode = {
              background = "#313244";  # surface0
              border = "#a6e3a1";      # green
              text = "#cdd6f4";        # text
            };
          };
          extraConfig = ''
            output ${output}
            separator_symbol " | "
            ${lib.optionalString bindingModeIndicator "binding_mode_indicator yes"}
          '';
        };

      headlessBars = [
        { output = "HEADLESS-1"; trayOutput = "HEADLESS-1"; bindingModeIndicator = true; }
        { output = "HEADLESS-2"; }
        { output = "HEADLESS-3"; }
      ];

      laptopBars = [
        { output = "eDP-1"; trayOutput = "eDP-1"; }
        { output = "HDMI-A-1"; }
      ];
    in
      map mkTopBar (if isHeadless then headlessBars else laptopBars);
}

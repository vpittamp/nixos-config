# Eww-Based Top Bar with Catppuccin Mocha Theme
# Feature 060: Replace Swaybar top bar with Eww widgets for visual consistency
# Displays system metrics (CPU, memory, disk, network, temperature, time)
{ config, lib, pkgs, osConfig ? null, ... }:

let
  cfg = config.programs.eww-top-bar;

  # Feature 057: Import unified theme colors (Catppuccin Mocha)
  # Use the same color palette as unified-bar-theme.nix
  mocha = {
    base = "#1e1e2e";      # Background base
    mantle = "#181825";    # Darker background
    surface0 = "#313244";  # Surface layer 1
    surface1 = "#45475a";  # Surface layer 2
    overlay0 = "#6c7086";  # Overlay/border
    text = "#cdd6f4";      # Primary text
    subtext0 = "#a6adc8";  # Dimmed text
    blue = "#89b4fa";      # CPU - focused accent
    sapphire = "#74c7ec";  # Memory
    sky = "#89dceb";       # Disk
    teal = "#94e2d5";      # Network
    green = "#a6e3a1";     # Success/healthy
    yellow = "#f9e2af";    # Warning
    peach = "#fab387";     # Temperature
    red = "#f38ba8";       # Urgent/critical
    mauve = "#cba6f7";     # Border accent
  };

  # Detect host type from hostname
  hostname = osConfig.networking.hostName or "";
  isHeadless = hostname == "hetzner";
  isRyzen = hostname == "ryzen";

  # Multi-monitor output configuration
  # Headless: HEADLESS-1/2/3 (Hetzner VNC)
  # Ryzen Desktop: DP-1, HDMI-A-1, DP-2, DP-3 (NVIDIA 4-monitor setup)
  # Laptop: eDP-1 (built-in), HDMI-A-1 (external - only when connected)
  topBarOutputs =
    if isHeadless then [
      { name = "HEADLESS-1"; showTray = true; }
    ] else if isRyzen then [
      # Ryzen desktop: 4-monitor bare-metal setup with NVIDIA RTX 5070
      # Show top bar on all monitors, tray only on primary
      { name = "DP-1"; showTray = true; }    # Primary - shows system tray
      { name = "HDMI-A-1"; showTray = false; }
      { name = "DP-2"; showTray = false; }
      { name = "DP-3"; showTray = false; }
    ] else [
      # Laptop: built-in display (eDP-1)
      # TODO: Auto-detect connected monitors and open windows dynamically
      { name = "eDP-1"; showTray = true; }
    ];

  # Sanitize output names for Eww window IDs (lowercase, replace special chars)
  sanitizeOutputName = name:
    lib.toLower (
      lib.replaceStrings [" " ":" "/" "_" "-"] ["" "" "" "" ""] name
    );

  # Hardware detection script (Python)
  # Detects battery, bluetooth, thermal sensors at runtime
  hardwareDetectScript = pkgs.writeText "hardware-detect.py" ''
    #!/usr/bin/env python3
    """Hardware detection for Eww top bar widgets

    Returns JSON with hardware capabilities:
    - battery: true if /sys/class/power_supply/BAT* exists
    - bluetooth: true if bluetoothctl available
    - thermal: true if /sys/class/thermal/thermal_zone* exists
    """
    import json
    import os
    from pathlib import Path

    def detect_battery():
        """Check for battery hardware"""
        return any(Path("/sys/class/power_supply").glob("BAT*"))

    def detect_bluetooth():
        """Check for bluetooth hardware via bluez D-Bus"""
        try:
            import pydbus
            bus = pydbus.SystemBus()
            bluez = bus.get("org.bluez", "/")
            return True
        except Exception:
            return False

    def detect_thermal():
        """Check for thermal sensors"""
        return any(Path("/sys/class/thermal").glob("thermal_zone*"))

    if __name__ == "__main__":
        capabilities = {
            "battery": detect_battery(),
            "bluetooth": detect_bluetooth(),
            "thermal": detect_thermal(),
        }
        print(json.dumps(capabilities))
  '';

in
{
  options.programs.eww-top-bar = {
    enable = lib.mkEnableOption "Eww-based top bar with system metrics";

    updateIntervals = {
      systemMetrics = lib.mkOption {
        type = lib.types.int;
        default = 2;
        description = "Update interval for CPU/memory metrics (seconds)";
      };

      diskNetwork = lib.mkOption {
        type = lib.types.int;
        default = 5;
        description = "Update interval for disk/network metrics (seconds)";
      };

      dateTime = lib.mkOption {
        type = lib.types.int;
        default = 1;
        description = "Update interval for date/time (seconds)";
      };

      daemonHealth = lib.mkOption {
        type = lib.types.int;
        default = 5;
        description = "Update interval for i3pm daemon health (seconds)";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Add eww package to home environment
    # NOTE: Click handler apps (pavucontrol, gnome-calendar, gnome-control-center, blueman)
    # are VERY large (~3.8 GB total) and temporarily disabled to test core functionality
    home.packages = [
      pkgs.eww
      # pkgs.pavucontrol            # Volume control (click handler for volume widget) - 1.0 GiB
      # pkgs.gnome-calendar          # Calendar app (click handler for datetime widget) - 1.8 GiB
      # pkgs.gnome-control-center  # Network settings (click handler for network widget) - 266 MiB
      # pkgs.blueman                # Bluetooth manager (click handler for bluetooth widget) - 793 MiB
    ];

    # Install Python scripts to config directory
    xdg.configFile."eww/eww-top-bar/scripts/hardware-detect.py" = {
      source = hardwareDetectScript;
      executable = true;
    };

    xdg.configFile."eww/eww-top-bar/scripts/system-metrics.py" = {
      source = ./eww-top-bar/scripts/system-metrics.py;
      executable = true;
    };

    xdg.configFile."eww/eww-top-bar/scripts/volume-monitor.py" = {
      source = ./eww-top-bar/scripts/volume-monitor.py;
      executable = true;
    };

    xdg.configFile."eww/eww-top-bar/scripts/battery-monitor.py" = {
      source = ./eww-top-bar/scripts/battery-monitor.py;
      executable = true;
    };

    xdg.configFile."eww/eww-top-bar/scripts/bluetooth-monitor.py" = {
      source = ./eww-top-bar/scripts/bluetooth-monitor.py;
      executable = true;
    };

    xdg.configFile."eww/eww-top-bar/scripts/active-project.py" = {
      source = ./eww-top-bar/scripts/active-project.py;
      executable = true;
    };

    xdg.configFile."eww/eww-top-bar/scripts/build-health.sh" = {
      source = ./eww-top-bar/scripts/build-health.sh;
      executable = true;
    };

    xdg.configFile."eww/eww-top-bar/scripts/active-outputs-status.sh" = {
      source = ./eww-top-bar/scripts/active-outputs-status.sh;
      executable = true;
    };

    xdg.configFile."eww/eww-top-bar/scripts/i3pm-health.sh" = {
      source = ./eww-top-bar/scripts/i3pm-health.sh;
      executable = true;
    };

    # Feature 061: WiFi status script
    xdg.configFile."eww/eww-top-bar/scripts/wifi-status.sh" = {
      source = ./eww-top-bar/scripts/wifi-status.sh;
      executable = true;
    };

    # Feature 061: Volume status script
    xdg.configFile."eww/eww-top-bar/scripts/volume-status.sh" = {
      source = ./eww-top-bar/scripts/volume-status.sh;
      executable = true;
    };

    # Feature 110: Notification monitor script (streaming backend for badge)
    xdg.configFile."eww/eww-top-bar/scripts/notification-monitor.py" = {
      source = ./eww-top-bar/scripts/notification-monitor.py;
      executable = true;
    };

    # Eww widget definitions (Yuck syntax)
    # Generated from eww.yuck.nix module
    xdg.configFile."eww/eww-top-bar/eww.yuck".text = import ./eww-top-bar/eww.yuck.nix {
      inherit config lib pkgs;
      inherit (pkgs.stdenv.hostPlatform) system;
      osConfig = osConfig;
      # Pass monitor configuration for dynamic window generation
      inherit topBarOutputs sanitizeOutputName;
    };

    # Eww styles (CSS/SCSS)
    # Generated from eww.scss.nix module
    xdg.configFile."eww/eww-top-bar/eww.scss".text = import ./eww-top-bar/eww.scss.nix {
      inherit config lib pkgs;
    };

    # systemd user service for Eww top bar
    # Auto-restarts on failure, runs after Sway session starts
    systemd.user.services.eww-top-bar = {
      Unit = {
        Description = "Eww top bar with system metrics";
        Documentation = "https://github.com/elkowar/eww";
        PartOf = [ "sway-session.target" ];
        # Feature 117: Depend on i3-project-daemon for health checks
        After = [ "sway-session.target" "i3-project-daemon.service" ];
        Wants = [ "i3-project-daemon.service" ];
      };

      Service = {
        Type = "simple";
        ExecStart = "${pkgs.eww}/bin/eww daemon --no-daemonize --config ${config.xdg.configHome}/eww/eww-top-bar";
        # Only open defined windows; headless config now defines just HEADLESS-1 window
        ExecStartPost = let
          windowIds = lib.concatMapStringsSep " " (output: "top-bar-${sanitizeOutputName output.name}") topBarOutputs;
        in "${pkgs.eww}/bin/eww open-many ${windowIds} --config ${config.xdg.configHome}/eww/eww-top-bar";
        ExecStop = "${pkgs.eww}/bin/eww kill --config ${config.xdg.configHome}/eww/eww-top-bar";
        Restart = "on-failure";
        RestartSec = 3;
      };

      Install = {
        WantedBy = [ "sway-session.target" ];
      };
    };
  };
}

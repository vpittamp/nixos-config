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
  # Uses simple file/subprocess checks instead of D-Bus to avoid hangs
  hardwareDetectScript = pkgs.writeText "hardware-detect.py" ''
    #!/usr/bin/env python3
    """Hardware detection for Eww top bar widgets

    Returns JSON with hardware capabilities:
    - battery: true if /sys/class/power_supply/BAT* exists
    - bluetooth: true if bluetoothctl available and bluetooth adapter exists
    - thermal: true if /sys/class/thermal/thermal_zone* exists
    """
    import json
    from pathlib import Path

    def detect_battery():
        """Check for battery hardware"""
        return any(Path("/sys/class/power_supply").glob("BAT*"))

    def detect_bluetooth():
        """Check for bluetooth hardware via hci devices (fast file check)"""
        try:
            # Check if any Bluetooth adapter exists via sysfs
            return any(Path("/sys/class/bluetooth").glob("hci*"))
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

  # Feature 110: Spinner animation script for pulsating effect
  # Uses indexed frame cycling via /tmp/eww-topbar-spinner-idx file
  topbarSpinnerScript = pkgs.writeShellScriptBin "eww-topbar-spinner-frame" ''
    #!/usr/bin/env bash
    IDX_FILE="/tmp/eww-topbar-spinner-idx"
    IDX=$(cat "$IDX_FILE" 2>/dev/null || echo 0)
    # Braille spinner: ⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏
    FRAMES=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    echo "''${FRAMES[$IDX]}"
    NEXT=$(( (IDX + 1) % 10 ))
    echo "$NEXT" > "$IDX_FILE"
  '';

  # Feature 110: Opacity script for fade effect (synced with spinner)
  topbarSpinnerOpacityScript = pkgs.writeShellScriptBin "eww-topbar-spinner-opacity" ''
    #!/usr/bin/env bash
    IDX=$(cat /tmp/eww-topbar-spinner-idx 2>/dev/null || echo 0)
    # Opacity values: fade in, hold, fade out
    case $IDX in
      0|9)  echo "0.4" ;;
      1|8)  echo "0.6" ;;
      2|7)  echo "0.8" ;;
      3|4|5|6)  echo "1.0" ;;
      *)  echo "1.0" ;;
    esac
  '';

  togglePowermenuScript = pkgs.writeShellScriptBin "toggle-topbar-powermenu" ''
    set -euo pipefail

    CFG="$HOME/.config/eww/eww-top-bar"
    EWW="${pkgs.eww}/bin/eww"

    sanitize() {
      # Match sanitizeOutputName in Nix: lowercase and drop separators.
      echo "$1" | tr '[:upper:]' '[:lower:]' | tr -d ' :/_-'
    }

    target_raw="''${1:-}"

    # Close all powermenus if one is already open.
    active="$("$EWW" --config "$CFG" active-windows 2>/dev/null || true)"
    if echo "$active" | ${pkgs.gnugrep}/bin/grep -q '^powermenu-'; then
      echo "$active" | ${pkgs.gnugrep}/bin/grep '^powermenu-' | while read -r w; do
        [ -n "$w" ] && "$EWW" --config "$CFG" close "$w" || true
      done
      "$EWW" --config "$CFG" update powermenu_confirm_action=\"\" 2>/dev/null || true
      exit 0
    fi

    # Resolve which powermenu window to open.
    windows="$("$EWW" --config "$CFG" list-windows 2>/dev/null || true)"
    if [ -z "$windows" ]; then
      echo "toggle-topbar-powermenu: no Eww windows found (is eww-top-bar running?)" >&2
      exit 1
    fi

    target_id=""

    if [ -n "$target_raw" ]; then
      target_id="$(sanitize "$target_raw")"
    else
      # Use focused output (Wayland/Sway), fall back to first powermenu window.
      if command -v swaymsg >/dev/null 2>&1 && command -v ${pkgs.jq}/bin/jq >/dev/null 2>&1; then
        focused_output="$(swaymsg -t get_outputs | ${pkgs.jq}/bin/jq -r '.[] | select(.focused==true) | .name' | head -n1 || true)"
        if [ -n "$focused_output" ] && [ "$focused_output" != "null" ]; then
          target_id="$(sanitize "$focused_output")"
        fi
      fi
    fi

    target_window=""
    if [ -n "$target_id" ] && echo "$windows" | ${pkgs.gnugrep}/bin/grep -qx "powermenu-$target_id"; then
      target_window="powermenu-$target_id"
    else
      target_window="$(echo "$windows" | ${pkgs.gnugrep}/bin/grep '^powermenu-' | head -n1 || true)"
    fi

    if [ -z "$target_window" ]; then
      echo "toggle-topbar-powermenu: powermenu windows not defined in config" >&2
      exit 1
    fi

    "$EWW" --config "$CFG" update powermenu_confirm_action=\"\" 2>/dev/null || true
    "$EWW" --config "$CFG" open "$target_window"
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
      togglePowermenuScript
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

    # Feature 123: AI sessions now use deflisten with otel-ai-monitor service
    # The legacy ai-sessions-status.sh polling script has been removed

    # Feature 117: Spinner scripts for AI working animation
    xdg.configFile."eww/eww-top-bar/scripts/spinner-frame.sh" = {
      source = ./eww-top-bar/scripts/spinner-frame.sh;
      executable = true;
    };

    xdg.configFile."eww/eww-top-bar/scripts/spinner-opacity.sh" = {
      source = ./eww-top-bar/scripts/spinner-opacity.sh;
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
      # Feature 110: Spinner scripts for pulsating animation
      inherit topbarSpinnerScript topbarSpinnerOpacityScript;
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
        # Feature 123: Depend on otel-ai-monitor for AI session indicators
        After = [ "sway-session.target" "i3-project-daemon.service" "otel-ai-monitor.service" ];
        Wants = [ "i3-project-daemon.service" "otel-ai-monitor.service" ];
      };

      Service = {
        Type = "simple";
        # Pre-start: kill any orphan daemon for this config and clean stale socket
        ExecStartPre = "${pkgs.bash}/bin/bash -c '${pkgs.eww}/bin/eww --config ${config.xdg.configHome}/eww/eww-top-bar kill 2>/dev/null || true'";
        ExecStart = "${pkgs.eww}/bin/eww daemon --no-daemonize --config ${config.xdg.configHome}/eww/eww-top-bar";
        # Wait for daemon, close any stale windows, then open fresh ones
        ExecStartPost = let
          windowIds = lib.concatMapStringsSep " " (output: "top-bar-${sanitizeOutputName output.name}") topBarOutputs;
          ewwCmd = "${pkgs.eww}/bin/eww --config ${config.xdg.configHome}/eww/eww-top-bar";
        in "${pkgs.bash}/bin/bash -c 'for i in $(seq 1 50); do ${pkgs.coreutils}/bin/timeout 1s ${ewwCmd} ping >/dev/null 2>&1 && break; sleep 0.2; done; ${ewwCmd} close-all 2>/dev/null || true; ${ewwCmd} open-many ${windowIds}'";
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

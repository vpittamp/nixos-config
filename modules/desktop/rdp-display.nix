{ config, lib, pkgs, ... }:

let
  rdpEnabled = (config.services.xrdp.enable or false);

  # Panel positioning script
  panelPositioningScript = pkgs.writeShellScript "fix-panel-positions" ''
    CONFIG_FILE="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"

    # Wait for displays to stabilize
    sleep 3

    # Get display info
    if ! command -v xrandr >/dev/null 2>&1; then
      echo "xrandr not found" >> /tmp/rdp-display.log
      exit 1
    fi

    # Detect screen positions
    MONITOR_INFO=$(xrandr --query 2>/dev/null | grep " connected" | \
      awk '{
        if (match($0, /\+([0-9]+)\+/, pos)) {
          x_pos = pos[1]
          print NR-1, x_pos
        }
      }')

    LEFT_SCREEN=""
    CENTER_SCREEN=""
    RIGHT_SCREEN=""
    while read screen_num x_pos; do
      if [ "$x_pos" -eq 0 ]; then
        LEFT_SCREEN=$screen_num
      elif [ "$x_pos" -gt 1000 ] && [ "$x_pos" -lt 2500 ]; then
        CENTER_SCREEN=$screen_num
      elif [ "$x_pos" -gt 3000 ]; then
        RIGHT_SCREEN=$screen_num
      fi
    done <<< "$MONITOR_INFO"

    # Fallbacks
    CENTER_SCREEN=''${CENTER_SCREEN:-2}
    LEFT_SCREEN=''${LEFT_SCREEN:-1}
    RIGHT_SCREEN=''${RIGHT_SCREEN:-0}

    echo "$(date): Screen mapping: Left=$LEFT_SCREEN, Center=$CENTER_SCREEN, Right=$RIGHT_SCREEN" >> /tmp/rdp-display.log

    if [ ! -f "$CONFIG_FILE" ]; then
      echo "$(date): Config file not found" >> /tmp/rdp-display.log
      exit 1
    fi

    # Find PRIMARY panel (with systemtray)
    PRIMARY_PANEL=$(grep -B 200 "plugin=org.kde.plasma.systemtray" "$CONFIG_FILE" | \
                  grep -E "^\[Containments\]\[[0-9]+\]$" | tail -1 | \
                  sed 's/\[Containments\]\[\([0-9]\+\)\]/\1/')

    # Find all panels
    ALL_PANELS=$(grep -B 10 "^plugin=org.kde.panel$" "$CONFIG_FILE" | \
                grep -E "^\[Containments\]\[[0-9]+\]$" | \
                sed 's/\[Containments\]\[\([0-9]\+\)\]/\1/' | sort -u)

    # Move primary panel to center
    if [ -n "$PRIMARY_PANEL" ]; then
      sed -i "/^\[Containments\]\[$PRIMARY_PANEL\]/,/^\[/ s/^lastScreen=.*/lastScreen=$CENTER_SCREEN/" "$CONFIG_FILE"
      echo "$(date): Primary panel $PRIMARY_PANEL -> Screen $CENTER_SCREEN" >> /tmp/rdp-display.log
    fi

    # Distribute secondary panels
    SECONDARY_COUNT=0
    for panel in $ALL_PANELS; do
      if [ "$panel" != "$PRIMARY_PANEL" ]; then
        if [ $SECONDARY_COUNT -eq 0 ]; then
          sed -i "/^\[Containments\]\[$panel\]/,/^\[/ s/^lastScreen=.*/lastScreen=$LEFT_SCREEN/" "$CONFIG_FILE"
          echo "$(date): Secondary panel $panel -> Screen $LEFT_SCREEN" >> /tmp/rdp-display.log
        else
          sed -i "/^\[Containments\]\[$panel\]/,/^\[/ s/^lastScreen=.*/lastScreen=$RIGHT_SCREEN/" "$CONFIG_FILE"
          echo "$(date): Secondary panel $panel -> Screen $RIGHT_SCREEN" >> /tmp/rdp-display.log
        fi
        SECONDARY_COUNT=$((SECONDARY_COUNT + 1))
      fi
    done
  '';

in
{
  config = lib.mkIf rdpEnabled {
    # Comfortable default DPI for remote sessions
    services.xserver.dpi = lib.mkDefault 180;

    # Helpful tools
    environment.systemPackages = with pkgs; [
      xorg.xrandr
      pavucontrol
      (pkgs.writeShellScriptBin "fix-panel-positions" ''
        ${panelPositioningScript}
        echo "Restarting plasmashell..."
        kquitapp6 plasmashell 2>/dev/null || kquitapp5 plasmashell 2>/dev/null || pkill plasmashell || true
        sleep 2
        plasmashell &
        echo "Done!"
      '')
    ];

    # Avoid Qt double scaling; let Plasma manage scaling
    services.xserver.displayManager.sessionCommands = lib.mkAfter ''
      export QT_AUTO_SCREEN_SCALE_FACTOR=0
      export QT_ENABLE_HIGHDPI_SCALING=0
      export PLASMA_USE_QT_SCALING=1

      # Mark this as an RDP session
      export XRDP_SESSION=1
      export RDP_SESSION=1

      # GTK apps: integer scale only
      export GDK_SCALE=2
      unset GDK_DPI_SCALE

      # Larger cursor for remote sessions
      export XCURSOR_SIZE=48

      # Align font DPI and set per-output scale for XRDP virtual display
      kwriteconfig5 --file kcmfonts --group General --key forceFontDPI 180 || true
      kwriteconfig5 --file kdeglobals --group KScreen --key ScreenScaleFactors "XORGXRDP0=2;" || true

      # Fix panel positions on login
      (
        ${panelPositioningScript}
        # Restart plasmashell to apply changes
        kquitapp6 plasmashell 2>/dev/null || kquitapp5 plasmashell 2>/dev/null || pkill plasmashell || true
        sleep 2
        plasmashell &
        echo "$(date): Plasmashell restarted" >> /tmp/rdp-display.log
      ) &

      # Prefer XRDP audio devices when present (PipeWire-Pulse compat)
      (
        tries=0
        while [ $tries -lt 10 ]; do
          if command -v pactl >/dev/null 2>&1; then
            sink=$(pactl list short sinks 2>/dev/null | awk '/xrdp|rdp/i {print $1; exit}')
            source=$(pactl list short sources 2>/dev/null | awk '/xrdp|rdp/i {print $1; exit}')
            if [ -n "$sink" ]; then
              pactl set-default-sink "$sink" || true
              for input in $(pactl list short sink-inputs 2>/dev/null | awk '{print $1}'); do
                pactl move-sink-input "$input" "$sink" || true
              done
            fi
            if [ -n "$source" ]; then
              pactl set-default-source "$source" || true
              for rec in $(pactl list short source-outputs 2>/dev/null | awk '{print $1}'); do
                pactl move-source-output "$rec" "$source" || true
              done
            fi
            [ -n "$sink$source" ] && break
          fi
          tries=$((tries+1))
          sleep 1
        done
      ) >/dev/null 2>&1 &
    '';
  };
}

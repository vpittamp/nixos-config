{ config, lib, pkgs, ... }:

let
  rdpEnabled = (config.services.xrdp.enable or false);
in
{
  config = lib.mkIf rdpEnabled {
    # Comfortable default DPI for remote sessions
    services.xserver.dpi = lib.mkDefault 180;

    # Helpful tools
    environment.systemPackages = with pkgs; [
      xorg.xrandr
      pavucontrol
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

      # Ensure panel is on primary screen for RDP sessions
      # This handles dynamic monitor configurations
      (
        sleep 2
        # Get primary display info
        if command -v xrandr >/dev/null 2>&1; then
          PRIMARY=$(xrandr --query 2>/dev/null | grep " connected" | head -1 | awk '{print $1}')
          echo "RDP Primary display detected: $PRIMARY" >> /tmp/rdp-display.log

          # Update panel to primary screen (screen 0)
          CONFIG_FILE="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
          if [ -f "$CONFIG_FILE" ]; then
            # Find and update panel configuration
            PANEL_ID=$(grep -E "^\[Containments\]\[[0-9]+\]$" "$CONFIG_FILE" | \
                      while read line; do
                        id=$(echo "$line" | sed 's/\[Containments\]\[\([0-9]\+\)\]/\1/')
                        if grep -A 3 "\[Containments\]\[$id\]" "$CONFIG_FILE" | grep -q "plugin=org.kde.panel"; then
                          echo "$id"
                          break
                        fi
                      done)

            if [ -n "$PANEL_ID" ]; then
              # Use kwriteconfig to update panel screen
              kwriteconfig5 --file "$CONFIG_FILE" --group "Containments" --group "$PANEL_ID" --key lastScreen 0
              echo "Updated panel $PANEL_ID to screen 0" >> /tmp/rdp-display.log
            fi
          fi
        fi
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

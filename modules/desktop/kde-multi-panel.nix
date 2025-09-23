# KDE Multi-Monitor Panel Configuration
# Ensures primary taskbar on screen 0 and secondary panels on all other monitors
{ config, lib, pkgs, ... }:

let
  kdeEnabled = config.services.desktopManager.plasma6.enable or false;
  rdpEnabled = config.services.xrdp.enable or false;

  # Script to dynamically manage panels for multiple monitors
  panelManagerScript = pkgs.writeShellScript "kde-multi-panel-manager" ''
    #!/bin/sh
    set -e

    CONFIG_FILE="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"

    # Wait for KDE and display configuration to stabilize
    sleep 3

    # Function to create a secondary panel configuration
    create_secondary_panel() {
      local PANEL_ID=$1
      local SCREEN_NUM=$2

      echo "Creating secondary panel $PANEL_ID for screen $SCREEN_NUM"

      # Create minimal secondary panel with just task manager and activity switcher
      cat >> "$CONFIG_FILE" <<EOF

[Containments][$PANEL_ID]
activityId=
formfactor=2
immutability=1
lastScreen=$SCREEN_NUM
location=4
plugin=org.kde.panel
wallpaperplugin=org.kde.image

[Containments][$PANEL_ID][Applets][$((PANEL_ID + 1))]
immutability=1
plugin=org.kde.plasma.icontasks

[Containments][$PANEL_ID][Applets][$((PANEL_ID + 1))][Configuration][General]
launchers=
showOnlyCurrentActivity=false
showOnlyCurrentDesktop=false
showOnlyCurrentScreen=true

[Containments][$PANEL_ID][Applets][$((PANEL_ID + 2))]
immutability=1
plugin=org.kde.plasma.showActivityManager

[Containments][$PANEL_ID][General]
AppletOrder=$((PANEL_ID + 1));$((PANEL_ID + 2))
thickness=48
EOF
    }

    # Get number of connected monitors
    if command -v xrandr >/dev/null 2>&1; then
      MONITOR_COUNT=$(xrandr --query 2>/dev/null | grep " connected" | wc -l)
      echo "Detected $MONITOR_COUNT monitors"

      if [ "$MONITOR_COUNT" -gt 1 ] && [ -f "$CONFIG_FILE" ]; then
        # Ensure primary panel (410) is on screen 0
        ${pkgs.kdePackages.kconfig}/bin/kwriteconfig5 --file "$CONFIG_FILE" \
          --group Containments --group 410 --key lastScreen 0 || true

        # Check and create secondary panels for additional monitors
        for i in $(seq 1 $((MONITOR_COUNT - 1))); do
          PANEL_ID=$((500 + i * 10))

          # Check if this panel already exists
          if ! grep -q "\[Containments\]\[$PANEL_ID\]" "$CONFIG_FILE" 2>/dev/null; then
            create_secondary_panel "$PANEL_ID" "$i"
          else
            # Ensure existing panel is on correct screen
            ${pkgs.kdePackages.kconfig}/bin/kwriteconfig5 --file "$CONFIG_FILE" \
              --group Containments --group $PANEL_ID --key lastScreen $i || true
          fi
        done

        # Restart plasmashell to apply changes
        if pgrep -x plasmashell >/dev/null; then
          kquitapp6 plasmashell 2>/dev/null || kquitapp5 plasmashell 2>/dev/null || true
          sleep 1
          plasmashell --replace >/dev/null 2>&1 &
        fi
      fi
    fi
  '';

in
{
  config = lib.mkIf (kdeEnabled && rdpEnabled) {
    # Add panel manager script to system
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "kde-setup-multi-panels" ''
        ${panelManagerScript}
      '')
    ];

    # Configure KDE panel defaults declaratively
    environment.etc."xdg/plasma-workspace/env/01-panel-multi.sh" = {
      text = ''
        #!/bin/sh
        # Setup multi-monitor panels
        export PLASMA_PANEL_PRIMARY_SCREEN=0
        export PLASMA_MULTI_PANEL=1
      '';
      mode = "0755";
    };

    # Configure KDE defaults for panel behavior
    environment.etc."xdg/plasmashellrc".text = ''
      [PlasmaViews][Panel]
      alignment=132
      floating=0
      panelLengthMode=0
      thickness=56

      [PlasmaViews][Panel][Defaults]
      lastScreen=0
      showOnAllScreens=false

      [Updates]
      performed=/usr/share/plasma/shells/org.kde.plasma.desktop/contents/updates/containmentactions_middlebutton.js,/usr/share/plasma/shells/org.kde.plasma.desktop/contents/updates/digitalclock_rename_timezonedisplay_key.js,/usr/share/plasma/shells/org.kde.plasma.desktop/contents/updates/folderview_fix_recursive_screenmapping.js,/usr/share/plasma/shells/org.kde.plasma.desktop/contents/updates/keyboardlayout_migrateiconsetting.js,/usr/share/plasma/shells/org.kde.plasma.desktop/contents/updates/keyboardlayout_remove_shortcut.js,/usr/share/plasma/shells/org.kde.plasma.desktop/contents/updates/klipper_clear_config.js,/usr/share/plasma/shells/org.kde.plasma.desktop/contents/updates/maintain_existing_desktop_icon_sizes.js,/usr/share/plasma/shells/org.kde.plasma.desktop/contents/updates/mediaframe_migrate_useBackground_setting.js,/usr/share/plasma/shells/org.kde.plasma.desktop/contents/updates/migrate_font_weights.js,/usr/share/plasma/shells/org.kde.plasma.desktop/contents/updates/move_desktop_contents_to_subcontainment.js,/usr/share/plasma/shells/org.kde.plasma.desktop/contents/updates/no_middle_click_paste_on_panels.js,/usr/share/plasma/shells/org.kde.plasma.desktop/contents/updates/systemloadviewer_systemmonitor.js,/usr/share/plasma/shells/org.kde.plasma.desktop/contents/updates/unlock_widgets.js
    '';

    # Session commands to setup panels
    services.xserver.displayManager.sessionCommands = lib.mkAfter ''
      # Setup multi-monitor panels for RDP sessions
      if [ -n "$XRDP_SESSION" ] || [ -n "$RDP_SESSION" ]; then
        (
          ${panelManagerScript}
        ) &
      fi
    '';

    # Systemd user service to manage multi-monitor panels
    systemd.user.services.kde-multi-panel = {
      description = "Configure KDE panels for multiple monitors";
      wantedBy = [ "plasma-workspace.target" ];
      after = [ "plasma-workspace.target" ];

      script = ''
        ${panelManagerScript}
      '';

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
  };
}
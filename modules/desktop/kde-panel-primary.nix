# KDE Panel Primary Display Configuration
# Ensures primary taskbar always shows regardless of monitor configuration
{ config, lib, pkgs, ... }:

let
  kdeEnabled = config.services.desktopManager.plasma6.enable or false;
  rdpEnabled = config.services.xrdp.enable or false;

  # Declarative panel configuration for primary display
  panelConfig = ''
    [Containments][410]
    activityId=
    formfactor=2
    immutability=1
    lastScreen=0
    location=4
    plugin=org.kde.panel
    wallpaperplugin=org.kde.image

    [Containments][410][General]
    AppletOrder=411;412;437;436;438;413;414;427;428
    thickness=56

    [Containments][410][Applets][412][Configuration][General]
    showOnlyCurrentScreen=false
    showOnlyCurrentActivity=false
    showOnlyCurrentDesktop=false
  '';

in
{
  config = lib.mkIf (kdeEnabled && rdpEnabled) {
    # Configure KDE panel defaults declaratively
    environment.etc."xdg/plasma-workspace/env/01-panel-primary.sh" = {
      text = ''
        #!/bin/sh
        # Ensure KDE panel is configured for primary display
        export PLASMA_PANEL_PRIMARY_SCREEN=0
      '';
      mode = "0755";
    };

    # Default panel layout configuration
    environment.etc."xdg/plasma-org.kde.plasma.desktop-appletsrc.default" = {
      text = panelConfig;
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

    # KDE Configuration through kwriteconfig
    services.xserver.displayManager.sessionCommands = lib.mkAfter ''
      # Set panel to primary screen declaratively
      if [ -n "$XRDP_SESSION" ] || [ -n "$RDP_SESSION" ]; then
        # Configure panel for RDP sessions
        kwriteconfig5 --file plasma-org.kde.plasma.desktop-appletsrc --group Containments --group 410 --key lastScreen 0 || true
        kwriteconfig5 --file plasma-org.kde.plasma.desktop-appletsrc --group Containments --group 410 --group Applets --group 412 --group Configuration --group General --key showOnlyCurrentScreen false || true

        # Ensure panel is visible
        kwriteconfig5 --file plasmashellrc --group PlasmaViews --group Panel --key lastScreen 0 || true
      fi
    '';

    # Systemd user service to apply panel configuration
    systemd.user.services.kde-panel-primary = {
      description = "Configure KDE panel for primary display";
      wantedBy = [ "plasma-workspace.target" ];
      after = [ "plasma-workspace.target" ];

      script = ''
        # Ensure panel configuration is applied
        CONFIG_FILE="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"

        # Wait for KDE to initialize
        sleep 2

        # Apply primary screen configuration
        ${pkgs.kdePackages.kconfig}/bin/kwriteconfig5 --file "$CONFIG_FILE" \
          --group Containments --group 410 --key lastScreen 0

        ${pkgs.kdePackages.kconfig}/bin/kwriteconfig5 --file "$CONFIG_FILE" \
          --group Containments --group 410 --group Applets --group 412 \
          --group Configuration --group General --key showOnlyCurrentScreen false
      '';

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };
  };
}
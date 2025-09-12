{ config, lib, pkgs, ... }:

let
  rdpEnabled = (config.services.xrdp.enable or false);
in
{
  config = lib.mkIf rdpEnabled {
    # Comfortable default DPI for remote sessions
    services.xserver.dpi = lib.mkDefault 180;

    environment.systemPackages = with pkgs; [ xorg.xrandr ];

    # Avoid Qt double scaling; let Plasma manage scaling
    services.xserver.displayManager.sessionCommands = lib.mkAfter ''
      export QT_AUTO_SCREEN_SCALE_FACTOR=0
      export QT_ENABLE_HIGHDPI_SCALING=0
      export PLASMA_USE_QT_SCALING=1

      # GTK apps: integer scale only
      export GDK_SCALE=2
      unset GDK_DPI_SCALE

      # Larger cursor for remote sessions
      export XCURSOR_SIZE=48

      # Align font DPI and set per-output scale for XRDP virtual display
      kwriteconfig5 --file kcmfonts --group General --key forceFontDPI 180 || true
      kwriteconfig5 --file kdeglobals --group KScreen --key ScreenScaleFactors "XORGXRDP0=2;" || true
    '';
  };
}

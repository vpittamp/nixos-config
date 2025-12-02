# Desktop entries for Kubernetes applications
# These entries allow k9s and headlamp to appear in KDE menu across all activities
# Feature 106: Portable icon paths via assetsPackage
{ config, pkgs, lib, assetsPackage, ... }:

{
  # Desktop entry for k9s (Kubernetes terminal UI)
  xdg.desktopEntries.k9s = {
    name = "K9s";
    comment = "Kubernetes CLI to manage your clusters in style";
    exec = "${pkgs.kdePackages.konsole}/bin/konsole --qwindowtitle K9s -e ${pkgs.k9s}/bin/k9s";
    icon = "${assetsPackage}/icons/k9s.png";  # Feature 106: Portable icon path
    terminal = false;  # We're launching konsole explicitly
    type = "Application";
    categories = [ "Development" "System" "Utility" ];
  };

  # Desktop entry for Headlamp (Kubernetes web UI)
  # Note: Headlamp package should be added to system packages
  xdg.desktopEntries.headlamp = lib.mkIf (pkgs.stdenv.hostPlatform.isx86_64) {
    name = "Headlamp";
    comment = "Kubernetes web UI dashboard";
    exec = "headlamp --disable-gpu";
    icon = "headlamp";
    terminal = false;
    type = "Application";
    categories = [ "Development" "System" ];
  };
}

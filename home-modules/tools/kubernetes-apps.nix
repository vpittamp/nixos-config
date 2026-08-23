# Desktop entries for Kubernetes applications
# This entry allows k9s to appear in the application menu across all activities
# Feature 106: Portable icon paths via assetsPackage
{ config, pkgs, lib, assetsPackage, ... }:

{
  # Desktop entry for k9s (Kubernetes terminal UI)
  xdg.desktopEntries.k9s = {
    name = "K9s";
    comment = "Kubernetes CLI to manage your clusters in style";
    # ghostty rather than konsole: konsole was pulled into the closure solely by this
    # desktop entry (~187 MiB, plus a KDE frameworks tail). ghostty is the session terminal.
    exec = "${pkgs.ghostty}/bin/ghostty --title=K9s -e ${pkgs.k9s}/bin/k9s";
    icon = "${assetsPackage}/icons/k9s.png";  # Feature 106: Portable icon path
    terminal = false;  # We're launching the terminal explicitly
    type = "Application";
    categories = [ "Development" "System" "Utility" ];
  };

  # Headlamp desktop entry removed 2026-08-23 (slimming); the package was dropped
  # from modules/services/development.nix.
}

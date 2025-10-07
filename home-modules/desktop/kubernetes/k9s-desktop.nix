{ config, lib, pkgs, ... }:

# K9s Desktop Entry
#
# This module creates a standalone desktop entry for k9s with:
# - Unique desktop file that KDE Wayland can track separately
# - Custom icon for visual distinction
# - Dedicated window rule for activity assignment
#
# K9s will appear as its own application in the taskbar instead of
# grouping with regular Konsole windows.
#
# Note: On Wayland, the window grouping is determined by the desktop file
# name and StartupWMClass. We use "k9s" as the identifier to match the
# window rule in browser-window-rules.nix.

let
  # Create a wrapper script that launches k9s in Konsole with proper title
  k9sLauncher = pkgs.writeScriptBin "k9s-launcher" ''
    #!/usr/bin/env bash
    exec ${pkgs.kdePackages.konsole}/bin/konsole --separate -p tabtitle="K9s" -e ${pkgs.k9s}/bin/k9s
  '';
in
{
  home.packages = [ k9sLauncher ];

  home.file.".local/share/applications/k9s.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=K9s
    GenericName=Kubernetes CLI Manager
    Comment=Kubernetes CLI to manage your clusters in style
    Exec=${k9sLauncher}/bin/k9s-launcher
    Icon=kubernetes
    Terminal=false
    Categories=System;Monitor;Development;
    Keywords=kubernetes;k8s;cluster;pods;containers;
    StartupWMClass=k9s
    X-KDE-SubstituteUID=false
  '';

  # Rebuild KDE application cache when desktop files change
  home.activation.rebuildKdeCacheK9s = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if command -v kbuildsycoca6 >/dev/null 2>&1; then
      $DRY_RUN_CMD kbuildsycoca6 --noincremental 2>/dev/null || true
    elif command -v kbuildsycoca5 >/dev/null 2>&1; then
      $DRY_RUN_CMD kbuildsycoca5 --noincremental 2>/dev/null || true
    fi
  '';
}

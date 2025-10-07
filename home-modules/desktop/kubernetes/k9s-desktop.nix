{ config, lib, pkgs, ... }:

# K9s Desktop Entry
#
# This module creates a standalone desktop entry for k9s with:
# - Unique WM class (k9s-terminal) for taskbar grouping
# - Custom icon for visual distinction
# - Dedicated window rule for activity assignment
#
# K9s will appear as its own application in the taskbar instead of
# grouping with regular Konsole windows.

{
  home.file.".local/share/applications/k9s.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=K9s
    GenericName=Kubernetes CLI Manager
    Comment=Kubernetes CLI to manage your clusters in style
    Exec=${pkgs.kdePackages.konsole}/bin/konsole --class k9s-terminal --profile Shell -e ${pkgs.k9s}/bin/k9s
    Icon=kubernetes
    Terminal=false
    Categories=System;Monitor;Development;
    Keywords=kubernetes;k8s;cluster;pods;containers;
    StartupWMClass=k9s-terminal
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

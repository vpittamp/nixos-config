{ ... }:
{
  imports = [
    ./home-modules/profiles/base-home.nix
    # Plasma-home disabled during i3wm migration (Feature 009)
    # Re-enable if switching back to KDE Plasma
    # ./home-modules/profiles/plasma-home.nix
    ./home-modules/desktop/i3.nix  # i3 window manager configuration with keybindings
    ./home-modules/desktop/i3wsr.nix  # Dynamic workspace naming for i3wm (Feature 009)
    # ./home-modules/desktop/i3-projects.nix  # REMOVED: Feature 010 (OLD STATIC SYSTEM)
    # ./home-modules/desktop/i3-project-manager.nix  # REMOVED: Replaced by i3pm (Feature 019)
    ./home-modules/desktop/i3-project-daemon.nix   # Feature 015: Event-driven daemon
    # ./home-modules/tools/i3-project-manager.nix  # REMOVED: Replaced by i3pm Deno (Feature 027)
    ./home-modules/tools/i3pm-deno.nix             # Feature 027: i3pm Deno CLI rewrite (MVP)
    ./home-modules/tools/i3pm-diagnostic.nix       # Feature 039: Diagnostic CLI for troubleshooting
    ./home-modules/desktop/i3bar.nix  # Event-driven i3bar with instant project updates
    # ./home-modules/desktop/polybar.nix  # REMOVED: Replaced by event-driven i3bar
    # ./home-modules/desktop/i3blocks  # REMOVED: Switched to i3bar with event subscriptions
    ./home-modules/desktop/walker.nix        # Walker: Modern GTK4 application launcher
    ./home-modules/desktop/app-registry.nix  # Feature 034: Application registry with desktop files
    ./home-modules/desktop/i3-window-rules.nix  # Feature 035: Auto-generated window rules for global apps
    ./home-modules/tools/app-launcher.nix    # Feature 034: Launcher wrapper script and CLI
  ];

  home.username = "vpittamp";
  home.homeDirectory = "/home/vpittamp";

  # Feature 019: Enable i3pm CLI/TUI tool (unified project management) - DISABLED for Feature 027
  # programs.i3pm.enable = true;  # Old Python version - replaced by Deno rewrite

  # Feature 015: i3 project event listener daemon
  # NOTE: Disabled in favor of system service (Feature 037 - cross-namespace /proc access)
  # System service configured in configurations/hetzner.nix: services.i3ProjectDaemon.enable
  services.i3ProjectEventListener = {
    enable = false;  # Disabled - using system service instead
  };

  # Auto-clean home-manager backup conflicts before activation
  home.activation.cleanBackupConflicts = ''
    echo "Cleaning home-manager backup conflicts..."
    # Only clean specific files that home-manager manages
    # Note: mimeapps.list removed - now using associations.added to merge instead of overwrite
    for file in \
      .codex/config.toml \
      .mozilla/firefox/default/search.json.mozlz4 \
      .config/plasma-org.kde.plasma.desktop-appletsrc \
      .config/mimeapps.list; do
      if [ -f "$HOME/$file.backup" ]; then
        echo "Removing conflict: $HOME/$file.backup"
        rm -f "$HOME/$file.backup"
      fi
      if [ -f "$HOME/$file.hm-backup" ]; then
        echo "Removing old conflict: $HOME/$file.hm-backup"
        rm -f "$HOME/$file.hm-backup"
      fi
      if [ -f "$HOME/$file.old" ]; then
        echo "Removing old file: $HOME/$file.old"
        rm -f "$HOME/$file.old"
      fi
    done
  '';
}

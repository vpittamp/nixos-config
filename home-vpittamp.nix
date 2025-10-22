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
    ./home-modules/tools/i3-project-manager.nix    # Feature 019: i3pm CLI/TUI tool (unified solution)
    ./home-modules/tools/i3pm-deno.nix             # Feature 027: i3pm Deno CLI rewrite (MVP)
    ./home-modules/desktop/polybar.nix  # Re-enabled: Better centering support than i3bar
    # ./home-modules/desktop/i3blocks  # REMOVED: Switched back to polybar for center modules
  ];

  home.username = "vpittamp";
  home.homeDirectory = "/home/vpittamp";

  # Feature 019: Enable i3pm CLI/TUI tool (unified project management)
  programs.i3pm.enable = true;

  # Feature 015: Enable i3 project event listener daemon
  services.i3ProjectEventListener = {
    enable = true;  # Enabled for testing (Feature 015)
    logLevel = "DEBUG";  # Debug logging for initial testing
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

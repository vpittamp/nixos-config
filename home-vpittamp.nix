{ ... }:
{
  imports = [
    ./home-modules/profiles/base-home.nix
    # Plasma-home disabled during i3wm migration (Feature 009)
    # Re-enable if switching back to KDE Plasma
    # ./home-modules/profiles/plasma-home.nix

    # Sway (Wayland) for M1 MacBook Pro (Feature 045)
    ./home-modules/desktop/sway.nix  # Sway window manager configuration
    ./home-modules/desktop/swaybar.nix  # Swaybar with event-driven status
    ./home-modules/desktop/eww-workspace-bar.nix  # SVG workspace bar with icons
    ./home-modules/desktop/sway-config-manager.nix  # Feature 047: Dynamic configuration management
    ./home-modules/profiles/declarative-cleanup.nix  # Automatic XDG cleanup

    # i3 (X11) - disabled on M1, using Sway instead
    # ./home-modules/desktop/i3.nix  # i3 window manager configuration with keybindings
    # ./home-modules/desktop/i3wsr.nix  # Dynamic workspace naming for i3wm (Feature 009)
    # ./home-modules/desktop/i3bar.nix  # Event-driven i3bar with instant project updates

    # Project management (works with both i3 and Sway)
    # Feature 015: Event-driven daemon - now managed by system service (Feature 037)
    ./home-modules/tools/i3pm-deno.nix             # Feature 027: i3pm Deno CLI rewrite (MVP)
    ./home-modules/tools/i3pm-diagnostic.nix       # Feature 039: Diagnostic CLI for troubleshooting

    # Application launcher and registry (Wayland-compatible)
    ./home-modules/desktop/walker.nix        # Walker: Modern GTK4 application launcher
    ./home-modules/desktop/app-registry.nix  # Feature 034: Application registry with desktop files
    ./home-modules/tools/app-launcher.nix    # Feature 034: Launcher wrapper script and CLI
  ];

  home.username = "vpittamp";
  home.homeDirectory = "/home/vpittamp";

  # Feature 019: Enable i3pm CLI/TUI tool (unified project management) - DISABLED for Feature 027
  # programs.i3pm.enable = true;  # Old Python version - replaced by Deno rewrite

  # Feature 015: i3 project event listener daemon
  # Managed by system service (Feature 037) - see configurations/m1.nix: services.i3ProjectDaemon.enable

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

  # Feature 047: Sway Dynamic Configuration Management
  programs.sway-config-manager = {
    enable = true;
    enableFileWatcher = true;  # Auto-reload on file changes
    debounceMs = 500;  # Wait 500ms after last change before reloading
  };

  programs.eww-workspace-bar.enable = true;
}

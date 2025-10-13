{ ... }:
{
  imports = [
    # Use only darwin-home.nix, which has curated cross-platform imports
    # base-home.nix includes Linux-specific modules (firefox, gitkraken, kubernetes-apps)
    ./home-modules/profiles/darwin-home.nix
    # Note: plasma-home.nix is excluded - KDE Plasma is Linux-only
  ];

  home.username = "vpittamp";
  home.homeDirectory = "/Users/vpittamp";

  # Auto-clean home-manager backup conflicts before activation
  home.activation.cleanBackupConflicts = ''
    echo "Cleaning home-manager backup conflicts..."
    # Clean specific files that home-manager manages
    for file in \
      .codex/config.toml \
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

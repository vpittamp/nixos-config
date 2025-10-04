{ ... }:
{
  imports = [
    ./home-modules/profiles/base-home.nix
    ./home-modules/profiles/plasma-home.nix
  ];

  home.username = "vpittamp";
  home.homeDirectory = "/home/vpittamp";

  # Auto-clean home-manager backup conflicts before activation
  home.activation.cleanBackupConflicts = ''
    echo "Cleaning home-manager backup conflicts..."
    # Only clean specific files that home-manager manages
    for file in .codex/config.toml .mozilla/firefox/default/search.json.mozlz4 .config/plasma-org.kde.plasma.desktop-appletsrc .config/mimeapps.list; do
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

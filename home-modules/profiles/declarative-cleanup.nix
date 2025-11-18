# Declarative Cleanup Module
# Automatically removes backup files and stale resources before home-manager activation
# This ensures a clean state and prevents "file exists" conflicts
{ pkgs, ... }:

{
  home.activation.cleanupBeforeActivation = {
    # Run before home-manager checks file targets
    after = [];
    before = [ "checkLinkTargets" "writeBoundary" ];

    data = ''
      echo "=== Running declarative cleanup ==="

      # 1. Remove home-manager backup files (.backup, .backup-before-home-manager)
      echo "Cleaning up home-manager backup files..."
      ${pkgs.findutils}/bin/find $HOME/.config -name "*.backup" -type f -delete 2>/dev/null || true
      ${pkgs.findutils}/bin/find $HOME/.config -name "*.backup" -type d -exec rm -rf {} + 2>/dev/null || true
      ${pkgs.findutils}/bin/find $HOME/.config -name "*.backup-before-home-manager" -delete 2>/dev/null || true

      # 2. Remove stale runtime sockets
      echo "Cleaning up stale runtime sockets..."
      rm -f /run/user/$(id -u)/wayvncctl 2>/dev/null || true

      # 3. Clean up old .desktop backup files
      echo "Cleaning up old desktop file backups..."
      ${pkgs.findutils}/bin/find $HOME/.local/share/i3pm-applications -name "*.backup" -delete 2>/dev/null || true

      # 4. Clean up old systemd service backups
      echo "Cleaning up systemd service backups..."
      ${pkgs.findutils}/bin/find $HOME/.config/systemd/user -name "*.backup" -type f -delete 2>/dev/null || true

      # 5. Clean up temporary/stale lock files
      echo "Cleaning up stale lock files..."
      ${pkgs.findutils}/bin/find $HOME/.config -name "*.lock" -type f -mtime +7 -delete 2>/dev/null || true

      # 6. Remove lingering Codex permission backups that can block activation
      rm -f $HOME/.codex/config.toml.hm-bak 2>/dev/null || true
      rm -f $HOME/.codex/config.toml.backup 2>/dev/null || true
      rm -f $HOME/.codex/config.toml 2>/dev/null || true

      echo "=== Cleanup complete ==="
    '';
  };

  # Prevent home-manager from creating backups in the first place
  # Instead, use git for version control and this activation script for cleanup
  home.enableNixpkgsReleaseCheck = false;  # Suppress version mismatch warnings
}

# PWA Extensions Module - Installs extensions to all PWA profiles
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.pwa-extensions;

  # Script to copy extensions to PWA profiles
  extensionInstaller = pkgs.writeShellScriptBin "install-pwa-extensions" ''
    #!/usr/bin/env bash
    set -e

    echo "Installing extensions for PWA profiles..."

    # Find 1Password extension from main Firefox profile
    ONEPASS_EXT=""
    for profile_dir in ~/.mozilla/firefox/*.default*; do
      if [ -f "$profile_dir/extensions/{d634138d-c276-4fc8-924b-40a0ea21d284}.xpi" ]; then
        ONEPASS_EXT="$profile_dir/extensions/{d634138d-c276-4fc8-924b-40a0ea21d284}.xpi"
        break
      fi
    done

    if [ -z "$ONEPASS_EXT" ]; then
      echo "1Password extension not found in Firefox profiles. Please install it first."
      exit 1
    fi

    # Copy to all PWA profiles
    for profile_dir in ~/.local/share/firefoxpwa/profiles/*/; do
      if [ -d "$profile_dir" ]; then
        echo "Installing extensions to $profile_dir"
        mkdir -p "$profile_dir/extensions"
        cp -f "$ONEPASS_EXT" "$profile_dir/extensions/" 2>/dev/null || true

        # Also copy Plasma Browser Integration if available
        for firefox_profile in ~/.mozilla/firefox/*.default*; do
          if [ -f "$firefox_profile/extensions/plasma-browser-integration@kde.org.xpi" ]; then
            cp -f "$firefox_profile/extensions/plasma-browser-integration@kde.org.xpi" "$profile_dir/extensions/" 2>/dev/null || true
            break
          fi
        done
      fi
    done

    echo "Extension installation complete!"
  '';

in
{
  options.services.pwa-extensions = {
    enable = mkEnableOption "PWA extension auto-installation";

    autoInstall = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically install extensions to PWA profiles on activation";
    };
  };

  config = mkIf cfg.enable {
    # Add the installer script to system packages
    environment.systemPackages = [ extensionInstaller ];

    # Run installer on system activation
    system.activationScripts.pwa-extensions = mkIf cfg.autoInstall ''
      # Install extensions for the user
      if [ -n "''${SUDO_USER:-}" ]; then
        echo "Installing PWA extensions for user $SUDO_USER..."
        sudo -u "$SUDO_USER" ${extensionInstaller}/bin/install-pwa-extensions || true
      fi
    '';
  };
}
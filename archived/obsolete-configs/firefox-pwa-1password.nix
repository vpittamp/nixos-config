# Firefox PWA 1Password Integration
# Ensures 1Password extension works in PWAs
{ config, lib, pkgs, ... }:

with lib;

{
  # Configure firefoxpwa to enable extensions and provide helper script
  environment.systemPackages = with pkgs; [
    (firefoxpwa.overrideAttrs (oldAttrs: {
      postInstall = (oldAttrs.postInstall or "") + ''
        # Configure PWAs to allow extensions
        mkdir -p $out/share/firefoxpwa
        cat > $out/share/firefoxpwa/config.toml << EOF
        # Enable extensions in PWAs
        [runtime]
        enable_extensions = true
        enable_1password = true

        [extensions]
        # 1Password extension will be auto-installed
        force_install = [
          "onepassword@1password.com"
        ]
        EOF
      '';
    }))
    (writeShellScriptBin "pwa-enable-1password" ''
      # Script to enable 1Password in existing PWAs
      #!/usr/bin/env bash
      echo "Enabling 1Password for all PWAs..."

      TARGET=""
      while [ $# -gt 0 ]; do
        case "$1" in
          --profile)
            TARGET="$2"
            shift 2
            ;;
          -h|--help)
            cat <<'EOF'
Usage: pwa-enable-1password [--profile ULID]

Install/configure the 1Password extension for all PWAs or a single profile.
EOF
            exit 0
            ;;
          *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
        esac
      done

      if [ -n "$TARGET" ]; then
        set -- "$HOME/.local/share/firefoxpwa/profiles/$TARGET/"
      else
        set -- "$HOME/.local/share/firefoxpwa/profiles"/*/
      fi

      # Find all PWA profiles
      for profile in "$@"; do
        if [ -d "$profile" ]; then
          profile_name=$(basename "$profile")
          echo "  Updating profile: $profile_name"

          # Create extensions directory
          mkdir -p "$profile/extensions"

          # Download and install 1Password extension
          if [ ! -f "$profile/extensions/onepassword@1password.com.xpi" ]; then
            echo "    Downloading 1Password extension..."
            curl -sSL "https://addons.mozilla.org/firefox/downloads/latest/1password-x-password-manager/latest.xpi" \
              -o "$profile/extensions/onepassword@1password.com.xpi"
          else
            echo "    1Password extension already present"
          fi

          # Install extension into profile if not already registered
          if [ -f "$profile/extensions.json" ] && ${pkgs.jq}/bin/jq -e 'any(.addons[]?; .id == "onepassword@1password.com")' "$profile/extensions.json" >/dev/null 2>&1; then
            echo "    1Password extension already installed"
          else
            echo "    Installing 1Password extension into profile"
            timeout 30s MOZ_HEADLESS=1 MOZ_FORCE_DISABLE_E10S=1 ${pkgs.firefox}/bin/firefox \
              --headless --profile "$profile" --install-addon "$profile/extensions/onepassword@1password.com.xpi" \
              >/dev/null 2>&1 || true
            rm -f "$profile/.parentlock"
          fi

          # Update prefs.js for the profile
          if [ -f "$profile/prefs.js" ]; then
            # Backup existing prefs
            cp "$profile/prefs.js" "$profile/prefs.js.backup"

            # Add 1Password preferences if not already present
            if ! grep -q "extensions.1password.enabled" "$profile/prefs.js"; then
              cat >> "$profile/prefs.js" << 'PREFS'
// 1Password integration
user_pref("extensions.1password.enabled", true);
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);
user_pref("extensions.allowPrivateBrowsingByDefault", true);
user_pref("extensions.1password.native-messaging", true);
user_pref("extensions.webextensions.ExtensionStorageIDB.migrated.onepassword@1password.com", true);
PREFS
              echo "    Added 1Password preferences"
            fi
          fi

          # Set up native messaging
          mkdir -p "$profile/.mozilla/native-messaging-hosts"
          for host in ${pkgs._1password-gui}/share/1password/mozilla/native-messaging-hosts/*.json; do
            target="$profile/.mozilla/native-messaging-hosts/$(basename "$host")"
            ln -sf "$host" "$target"
          done
          echo "    Configured native messaging"
        fi
      done

      echo ""
      echo "1Password enabled for selected PWAs!"
      echo "Restart the PWA to load the extension and toolbar pin."
    '')
  ];

  # User configuration for PWAs
  system.activationScripts.configurePWA1Password = ''
    # Ensure vpittamp user exists before configuring
    if id -u vpittamp >/dev/null 2>&1; then
      # Create firefoxpwa config directory
      mkdir -p /home/vpittamp/.config/firefoxpwa

      # Create runtime configuration for PWAs
      cat > /home/vpittamp/.config/firefoxpwa/runtime.json << 'EOF'
    {
      "extensions": {
        "enabled": true,
        "autoInstall": [
          {
            "id": "onepassword@1password.com",
            "url": "https://addons.mozilla.org/firefox/downloads/latest/1password-x-password-manager/latest.xpi",
            "pinToToolbar": true
          }
        ]
      },
      "preferences": {
        "signon.rememberSignons": false,
        "signon.autofillForms": false,
        "extensions.allowPrivateBrowsingByDefault": true,
        "extensions.1password.native-messaging": true
      }
    }
    EOF

      # Set ownership
      chown -R vpittamp:users /home/vpittamp/.config/firefoxpwa

      # Link native messaging hosts for PWA profiles
      for profile_dir in /home/vpittamp/.local/share/firefoxpwa/profiles/*/; do
        if [ -d "$profile_dir" ]; then
          mkdir -p "$profile_dir/.mozilla/native-messaging-hosts"
          ln -sf ${pkgs._1password-gui}/share/1password/mozilla/native-messaging-hosts/*.json \
            "$profile_dir/.mozilla/native-messaging-hosts/" 2>/dev/null || true
        fi
      done
    fi
  '';
}

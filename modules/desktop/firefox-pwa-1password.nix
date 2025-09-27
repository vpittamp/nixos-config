# Firefox PWA 1Password Integration
# Ensures 1Password extension works in PWAs
{ config, lib, pkgs, ... }:

with lib;

{
  # Native messaging host configuration for PWAs
  environment.etc = {
    # PWA native messaging host for 1Password
    "firefox/native-messaging-hosts/com.1password.1password.json" = {
      text = builtins.toJSON {
        name = "com.1password.1password";
        description = "1Password Native Messaging Host";
        type = "stdio";
        allowed_extensions = [
          "onepassword@1password.com"
          "{d634138d-c276-4fc8-924b-40a0ea21d284}"  # 1Password extension ID
        ];
        path = "${pkgs._1password-gui}/share/1password/1Password-BrowserSupport";
      };
      mode = "0644";
    };
  };

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
    # Script to enable 1Password in existing PWAs
    (writeShellScriptBin "pwa-enable-1password" ''
      #!/usr/bin/env bash
      echo "Enabling 1Password for all PWAs..."

      # Find all PWA profiles
      for profile in ~/.local/share/firefoxpwa/profiles/*/; do
        if [ -d "$profile" ]; then
          profile_name=$(basename "$profile")
          echo "  Updating profile: $profile_name"

          # Create extensions directory
          mkdir -p "$profile/extensions"

          # Download and install 1Password extension
          echo "    Downloading 1Password extension..."
          curl -sL "https://addons.mozilla.org/firefox/downloads/latest/1password-x-password-manager/latest.xpi" \
            -o "$profile/extensions/onepassword@1password.com.xpi"

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
          ln -sf ${pkgs._1password-gui}/share/1password/mozilla/native-messaging-hosts/*.json \
            "$profile/.mozilla/native-messaging-hosts/" 2>/dev/null || true
          echo "    Configured native messaging"
        fi
      done

      echo ""
      echo "1Password enabled for all PWAs!"
      echo "Note: You need to restart each PWA for changes to take effect."
      echo ""
      echo "After restarting a PWA:"
      echo "1. Click the puzzle piece icon in the toolbar"
      echo "2. Pin 1Password to the toolbar"
      echo "3. Sign in to 1Password"
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
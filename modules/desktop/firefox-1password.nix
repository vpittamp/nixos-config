# Consolidated Firefox with 1Password Integration
# Configures Firefox with 1Password extension and optional PWA support
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.firefox-1password;
in
{
  options.programs.firefox-1password = {
    enable = mkEnableOption "Firefox with 1Password integration";

    enablePWA = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Enable Progressive Web App (PWA) support with 1Password integration.
        This installs firefoxpwa and configures PWAs to use the 1Password extension.
      '';
    };
  };

  config = mkIf cfg.enable (mkMerge [
    # ========== BASE FIREFOX + 1PASSWORD CONFIGURATION ==========
    {
      programs.firefox = {
        enable = true;

        # Global policies for all Firefox profiles
        policies = {
          # Extensions configuration
          ExtensionSettings = {
            # 1Password extension - force install and pin
            "{d634138d-c276-4fc8-924b-40a0ea21d284}" = {
              installation_mode = "force_installed";
              install_url = "https://addons.mozilla.org/firefox/downloads/latest/1password-x-password-manager/latest.xpi";
              default_area = "navbar";  # Pin to toolbar by default
              allowed_in_private_browsing = true;  # Enable in private browsing
            };
          };

          # Extension management
          Extensions = {
            Install = [
              "https://addons.mozilla.org/firefox/downloads/latest/1password-x-password-manager/latest.xpi"
              "https://addons.mozilla.org/firefox/downloads/latest/pwas-for-firefox/latest.xpi"
              "https://addons.mozilla.org/firefox/downloads/latest/gitingest/latest.xpi"
            ];
          };

          # Configure Firefox preferences
          Preferences = {
            # Disable Firefox password manager
            "signon.rememberSignons" = false;
            "signon.autofillForms" = false;
            "signon.generation.enabled" = false;
            "signon.management.page.breach-alerts.enabled" = false;
            "signon.management.page.breachAlertUrl" = "";

            # Enable extensions in private browsing by default
            "extensions.allowPrivateBrowsingByDefault" = true;

            # Enable native messaging for 1Password
            "extensions.1password.native-messaging" = true;

            # Disable Firefox's built-in password suggestions
            "browser.contentblocking.report.lockwise.enabled" = false;

            # Enable autofill
            "dom.forms.autocomplete.formautofill" = true;

            # Keep extensions enabled in private windows
            "extensions.privatebrowsing.notification" = false;
          };

          # Disable Firefox password manager completely
          PasswordManagerEnabled = false;

          # Enable autofill for 1Password
          AutofillCreditCardEnabled = true;
          AutofillAddressEnabled = true;

          # Private browsing settings
          EnableTrackingProtection = {
            Value = true;
            Locked = false;
            Cryptomining = true;
            Fingerprinting = true;
          };

          PopupBlocking = {
            Allow = [
              "https://my.1password.com"
              "https://*.my.1password.com"
            ];
          };
        };
      };

      # Create Firefox native messaging manifests for 1Password
      environment.etc = {
        # Firefox native messaging host for 1Password
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

        # Alternative Firefox location
        "mozilla/native-messaging-hosts/com.1password.1password.json" = {
          text = builtins.toJSON {
            name = "com.1password.1password";
            description = "1Password Native Messaging Host";
            type = "stdio";
            allowed_extensions = [
              "onepassword@1password.com"
              "{d634138d-c276-4fc8-924b-40a0ea21d284}"
            ];
            path = "${pkgs._1password-gui}/share/1password/1Password-BrowserSupport";
          };
          mode = "0644";
        };
      };

      # User-specific Firefox configuration
      system.activationScripts.firefoxUserConfig = ''
        # Create user Firefox directory structure
        mkdir -p /home/vpittamp/.mozilla/native-messaging-hosts

        # Link 1Password native messaging host for user
        ln -sf ${pkgs._1password-gui}/share/1password/mozilla/native-messaging-hosts/*.json \
          /home/vpittamp/.mozilla/native-messaging-hosts/ 2>/dev/null || true

        # Set proper permissions
        chown -R vpittamp:users /home/vpittamp/.mozilla
      '';

      # Environment variables for Firefox
      environment.sessionVariables = {
        # Enable Wayland support
        MOZ_ENABLE_WAYLAND = "1";

        # Enable 1Password integration
        MOZ_ALLOW_ADDON_SIDELOAD = "1";
      };
    }

    # ========== PWA CONFIGURATION ==========
    # Enabled when PWA support is requested
    (mkIf cfg.enablePWA {
      # Configure firefoxpwa to enable extensions
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
    })
  ]);
}

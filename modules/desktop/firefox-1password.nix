# Firefox with 1Password Integration
# Configures Firefox with 1Password extension pre-installed and configured
{ config, lib, pkgs, ... }:

{
  programs.firefox = {
    enable = true;

    # Package with native messaging support
    package = pkgs.firefox.override {
      nativeMessagingHosts = [
        pkgs._1password-gui  # Enable 1Password native messaging
      ];
    };

    # Global policies for all Firefox profiles
    policies = {
      # Extensions configuration
      ExtensionSettings = {
        # 1Password extension - force install and pin
        "onepassword@1password.com" = {
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
    };

    # Native messaging hosts for 1Password
    nativeMessagingHosts = [ pkgs._1password-gui ];
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
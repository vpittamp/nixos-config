# Chromium and Chromium-based Browsers with 1Password Integration
# Configures all Chromium-based browsers (including PWAs) with 1Password
{ config, lib, pkgs, ... }:

{
  # Chromium configuration
  programs.chromium = {
    enable = true;

    # Extension IDs
    extensions = [
      "aeblfdkhhhdcdjpifhhbdiojplfjncoa"  # 1Password extension
    ];

    # Extension policies
    extraOpts = {
      # Force install and configure 1Password extension
      ExtensionSettings = {
        "aeblfdkhhhdcdjpifhhbdiojplfjncoa" = {
          installation_mode = "force_installed";
          update_url = "https://clients2.google.com/service/update2/crx";
          toolbar_pin = "force_pinned";  # Pin to toolbar
        };
      };

      # Extension management settings
      ExtensionInstallAllowlist = [
        "aeblfdkhhhdcdjpifhhbdiojplfjncoa"
      ];

      # Allow extensions in incognito/private mode
      ExtensionInstallBlocklist = [];

      # Password manager settings
      PasswordManagerEnabled = false;  # Disable Chrome's password manager
      PasswordProtectionLoginURLs = [];
      PasswordProtectionChangePasswordURL = "";

      # Autofill settings
      AutofillEnabled = true;
      AutofillCreditCardEnabled = false;  # Let 1Password handle this
      AutofillAddressEnabled = false;  # Let 1Password handle this

      # Enable native messaging for 1Password
      NativeMessagingAllowlist = [
        "com.1password.1password"
        "com.1password.browser_support"
      ];

      # Privacy and security
      BrowserSignin = 0;  # Disable browser sign-in
      SyncDisabled = false;  # Allow sync if user wants

      # Private browsing settings
      IncognitoModeAvailability = 0;  # Allow incognito mode

      # Allow extensions in incognito
      RunAllFlashInAllowMode = false;
      DefaultPluginsSetting = 2;  # Block plugins by default
    };
  };

  # Create native messaging hosts for all Chromium-based browsers
  environment.etc = let
    nativeMessagingHost = name: {
      text = builtins.toJSON {
        name = name;
        description = "1Password Native Messaging Host";
        type = "stdio";
        allowed_origins = [
          "chrome-extension://aeblfdkhhhdcdjpifhhbdiojplfjncoa/"
          "chrome-extension://khgocmkkpikpnmmkgmdnfckapcdkgfaf/"  # 1Password beta
        ];
        path = "${pkgs._1password-gui}/share/1password/1Password-BrowserSupport";
      };
      mode = "0644";
    };
  in {
    # Chromium/Chrome native messaging
    "chromium/native-messaging-hosts/com.1password.1password.json" = nativeMessagingHost "com.1password.1password";
    "chromium/native-messaging-hosts/com.1password.browser_support.json" = nativeMessagingHost "com.1password.browser_support";

    # Google Chrome paths
    "opt/chrome/native-messaging-hosts/com.1password.1password.json" = nativeMessagingHost "com.1password.1password";
    "opt/chrome/native-messaging-hosts/com.1password.browser_support.json" = nativeMessagingHost "com.1password.browser_support";

    # Brave browser paths
    "opt/brave.com/brave/native-messaging-hosts/com.1password.1password.json" = nativeMessagingHost "com.1password.1password";
    "opt/brave.com/brave/native-messaging-hosts/com.1password.browser_support.json" = nativeMessagingHost "com.1password.browser_support";

    # Edge browser paths
    "opt/microsoft/msedge/native-messaging-hosts/com.1password.1password.json" = nativeMessagingHost "com.1password.1password";
    "opt/microsoft/msedge/native-messaging-hosts/com.1password.browser_support.json" = nativeMessagingHost "com.1password.browser_support";
  };

  # User-specific configuration for Chromium browsers
  system.activationScripts.chromiumUserConfig = ''
    # Create config directories for various Chromium browsers
    for browser in chromium google-chrome google-chrome-stable brave brave-browser microsoft-edge; do
      CONFIG_DIR="/home/vpittamp/.config/$browser/NativeMessagingHosts"
      mkdir -p "$CONFIG_DIR"

      # Link native messaging hosts
      ln -sf ${pkgs._1password-gui}/share/1password/chrome/native-messaging-hosts/*.json \
        "$CONFIG_DIR/" 2>/dev/null || true
    done

    # Special handling for Chromium-based PWAs
    # PWAs use the same profile as the parent browser
    PWA_DIR="/home/vpittamp/.config/chromium/Default/Web Applications"
    if [ -d "$PWA_DIR" ]; then
      echo "PWAs will use Chromium's 1Password configuration"
    fi

    # Set proper permissions
    chown -R vpittamp:users /home/vpittamp/.config/chromium 2>/dev/null || true
    chown -R vpittamp:users /home/vpittamp/.config/google-chrome 2>/dev/null || true
    chown -R vpittamp:users /home/vpittamp/.config/brave 2>/dev/null || true
    chown -R vpittamp:users /home/vpittamp/.config/microsoft-edge 2>/dev/null || true
  '';

  # Environment variables for Chromium browsers
  environment.sessionVariables = {
    # Enable Wayland support for Chromium
    NIXOS_OZONE_WL = "1";

    # Force 1Password extension to be available
    CHROME_EXTRA_FLAGS = "--enable-features=ExtensionsToolbarMenu";
  };

  # Chromium wrapper script to ensure 1Password works
  environment.systemPackages = with pkgs; [
    (writeScriptBin "chromium-with-1password" ''
      #!${pkgs.bash}/bin/bash
      # Launch Chromium with 1Password support
      exec ${pkgs.chromium}/bin/chromium \
        --enable-features=ExtensionsToolbarMenu \
        --load-extension=${pkgs._1password-gui}/share/1password/chrome/extension \
        "$@"
    '')

    # PWA launcher with 1Password support
    (writeScriptBin "launch-pwa" ''
      #!${pkgs.bash}/bin/bash
      # Launch PWA with 1Password support
      # Usage: launch-pwa <app-id> [additional-args]

      APP_ID="$1"
      shift

      exec ${pkgs.chromium}/bin/chromium \
        --app-id="$APP_ID" \
        --enable-features=ExtensionsToolbarMenu \
        --load-extension=${pkgs._1password-gui}/share/1password/chrome/extension \
        "$@"
    '')
  ];
}
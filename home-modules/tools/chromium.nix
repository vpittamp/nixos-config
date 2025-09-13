{ config, pkgs, lib, ... }:

{
  # Chromium browser configuration with 1Password and other extensions
  programs.chromium = {
    enable = true;
    package = pkgs.chromium;
    
    # Extension IDs for manual installation
    # Note: Chromium extensions in Nix must be installed via policies
    # The ExtensionSettings policy below will auto-install these
    extensions = [
      # These IDs are referenced but actual installation happens via policy
      "aeblfdkhhhdcdjpifhhbdiojplfjncoa"  # 1Password
      "cjpalhdlnbpafiamejdnhcphjbkeiagm"  # uBlock Origin
      "eimadpbcbfnmbkopoojfekhnkhdbieeh"  # Dark Reader
      "dbepggeogbaibhgnhhndojpepiihcmeb"  # Vimium
      "pkehgijcmpdhfbdbbnkijodmdjhbjlgp"  # Privacy Badger
    ];
    
    # Command line arguments for better performance and privacy
    commandLineArgs = [
      # Display scaling for HiDPI/Retina displays
      "--force-device-scale-factor=1.75"  # 1.75x scaling for M1 Retina display
      "--high-dpi-support=1"
      
      # Enable hardware acceleration
      "--enable-features=VaapiVideoDecoder"
      "--use-gl=desktop"
      "--enable-gpu-rasterization"
      "--enable-zero-copy"
      
      # Wayland support (auto-detect)
      "--ozone-platform-hint=auto"
      
      # Enable native messaging for 1Password
      "--enable-native-messaging"
      
      # Enable password import features
      "--enable-features=PasswordImport"
      
      # Privacy enhancements
      "--disable-reading-from-canvas"
      "--disable-background-networking"
    ];
    
    # Enable spell checking
    dictionaries = [
      pkgs.hunspellDictsChromium.en_US
    ];
  };

  # Set Chromium as the default browser for all URL types
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = [ "chromium-browser.desktop" ];
      "x-scheme-handler/http" = [ "chromium-browser.desktop" ];
      "x-scheme-handler/https" = [ "chromium-browser.desktop" ];
      "x-scheme-handler/ftp" = [ "chromium-browser.desktop" ];
      "x-scheme-handler/chrome" = [ "chromium-browser.desktop" ];
      "x-scheme-handler/about" = [ "chromium-browser.desktop" ];
      "x-scheme-handler/unknown" = [ "chromium-browser.desktop" ];
      "application/x-extension-htm" = [ "chromium-browser.desktop" ];
      "application/x-extension-html" = [ "chromium-browser.desktop" ];
      "application/x-extension-shtml" = [ "chromium-browser.desktop" ];
      "application/xhtml+xml" = [ "chromium-browser.desktop" ];
      "application/x-extension-xhtml" = [ "chromium-browser.desktop" ];
      "application/x-extension-xht" = [ "chromium-browser.desktop" ];
      "application/pdf" = [ "chromium-browser.desktop" ];
    };
    associations.added = {
      "text/html" = [ "chromium-browser.desktop" ];
      "x-scheme-handler/http" = [ "chromium-browser.desktop" ];
      "x-scheme-handler/https" = [ "chromium-browser.desktop" ];
      "application/pdf" = [ "chromium-browser.desktop" ];
    };
  };

  # Create Chromium policies for enterprise configuration
  # This ensures 1Password extension is pinned and properly configured
  home.file.".config/chromium/policies/managed/1password-policy.json" = {
    text = builtins.toJSON {
      # Force install and pin extensions
      ExtensionSettings = {
        # 1Password - Password Manager
        "aeblfdkhhhdcdjpifhhbdiojplfjncoa" = {
          installation_mode = "force_installed";
          update_url = "https://clients2.google.com/service/update2/crx";
          toolbar_pin = "force_pinned";
        };
        # uBlock Origin
        "cjpalhdlnbpafiamejdnhcphjbkeiagm" = {
          installation_mode = "force_installed";
          update_url = "https://clients2.google.com/service/update2/crx";
        };
        # Dark Reader
        "eimadpbcbfnmbkopoojfekhnkhdbieeh" = {
          installation_mode = "force_installed";
          update_url = "https://clients2.google.com/service/update2/crx";
        };
        # Vimium
        "dbepggeogbaibhgnhhndojpepiihcmeb" = {
          installation_mode = "force_installed";
          update_url = "https://clients2.google.com/service/update2/crx";
        };
        # Privacy Badger
        "pkehgijcmpdhfbdbbnkijodmdjhbjlgp" = {
          installation_mode = "force_installed";
          update_url = "https://clients2.google.com/service/update2/crx";
        };
      };
      
      # Disable Chrome's built-in password manager to avoid conflicts
      PasswordManagerEnabled = false;
      
      # Enable native messaging for 1Password
      NativeMessagingAllowlist = [
        "com.1password.1password"
        "com.1password.browser_support"
      ];
      
      # Set homepage and startup behavior
      HomepageLocation = "chrome://newtab";
      RestoreOnStartup = 1;  # Restore last session
      
      # Privacy and security settings
      SafeBrowsingProtectionLevel = 2;  # Enhanced protection
      DefaultCookiesSetting = 1;  # Allow cookies
      DefaultGeolocationSetting = 3;  # Ask before accessing
      DefaultNotificationsSetting = 3;  # Ask before showing
      
      # Development settings
      DeveloperToolsAvailability = 1;  # Allow developer tools
    };
  };

  # Create native messaging host manifest for 1Password
  # This allows the browser extension to communicate with the desktop app
  home.file.".config/chromium/NativeMessagingHosts/com.1password.1password.json" = {
    text = builtins.toJSON {
      name = "com.1password.1password";
      description = "1Password Native Messaging Host";
      type = "stdio";
      allowed_origins = [
        "chrome-extension://aeblfdkhhhdcdjpifhhbdiojplfjncoa/"
      ];
      # Path to the 1Password browser support binary
      path = "${pkgs._1password-gui}/share/1password/op-browser-support";
    };
  };

  # Additional native messaging host for browser support
  home.file.".config/chromium/NativeMessagingHosts/com.1password.browser_support.json" = {
    text = builtins.toJSON {
      name = "com.1password.browser_support";
      description = "1Password Browser Support";
      type = "stdio";
      allowed_origins = [
        "chrome-extension://aeblfdkhhhdcdjpifhhbdiojplfjncoa/"
      ];
      path = "${pkgs._1password-gui}/share/1password/op-browser-support";
    };
  };

  # Configure 1Password browser integration settings
  home.file.".config/1Password/settings/browser-support.json" = {
    text = builtins.toJSON {
      "browser.autoFillShortcut" = {
        "enabled" = true;
        "shortcut" = "Ctrl+Shift+L";
      };
      "browser.showSavePrompts" = true;
      "browser.theme" = "system";
      "security.authenticatedUnlock.enabled" = true;
      "security.authenticatedUnlock.method" = "system";  # Use system authentication
      "security.autolock.minutes" = 10;
      "security.clipboardClearAfterSeconds" = 90;
    };
  };

  # Environment variables for default browser
  home.sessionVariables = {
    DEFAULT_BROWSER = "chromium";
    BROWSER = "chromium";
  };

  # Shell aliases for convenience
  home.shellAliases = {
    chrome = "chromium";
    browser = "chromium";
  };
}
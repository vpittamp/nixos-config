{ config, pkgs, lib, ... }:

let
  # Detect if we're on M1 or Hetzner based on hostname
  isM1 = config.networking.hostName or "" == "nixos-m1";
  # M1 with HiDPI uses system scaling via GDK_SCALE=2, so no additional scaling needed
  scaleFactor = if isM1 then "1.0" else "1.0";
in
{
  # Chromium browser configuration with 1Password and other extensions
  programs.chromium = {
    enable = true;
    package = pkgs.chromium;
    
    # Extension IDs - These are installed declaratively by Nix
    extensions = [
      { id = "aeblfdkhhhdcdjpifhhbdiojplfjncoa"; }  # 1Password - Password Manager
      { id = "cjpalhdlnbpafiamejdnhcphjbkeiagm"; }  # uBlock Origin
      { id = "eimadpbcbfnmbkopoojfekhnkhdbieeh"; }  # Dark Reader
      { id = "dbepggeogbaibhgnhhndojpepiihcmeb"; }  # Vimium
      { id = "pkehgijcmpdhfbdbbnkijodmdjhbjlgp"; }  # Privacy Badger
    ];
    
    # Command line arguments for better performance and privacy
    commandLineArgs = [
      # Display scaling handled by system environment variables (GDK_SCALE)
      
      # Disable KDE Wallet to prevent errors - use basic password store
      "--password-store=basic"
      
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
      
      # Note: Removed --load-extension flag that was causing "Manifest file missing" error
      # External Extensions are handled automatically by Chromium from the JSON files
      
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

  # Configure Chromium master preferences for first run
  # This ensures extensions are installed and pinned on first launch
  home.file.".config/chromium/initial_preferences.json" = {
    text = builtins.toJSON {
      browser = {
        show_home_button = true;
        check_default_browser = false;
      };
      bookmark_bar = {
        show_on_all_tabs = true;
      };
      extensions = {
        # Pin extensions to toolbar
        toolbar = [
          "aeblfdkhhhdcdjpifhhbdiojplfjncoa"  # 1Password
        ];
        # Settings for specific extensions
        settings = {
          "aeblfdkhhhdcdjpifhhbdiojplfjncoa" = {
            toolbar_pin = "force_pinned";
          };
        };
      };
      # Disable Chrome's password manager since we use 1Password
      credentials_enable_service = false;
      credentials_enable_autosignon = false;
    };
  };
  
  # Extensions are already installed via home.file declarations above
  # No need for an activation script since home-manager handles the files

  # Native messaging host manifest for 1Password
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
      path = "/run/current-system/sw/share/1password/1Password-BrowserSupport";
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
      path = "/run/current-system/sw/share/1password/1Password-BrowserSupport";
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